import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import '../core/logging.dart';
import '../core/sync_pulse.dart';
import '../core/timing_session.dart';
import 'button_types.dart';
import 'indicators.dart';
import 'raw_pointer_button.dart';

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
    title: _getButtonTitle('RawPointerDownButton'),
  ).build();
  static final GlobalKey<DirectPressIndicatorState> pressIndicatorKey =
      GlobalKey();

  /// The single entry point for every button implementation.
  ///
  /// The clock reading arrives from the button itself rather than being taken
  /// here, so nothing between the input callback and this line lands inside
  /// the measurement.
  static void onPressed(double observedClock, int hardwareMicros) {
    final session = TimingSession.instance;
    final trial = session.registerTouch(
      observedClock: observedClock,
      hardwareMicros: hardwareMicros,
      buttonType: _currentButtonType,
    );
    // Rejected by the inter-trial lockout: logged, but no trial and no flash.
    if (trial < 0) return;

    if (session.belaMode) {
      // The photodiode patch is the only thing that should change on screen;
      // the legacy indicator would add an unrelated rebuild to the same frame.
      return;
    }

    pressState.press();
    pressIndicatorKey.currentState?.setPressed(true);
    if (_autoRelease) {
      Future.delayed(autoReleaseDelay, () {
        pressState.release();
        pressIndicatorKey.currentState?.setPressed(false);
      });
    }
  }

  static void _release() {
    pressState.release();
    pressIndicatorKey.currentState?.setPressed(false);
  }

  /// Defaults to the lowest-latency implementation; the dropdown exists to
  /// measure how much the others cost.
  static String _currentButtonType = 'RawPointerDownButton';

  /// The button implementation currently under test.
  static String get currentButtonType => _currentButtonType;

  static final button = ButtonService(
    RawPointerDownButton(
      onPressed: onPressed,
      onReleased: _release,
      child: SquareButton(
        title: _getButtonTitle('RawPointerDownButton'),
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
    PerformanceLogger.buttonType = type;
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
          onReleased: _release,
          child: child,
        );

      case 'ListenerPointerDownButton':
        _autoRelease = false;
        return ListenerPointerDownButton(
          onPressed: onPressed,
          onReleased: _release,
          child: child,
        );

      case 'RawPointerDownButton':
        _autoRelease = false;
        return RawPointerDownButton(
          onPressed: onPressed,
          onReleased: _release,
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
    TimingSession.instance.resetTrials();
  }

  static String exportLogs() {
    // Re-read the session so the exported header carries the pointer-epoch
    // cross-check, which only exists once a touch has happened.
    PerformanceLogger.sessionMetadata
      ..clear()
      ..addAll(TimingSession.instance.sessionMetadata());
    return PerformanceLogger.exportCsv();
  }
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
