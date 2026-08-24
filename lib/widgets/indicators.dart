import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/flash_controller.dart';
import '../core/logging.dart';
import '../core/sync_pulse.dart';
import '../core/timing_config.dart';

double _cachedVerticalCenter = -1;
double get verticalCenter {
  if (_cachedVerticalCenter != -1) {
    return _cachedVerticalCenter;
  }
  // First get the FlutterView.
  FlutterView view = WidgetsBinding.instance.platformDispatcher.views.first;

  // Dimensions in logical pixels (dp)
  Size size = view.physicalSize / view.devicePixelRatio;
  _cachedVerticalCenter = size.height / 2; // Cache the value for future use
  return _cachedVerticalCenter; // Adjust the offset as needed
}

class DirectPressIndicatorState extends State<DirectPressIndicator> {
  bool _isPressed = false;

  void setPressed(bool pressed) {
    if (_isPressed != pressed) {
      PerformanceLogger.logEvent(
        pressed ? EventType.displayStart : EventType.displayEnd,
      );

      if (pressed) {
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          PerformanceLogger.logEvent(EventType.frameStart);
          PerformanceLogger.incrementFrame();
        });
        SchedulerBinding.instance.addPostFrameCallback((_) {
          PerformanceLogger.logEvent(EventType.frameEnd);
        });
        SchedulerBinding.instance.scheduleFrame();
      }

      setState(() {
        _isPressed = pressed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: verticalCenter - 50,
      right: 0,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(100, 100),
          painter: SquarePainter(_isPressed),
        ),
      ),
    );
  }
}

class DirectPressIndicator extends StatefulWidget {
  const DirectPressIndicator({super.key});

  @override
  DirectPressIndicatorState createState() => DirectPressIndicatorState();
}

/// The patch the photodiode sits on.
///
/// Deliberately *not* a [StatefulWidget]: the [FlashController] is handed
/// straight to the painter as its `repaint` [Listenable], so a flash is a
/// `markNeedsPaint` on this one render object. No element rebuild, no layout,
/// no `setState` — just a different colour submitted for the frame that is
/// already on its way.
///
/// It is pinned to the top-left corner because panel scanout is row-by-row:
/// a patch further down the screen adds a fixed offset of up to one refresh
/// period to every measurement. The position and size are recorded in the
/// stream header so the residual offset is at least a known constant.
class PhotodiodePatch extends StatelessWidget {
  const PhotodiodePatch({
    super.key,
    required this.controller,
    this.size = TimingConfig.patchSize,
  });

  final FlashController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(size, size),
          painter: FlashPainter(controller),
          isComplex: false,
          willChange: true,
        ),
      ),
    );
  }
}

/// Paints the photodiode patch. Repaints are driven by the [FlashController]
/// passed as `repaint`, never by a rebuild.
class FlashPainter extends CustomPainter {
  FlashPainter(this.controller) : super(repaint: controller);

  final FlashController controller;

  static final Paint _white = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;

  static final Paint _black = Paint()
    ..color = const Color(0xFF000000)
    ..style = PaintingStyle.fill
    ..isAntiAlias = false;

  @override
  void paint(Canvas canvas, Size size) {
    // Always paint: an opaque black patch when idle keeps the photodiode's
    // baseline independent of whatever the app draws behind it, so the rising
    // edge is the largest and cleanest transition available.
    canvas.drawRect(Offset.zero & size, controller.isOn ? _white : _black);
  }

  @override
  bool shouldRepaint(FlashPainter oldDelegate) =>
      oldDelegate.controller != controller;
}

class SyncPulseIndicator extends StatefulWidget {
  const SyncPulseIndicator({super.key});

  @override
  SyncPulseIndicatorState createState() => SyncPulseIndicatorState();
}

class SyncPulseIndicatorState extends State<SyncPulseIndicator> {
  bool _isHigh = false;
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = PreciseSyncPulseGenerator.stateStream.listen((isHigh) {
      if (mounted && _isHigh != isHigh) {
        setState(() => _isHigh = isHigh);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: verticalCenter - 50,
      left: 0,
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(100, 100),
          painter: SquarePainter(_isHigh),
        ),
      ),
    );
  }
}

class SquarePainter extends CustomPainter {
  final bool isPressed;

  SquarePainter(this.isPressed);

  @override
  void paint(Canvas canvas, Size size) {
    if (isPressed) {
      final paint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  @override
  bool shouldRepaint(SquarePainter oldDelegate) {
    return oldDelegate.isPressed != isPressed;
  }
}
