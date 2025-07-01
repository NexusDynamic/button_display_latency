import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import '../core/logging.dart';
import '../core/sync_pulse.dart';
import 'button_types.dart';
import 'indicators.dart';

class SquareButton {
  final double size;
  final Color color;
  final String title;
  final Color textColor;

  const SquareButton({
    this.size = 150.0,
    this.color = Colors.blue,
    this.title = '',
    this.textColor = Colors.white,
  });

  Widget build() {
    return Container(
      width: size,
      height: size,
      color: color,
      alignment: Alignment.center,
      child: Text(
        title,
        style: TextStyle(color: textColor),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class ButtonService extends StateNotifier<BaseButton> {
  ButtonService(super.state);

  void updateButton(BaseButton newButton) {
    state = newButton;
  }

  BaseButton get currentButton => state;
}

class ButtonPressService extends StateNotifier<bool> {
  ButtonPressService() : super(false);

  void togglePressed() {
    state = !state;
  }

  void setPressed(bool pressed) {
    state = pressed;
  }

  void press() {
    state = true;
  }

  void release() {
    state = false;
  }

  bool get pressed => state;
}

class StaticButtonFactory {
  static final pressState = ButtonPressService();
  static bool _autoRelease = true;
  static Duration autoReleaseDelay = Duration(milliseconds: 50);
  static Widget child = SquareButton(
    title: _getButtonTitle('buttonTypes.GestureDetectorTapButton'.tr()),
  ).build();
  static final GlobalKey<DirectPressIndicatorState> pressIndicatorKey =
      GlobalKey();

  static VoidCallback onPressed = () {
    PerformanceLogger.logEvent(
      EventType.touchDetected,
      buttonType: _currentButtonType,
    );
    if (kDebugMode) {
      print('Button pressed!');
    }
    pressState.press();
    pressIndicatorKey.currentState?.setPressed(true);
    if (_autoRelease) {
      Future.delayed(autoReleaseDelay, () {
        pressState.release();
        pressIndicatorKey.currentState?.setPressed(false);
      });
    }
  };

  static String _currentButtonType = 'GestureDetectorTapButton';
  static final button = ButtonService(
    GestureDetectorTapButton(
      onPressed: onPressed,
      child: SquareButton(
        title: 'buttonTypes.GestureDetectorTapButton'.tr(),
      ).build(),
    ),
  );

  /// Gets localized button title for the given type.
  /// Falls back to type name if localization is not available.
  static String _getButtonTitle(String type) {
    try {
      return 'buttonTypes.$type'.tr();
    } catch (e) {
      // Fallback to type name if localization fails
      return type;
    }
  }

  static BaseButton createButton({required String type}) {
    _currentButtonType = type;
    child = SquareButton(title: _getButtonTitle(type)).build();
    switch (type) {
      case 'GestureDetectorTapButton':
        _autoRelease = true;
        return GestureDetectorTapButton(onPressed: onPressed, child: child);
      case 'GestureDetectorTapDownButton':
        _autoRelease = true;
        return GestureDetectorTapDownButton(onPressed: onPressed, child: child);
      case 'RawGestureDetectorTapButton':
        _autoRelease = true;
        return RawGestureDetectorTapButton(onPressed: onPressed, child: child);
      case 'GestureDetectorPanDownButton':
        _autoRelease = false;
        return GestureDetectorPanDownButton(
          onPressed: onPressed,
          onReleased: () {
            pressState.release();
            pressIndicatorKey.currentState?.setPressed(false);
          },
          child: child,
        );

      case 'ListenerPointerDownButton':
        _autoRelease = false;
        return ListenerPointerDownButton(
          onPressed: onPressed,
          onReleased: () {
            pressState.release();
            pressIndicatorKey.currentState?.setPressed(false);
          },
          child: child,
        );
      default:
        throw ArgumentError('Unknown button type: $type');
    }
  }

  // Logging utilities
  static void clearLogs() {
    PerformanceLogger.clear();
    PreciseSyncPulseGenerator.clearSyncEvents();
  }

  static String exportLogs() => PerformanceLogger.exportCsv();
  static List<LogEvent> getLogs() => PerformanceLogger.getEvents();
  static void generateSyncPulse() => PerformanceLogger.generateSyncPulse();

  // Precise sync pulse utilities
  static Future<void> startSyncPulse({
    Duration interval = const Duration(milliseconds: 100),
    Duration pulseDuration = const Duration(milliseconds: 10),
  }) => PreciseSyncPulseGenerator.start(
    interval: interval,
    pulseDuration: pulseDuration,
  );

  static Future<void> stopSyncPulse() => PreciseSyncPulseGenerator.stop();
  static List<LogEvent> getSyncEvents() =>
      PreciseSyncPulseGenerator.getSyncEvents();
}
