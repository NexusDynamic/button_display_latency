import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'native_clock.dart';

/// One presented flash, as reported by the engine after the fact.
class FlashPresentation {
  /// The engine frame this flash was painted in.
  final int frameNumber;

  /// `FrameTiming.vsyncStart`, mapped onto the LSL clock.
  final double vsyncStartLsl;

  /// `FrameTiming.rasterFinish`, mapped onto the LSL clock. The closest thing
  /// the framework knows to "the pixels are ready"; the panel then scans it
  /// out row by row, which is why the photodiode patch position is fixed and
  /// recorded.
  final double rasterFinishLsl;

  /// `FrameTiming.rasterFinishWallTime`, mapped onto the LSL clock from the
  /// wall-clock epoch it is reported in.
  final double rasterFinishWallLsl;

  final FrameTiming timing;

  const FlashPresentation({
    required this.frameNumber,
    required this.vsyncStartLsl,
    required this.rasterFinishLsl,
    required this.rasterFinishWallLsl,
    required this.timing,
  });
}

/// Drives the photodiode patch and reports when it actually reached the panel.
///
/// The patch is repainted **without a rebuild**: this object is a [Listenable]
/// handed to the patch's `CustomPainter` as its `repaint` argument, so
/// [requestFlash] goes straight to `markNeedsPaint` on one
/// [RepaintBoundary]-isolated render object. No `setState`, no element
/// rebuild, no layout — the shortest path from "touch observed" to "different
/// pixels submitted" that the framework offers.
///
/// A pointer event is dispatched at the top of a frame, before the build
/// phase, so a flash requested from a pointer handler is painted in *that*
/// frame and presented at its vsync.
class FlashController extends ChangeNotifier {
  FlashController({this.flashDuration = const Duration(milliseconds: 100)});

  /// How long the patch stays white. Fixed, so the falling edge is a second
  /// independent check on the same trial.
  final Duration flashDuration;

  bool _isOn = false;
  Timer? _offTimer;

  /// Frames whose presentation we are still waiting to hear about, keyed by
  /// engine frame number.
  final Map<int, int> _pendingTrials = <int, int>{};

  bool _timingsCallbackInstalled = false;
  bool _keepAliveActive = false;

  /// Called once per flash, when the engine reports the frame's timings. This
  /// is necessarily late — `addTimingsCallback` only fires after the frame —
  /// which is fine: what matters is the timestamps it carries, not when it
  /// arrives.
  void Function(int trial, FlashPresentation presentation)? onPresented;

  /// Whether the patch is currently white.
  bool get isOn => _isOn;

  /// Flashes not yet matched to a `FrameTiming`.
  int get pendingCount => _pendingTrials.length;

  /// Turns the patch white for [flashDuration], and arranges for the
  /// presentation of the frame it lands in to be reported to [onPresented].
  ///
  /// Returns the LSL clock reading taken immediately after the repaint was
  /// requested, i.e. the `FLASH_REQUESTED` instant.
  double requestFlash(int trial) {
    _installTimingsCallback();

    _isOn = true;
    // -> RenderCustomPaint.markNeedsPaint, which also requests a visual
    // update, so no explicit scheduleFrame is needed.
    notifyListeners();
    final requestedAt = AppClock.now();

    // Runs at the end of the frame this flash is painted in, which is where
    // the engine frame number for that frame is readable.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final frameNumber = PlatformDispatcher.instance.frameData.frameNumber;
      _pendingTrials[frameNumber] = trial;
    });

    _offTimer?.cancel();
    _offTimer = Timer(flashDuration, _turnOff);

    return requestedAt;
  }

  void _turnOff() {
    _offTimer = null;
    if (!_isOn) return;
    _isOn = false;
    notifyListeners();
  }

  void _installTimingsCallback() {
    if (_timingsCallbackInstalled) return;
    _timingsCallbackInstalled = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_pendingTrials.isEmpty) return;
    final offsets = ClockOffsets.measured ? ClockOffsets.instance : null;
    for (final timing in timings) {
      final trial = _pendingTrials.remove(timing.frameNumber);
      if (trial == null) continue;
      final callback = onPresented;
      if (callback == null) continue;
      double toLsl(int phaseMicros, bool wallClock) {
        if (offsets == null) return 0.0;
        final offset = wallClock ? offsets.wall : offsets.engine;
        if (!offset.valid) return 0.0;
        return offset.toLsl(phaseMicros * 1e-6);
      }

      callback(
        trial,
        FlashPresentation(
          frameNumber: timing.frameNumber,
          vsyncStartLsl: toLsl(
            timing.timestampInMicroseconds(FramePhase.vsyncStart),
            false,
          ),
          rasterFinishLsl: toLsl(
            timing.timestampInMicroseconds(FramePhase.rasterFinish),
            false,
          ),
          rasterFinishWallLsl: toLsl(
            timing.timestampInMicroseconds(FramePhase.rasterFinishWallTime),
            true,
          ),
          timing: timing,
        ),
      );
    }
    // A flash whose frame never reported (dropped, or the callback batch was
    // trimmed) would otherwise leak. Anything older than the newest reported
    // frame is never coming.
    if (_pendingTrials.isNotEmpty && timings.isNotEmpty) {
      final newest = timings.last.frameNumber;
      _pendingTrials.removeWhere((frame, _) => frame < newest - 2);
    }
  }

  /// Keeps the compositor producing frames continuously.
  ///
  /// A ProMotion panel drops its refresh rate when nothing is animating and
  /// ramps back up on interaction, which injects variable latency into every
  /// trial — the one thing the spec says cannot be fixed after the fact. An
  /// unconditional frame loop pins the display at its maximum rate, so the
  /// wait from "flash requested" to "vsync" is always one refresh period and
  /// never a ramp.
  void startFrameKeepAlive() {
    if (_keepAliveActive) return;
    _keepAliveActive = true;
    _scheduleKeepAliveFrame(false);
  }

  void stopFrameKeepAlive() => _keepAliveActive = false;

  bool get frameKeepAliveActive => _keepAliveActive;

  void _scheduleKeepAliveFrame(bool rescheduling) {
    if (!_keepAliveActive) return;
    SchedulerBinding.instance.scheduleFrameCallback(
      (_) => _scheduleKeepAliveFrame(true),
      rescheduling: rescheduling,
    );
  }

  @override
  void dispose() {
    _keepAliveActive = false;
    _offTimer?.cancel();
    if (_timingsCallbackInstalled) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _timingsCallbackInstalled = false;
    }
    super.dispose();
  }
}
