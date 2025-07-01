import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/logging.dart';
import '../core/sync_pulse.dart';

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
      final paint =
          Paint()
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
