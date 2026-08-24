import 'dart:ui'
    show PointerChange, PointerData, PointerDataPacket, PointerDataPacketCallback;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/native_clock.dart';
import 'button_types.dart';

/// The lowest-latency input path Dart can reach.
///
/// Every other button type in this app is handled *after* the framework has
/// converted the raw packet into [PointerEvent]s, walked the hit-test path and
/// (for the gesture recognisers) resolved a gesture arena. This one taps
/// `PlatformDispatcher.onPointerDataPacket`, which is the first Dart code that
/// runs for a touch: the callback the engine itself invokes.
///
/// The cost is that hit testing is ours to do — hence the cached rectangle in
/// physical pixels. That is a fair trade here, because the widget under test
/// is one fixed square, and it removes the framework's dispatch from the
/// measured interval entirely.
///
/// The original handler is always invoked afterwards, so the rest of the app
/// (and the widget tree) still sees a completely normal event stream. It runs
/// *after* our callback deliberately: [GestureBinding] dispatches synchronously,
/// so forwarding first would put the whole framework dispatch inside the
/// interval we are trying to measure.
class RawPointerDownButton extends BaseButton {
  const RawPointerDownButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.onReleased,
  });

  @override
  Widget build(BuildContext context) {
    return _RawPointerRegion(
      onPressed: onPressed,
      onReleased: onReleased,
      child: child,
    );
  }
}

class _RawPointerRegion extends StatefulWidget {
  const _RawPointerRegion({
    required this.onPressed,
    required this.onReleased,
    required this.child,
  });

  final PressHandler onPressed;
  final VoidCallback? onReleased;
  final Widget child;

  @override
  State<_RawPointerRegion> createState() => _RawPointerRegionState();
}

class _RawPointerRegionState extends State<_RawPointerRegion>
    with WidgetsBindingObserver {
  final GlobalKey _regionKey = GlobalKey();

  PointerDataPacketCallback? _previousHandler;
  Rect? _physicalRect;
  int? _activePointer;
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _install();
  }

  @override
  void dispose() {
    _uninstall();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Rotation or a size change moves the button; the cached rect is stale.
    _physicalRect = null;
    SchedulerBinding.instance.addPostFrameCallback((_) => _refreshRect());
  }

  void _install() {
    if (_installed) return;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    _previousHandler = dispatcher.onPointerDataPacket;
    dispatcher.onPointerDataPacket = _handlePacket;
    _installed = true;
  }

  void _uninstall() {
    if (!_installed) return;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    // Only restore if nothing else has chained on top of us in the meantime.
    if (dispatcher.onPointerDataPacket == _handlePacket) {
      dispatcher.onPointerDataPacket = _previousHandler;
    }
    _previousHandler = null;
    _installed = false;
  }

  /// Caches the button's rectangle in physical pixels, which is the coordinate
  /// space raw [PointerData] arrives in. Done off the input path.
  void _refreshRect() {
    final context = _regionKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final view = View.maybeOf(context!);
    final ratio = view?.devicePixelRatio ?? 1.0;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    _physicalRect = Rect.fromLTWH(
      topLeft.dx * ratio,
      topLeft.dy * ratio,
      renderObject.size.width * ratio,
      renderObject.size.height * ratio,
    );
  }

  bool _hit(PointerData data) {
    final rect = _physicalRect;
    if (rect == null) {
      _refreshRect();
      final refreshed = _physicalRect;
      if (refreshed == null) return false;
      return refreshed.contains(Offset(data.physicalX, data.physicalY));
    }
    return rect.contains(Offset(data.physicalX, data.physicalY));
  }

  void _handlePacket(PointerDataPacket packet) {
    // First statement: this is the earliest instant Dart can attribute to the
    // touch, and it is what goes on the wire as `event_clock`.
    final double observedClock = AppClock.now();

    final List<PointerData> data = packet.data;
    for (int i = 0; i < data.length; i++) {
      final PointerData datum = data[i];
      if (datum.synthesized) continue;
      switch (datum.change) {
        case PointerChange.down:
          if (_activePointer == null && _hit(datum)) {
            _activePointer = datum.pointerIdentifier;
            widget.onPressed(observedClock, datum.timeStamp.inMicroseconds);
          }
        case PointerChange.up:
        case PointerChange.cancel:
          if (_activePointer == datum.pointerIdentifier) {
            _activePointer = null;
            widget.onReleased?.call();
          }
        default:
          break;
      }
    }

    _previousHandler?.call(packet);
  }

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) => _refreshRect());
    return KeyedSubtree(key: _regionKey, child: widget.child);
  }
}
