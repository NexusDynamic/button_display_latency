import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';

import 'bela_protocol.dart';
import 'flash_controller.dart';
import 'logging.dart';
import 'lsl_timing.dart';
import 'native_clock.dart';
import 'timing_config.dart';

/// Owns one measurement session: trial numbering, the photodiode flash, and
/// the optional LSL outlet that the Bela rig listens to.
///
/// The whole chain the Bela measures is visible in [registerTouch]: the order
/// of operations there is the app's latency contract, and the comments explain
/// why each step sits where it does.
class TimingSession extends ChangeNotifier {
  TimingSession._()
    : flash = FlashController(
        flashDuration: Duration(milliseconds: TimingConfig.flashMillis),
      ) {
    flash.onPresented = _onFlashPresented;
  }

  static final TimingSession instance = TimingSession._();

  /// Drives the photodiode patch.
  final FlashController flash;

  /// The optional LSL side. Never assume it is running.
  final LslTimingService lsl = LslTimingService();

  int _trial = 0;
  double _lastTrialClock = 0.0;
  int _rejectedTouches = 0;
  double? _lastDispatchSeconds;
  int _firstTouchHardwareMicros = -1;
  double _firstTouchObservedClock = 0.0;
  bool _belaMode = false;
  bool _lslRequested = TimingConfig.lslEnabledByDefault;
  Map<String, dynamic> _refreshRateInfo = const <String, dynamic>{};

  /// Trials opened so far.
  int get trial => _trial;

  /// Touches ignored by the inter-trial lockout.
  int get rejectedTouches => _rejectedTouches;

  /// The most recent OS-report -> Dart-handler gap, in seconds: how long the
  /// platform took to deliver the touch. Null until a touch carries a hardware
  /// timestamp. A plausible few milliseconds here is also the live proof that
  /// the pointer clock mapping is the right one.
  double? get lastDispatchSeconds => _lastDispatchSeconds;

  /// Whether the Bela protocol is active: photodiode patch shown, frames
  /// pinned at the panel's maximum rate, raw pointer path installed.
  bool get belaMode => _belaMode;

  /// Whether the user has asked for an LSL outlet.
  bool get lslRequested => _lslRequested;

  bool get lslRunning => lsl.isRunning;

  Duration get minTrialInterval =>
      Duration(milliseconds: TimingConfig.minTrialIntervalMillis);

