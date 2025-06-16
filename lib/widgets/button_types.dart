import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

abstract class BaseButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const BaseButton({super.key, required this.onPressed, required this.child});
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
      onTap: onPressed,
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
      onTapDown: (_) => onPressed(),
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
                instance.onTap = onPressed;
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
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (_) => onPressed(),
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
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPressed(),
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
