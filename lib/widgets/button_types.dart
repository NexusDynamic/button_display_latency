import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/native_clock.dart';

/// Signature for a press observed by a button implementation.
///
/// [observedClock] is the LSL-clock instant the handler ran, read as the very
/// first statement so it carries as little of the handler itself as possible.
/// [hardwareMicros] is the OS's own timestamp for the touch, straight off the
/// pointer event, or -1 when the detection method does not expose one.
///
/// The gap between the two is the "OS reported it" → "Dart saw it" leg of the
/// chain, which is precisely what a gesture arena adds and a raw listener does
/// not — so the button types that cannot supply it are, by construction, the
/// ones where it matters most.
typedef PressHandler = void Function(double observedClock, int hardwareMicros);

abstract class BaseButton extends StatelessWidget {
  final PressHandler onPressed;
  final VoidCallback? onReleased;
  final Widget child;

  const BaseButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.onReleased,
  });
}

class GestureDetectorTapButton extends BaseButton {
  const GestureDetectorTapButton({
    super.key,
    required super.onPressed,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Fires only once the arena resolves, which for a tap means after the
      // pointer is lifted: the slowest option here, and included for contrast.
      onTap: () => onPressed(AppClock.now(), -1),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

class GestureDetectorTapDownButton extends BaseButton {
  const GestureDetectorTapDownButton({
    super.key,
    required super.onPressed,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onPressed(AppClock.now(), -1),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

class RawGestureDetectorTapButton extends BaseButton {
  const RawGestureDetectorTapButton({
    super.key,
    required super.onPressed,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
              (TapGestureRecognizer instance) {
                instance.onTap = () => onPressed(AppClock.now(), -1);
              },
            ),
      },
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

class GestureDetectorPanDownButton extends BaseButton {
  const GestureDetectorPanDownButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.onReleased,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (_) => onPressed(AppClock.now(), -1),
      onPanCancel: onReleased,
      onPanEnd: (_) => onReleased?.call(),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

class ListenerPointerDownButton extends BaseButton {
  const ListenerPointerDownButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.onReleased,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      // No gesture arena, and [PointerDownEvent] still carries the OS
      // timestamp, so this is the fastest path that stays inside the framework.
      onPointerDown: (event) =>
          onPressed(AppClock.now(), event.timeStamp.inMicroseconds),
      onPointerUp: (_) => onReleased?.call(),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