  /// Measures the clock offsets and reads the display's capabilities.
  ///
  /// Runs once at startup, off the input path — [ClockOffsets.measure] takes a
  /// few hundred microseconds and must never land inside a trial.
  Future<void> warmUp(FlutterRefreshRateControl refreshRateControl) async {
    ClockOffsets.measure();
    try {
      _refreshRateInfo = await refreshRateControl.getRefreshRateInfo();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Could not read refresh rate info: $e');
      }
    }
    PerformanceLogger.sessionMetadata.addAll(sessionMetadata());
    notifyListeners();
  }

  /// The reported display refresh rate, or null when unavailable.
  double? get refreshHz {
    final value =
        _refreshRateInfo['maximumFramesPerSecond'] ??
        _refreshRateInfo['currentRefreshRate'] ??
        _refreshRateInfo['currentFramesPerSecond'];
    if (value is num) return value.toDouble();
    return null;
  }

  /// Everything worth freezing into the permanent record of the run. The Bela
  /// writes the stream header verbatim to `<session>_stream.xml`, and the same
  /// map is emitted as `#` comments at the head of the exported CSV.
  Map<String, String> sessionMetadata() {
    final hz = refreshHz;
    return <String, String>{
      'app_name': 'button_display_latency',
      'app_version': TimingConfig.appVersion,
      'device_model': TimingConfig.deviceModel.isNotEmpty
          ? TimingConfig.deviceModel
          : defaultTargetPlatform.name,
      'device_name': TimingConfig.sourceId,
      'os_version': Platform.operatingSystemVersion,
      'display_refresh_hz': hz == null ? 'unknown' : hz.toStringAsFixed(1),
      'display_refresh_pinned': flash.frameKeepAliveActive.toString(),
      'patch_position': 'top-left corner, 0px from top',
      'patch_size_px':
          '${TimingConfig.patchSize.toStringAsFixed(0)}x${TimingConfig.patchSize.toStringAsFixed(0)}',
      'flash_duration_ms': TimingConfig.flashMillis.toString(),
      'min_trial_interval_ms': TimingConfig.minTrialIntervalMillis.toString(),
      'button_type': PerformanceLogger.buttonType,
      // Every foreign timestamp the app emits (ch4/ch5) has already been
      // mapped onto the LSL clock with these; they are recorded so the mapping
      // can be audited or undone offline.
      'aux_epoch': 'lsl_local_clock',
      if (TimingConfig.note.isNotEmpty) 'note': TimingConfig.note,
      ...ClockOffsets.measured
          ? ClockOffsets.instance.describe()
          : const <String, String>{},
      ..._pointerEpochCheck(),
    };
  }

  /// Records, for the first touch of the session, how far the OS timestamp
  /// lands from the observation instant under *every* measured clock. The
  /// chosen mapping should show a few milliseconds; the others will be out by
  /// the machine's uptime or the whole Unix epoch.
  Map<String, String> _pointerEpochCheck() {
    if (_firstTouchHardwareMicros < 0 || !ClockOffsets.measured) {
      return const <String, String>{};
    }
    final candidates = ClockOffsets.instance.pointerEpochCandidates(
      _firstTouchHardwareMicros * 1e-6,
      _firstTouchObservedClock,
    );
    return <String, String>{
      for (final entry in candidates.entries)
        'pointer_dispatch_under_${entry.key.name}_s': entry.value
            .toStringAsFixed(9),
    };
  }

  /// Opens a trial for a touch, or rejects it if it came too soon.
  ///
  /// [observedClock] must be read by the caller as the *first* statement of the
  /// input handler, and [hardwareMicros] is the OS touch timestamp straight
  /// from the pointer event (-1 when the input path does not carry one).
  ///
  /// Returns the trial number, or -1 if the touch was rejected.
  int registerTouch({
    required double observedClock,
    required int hardwareMicros,
    String? buttonType,
  }) {
    final lockout = TimingConfig.minTrialIntervalMillis;
    if (lockout > 0 &&
        _lastTrialClock != 0.0 &&
        (observedClock - _lastTrialClock) * 1000.0 < lockout) {
      // Logged but not pushed and not flashed: an FSR edge with no matching
      // trial is then unambiguously a false trigger or a bounce offline,
      // rather than a judgement call about time windows.
      _rejectedTouches++;
      PerformanceLogger.logEvent(
        EventType.touchDetected,
        buttonType: buttonType,
        lslClock: observedClock,
        trial: -1,
      );
      return -1;
    }

    _lastTrialClock = observedClock;
    final trial = ++_trial;

    // 1. Mark the patch dirty first. This is a markNeedsPaint on one
    //    RepaintBoundary — no rebuild, no layout — and it is the only step
    //    that can miss the frame we are trying to land on, so nothing goes
    //    before it.
    final requestedClock = flash.requestFlash(trial);

    // 2. Then the network. Both samples carry the instant they describe as an
    //    explicit timestamp, so a few microseconds spent here cannot smear the
    //    measurement; the frame is already scheduled either way.
    // 0 rather than NaN when unavailable: NaN round-trips badly through CSV,
    // and the spec asks for unused fields to be zero.
    final hardwareClock = hardwareMicros >= 0 && ClockOffsets.measured
        ? ClockOffsets.instance.pointer.toLsl(hardwareMicros * 1e-6)
        : 0.0;
    if (hardwareClock != 0.0) {
      _lastDispatchSeconds = observedClock - hardwareClock;
      if (_firstTouchHardwareMicros < 0) {
        // Kept raw; the per-clock comparison is done lazily off the hot path.
        _firstTouchHardwareMicros = hardwareMicros;
        _firstTouchObservedClock = observedClock;
      }
    }
    final touchSeq = lsl.pushEvent(
      BelaEvent.touchRegistered,
      eventClock: observedClock,
      trial: trial,
      auxA: hardwareClock,
    );
    final flashSeq = lsl.pushEvent(
      BelaEvent.flashRequested,
      eventClock: requestedClock,
      trial: trial,
    );

    // 3. Local logging last: it allocates, and nothing downstream waits on it.
    PerformanceLogger.logEvent(
      EventType.touchDetected,
      buttonType: buttonType,
      lslClock: observedClock,
      trial: trial,
      seq: touchSeq >= 0 ? touchSeq : null,
      auxA: hardwareClock,
    );
    PerformanceLogger.logEvent(
      EventType.flashRequested,
      buttonType: buttonType,
      lslClock: requestedClock,
      trial: trial,
      seq: flashSeq >= 0 ? flashSeq : null,
    );

    // Deliberately no notifyListeners() here: a listener would mark widgets
    // dirty and add a rebuild to the very frame the flash has to land in.
    // Counters are read on demand by the status panel instead.
    return trial;
  }

  void _onFlashPresented(int trial, FlashPresentation presentation) {
    assert(() {
      debugPrint(
        'PRESENTED trial=$trial frame=${presentation.frameNumber} '
        'vsync=${presentation.vsyncStartLsl.toStringAsFixed(6)} '
        'raster=${presentation.rasterFinishLsl.toStringAsFixed(6)} '
        'wall=${presentation.rasterFinishWallLsl.toStringAsFixed(6)}',
      );
      return true;
    }());
    final seq = lsl.pushEvent(
      BelaEvent.flashPresented,
      // The best estimate of "the pixels were ready"; the panel scans them out
      // from there, which is why the patch position is fixed and recorded.
      eventClock: presentation.rasterFinishLsl,
      trial: trial,
      auxA: presentation.vsyncStartLsl,
      auxB: presentation.rasterFinishWallLsl,
    );
    PerformanceLogger.logEvent(
      EventType.flashPresented,
      lslClock: presentation.rasterFinishLsl,
      trial: trial,
      seq: seq >= 0 ? seq : null,
      auxA: presentation.vsyncStartLsl,
      auxB: presentation.rasterFinishWallLsl,
      frameNumber: presentation.frameNumber,
    );
  }

  /// Turns the Bela protocol on or off.
  Future<void> setBelaMode(bool enabled) async {
    if (_belaMode == enabled) return;
    _belaMode = enabled;
    if (enabled) {
      flash.startFrameKeepAlive();
      if (_lslRequested) await _startLsl();
    } else {
      flash.stopFrameKeepAlive();
      await _stopLsl();
    }
    notifyListeners();
  }

  /// Turns the LSL outlet on or off. Independent of [belaMode] so the display
  /// side can be exercised with no network at all.
  Future<void> setLslEnabled(bool enabled) async {
    _lslRequested = enabled;
    if (enabled) {
      await _startLsl();
    } else {
      await _stopLsl();
    }
    notifyListeners();
  }

  Future<void> _startLsl() async {
    if (lsl.isRunning) return;
    try {
      await lsl.start(extraMetadata: sessionMetadata());
      PerformanceLogger.logEvent(EventType.sessionStart, trial: _trial);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Could not start LSL outlet: $e');
      }
      _lslRequested = false;
    }
    notifyListeners();
  }

  Future<void> _stopLsl() async {
    if (!lsl.isRunning) return;
    PerformanceLogger.logEvent(EventType.sessionEnd, trial: _trial);
    await lsl.stop(trial: _trial);
    notifyListeners();
  }

  /// Resets trial and rejection counters. Does not touch the outlet: `seq` is
  /// session-wide by design, so gaps in it stay meaningful.
  void resetTrials() {
    _trial = 0;
    _lastTrialClock = 0.0;
    _rejectedTouches = 0;
    notifyListeners();
  }
}
