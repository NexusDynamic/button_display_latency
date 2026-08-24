import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show WakelockPlus;

import 'core/lsl_timing.dart';
import 'core/timing_config.dart';
import 'widgets/buttons.dart';

/// Button Display Latency Test Application
///
/// A Flutter application designed to measure and compare input detection latency
/// and screen render timing across different button implementation methods, and
/// to act as the iPad end of the Bela timing rig in `bela-lsl-timing`.
///
/// This app provides:
/// - Multiple button detection methods, from a raw pointer-packet hook up to
///   full gesture recognisers, so the cost of each can be measured
/// - High-precision timing on the LSL clock, shared with the Bela
/// - Frame-accurate presentation times from `FrameTiming`
/// - An optional LSL outlet implementing the Bela's Flutter outlet spec
/// - Precise sync pulse generation for external device alignment
/// - CSV data export for analysis
///
/// The app is optimized for latency measurement with:
/// - Full screen mode for maximum screen real estate
/// - The display pinned at its maximum refresh rate (see
///   [FlashController.startFrameKeepAlive]) rather than left to ramp
/// - Wakelock to prevent screen dimming
/// - A photodiode patch that repaints without rebuilding or laying out
///
/// LSL is entirely optional: with it off the app never touches the network and
/// behaves exactly as a stand-alone latency logger.

/// Application entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must precede every other liblsl call, including the first clock read, and
  // is applied unconditionally so that turning the outlet on later still gets
  // the intended network configuration.
  LslTimingService.configure();

  // Initialize localization first
  await EasyLocalization.ensureInitialized();

  // Android-only, and a hard failure elsewhere; the doze exemption keeps the
  // scheduler from throttling frames mid-session.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await Permission.ignoreBatteryOptimizations.request();
  }

  // Enable full screen mode for maximum measurement area
  await FullScreen.ensureInitialized();
  FullScreen.setFullScreen(true);

  // Prevent screen from sleeping during testing
  await WakelockPlus.enable();

  // Request high refresh rate for better timing precision. On a ProMotion iPad
  // this raises the *ceiling*; what actually holds the panel at 120 Hz is the
  // continuous frame loop the session starts in Bela mode, because an idle
  // display ramps down and a ramp-up on touch is variable latency in every
  // trial.
  final refreshRateControl = FlutterRefreshRateControl();
  try {
    final bool success = await refreshRateControl.requestHighRefreshRate();
    if (!success) {
      debugPrint('Failed to enable high refresh rate');
    }
  } catch (e) {
    debugPrint('Error requesting high refresh rate: $e');
  }

  // Measures the clock offsets and reads the display's capabilities. Must
  // happen before the first trial and never on the input path.
  await TimingSession.instance.warmUp(refreshRateControl);

  if (TimingConfig.lslEnabledByDefault) {
    await TimingSession.instance.setBelaMode(true);
  }

  runApp(
    ExcludeSemantics(
      excluding: true,
      child: EasyLocalization(
        supportedLocales: [Locale('en'), Locale('da')],
        path: 'assets/translations',
        fallbackLocale: Locale('en'),
        useOnlyLangCode: true,
        useFallbackTranslations: true,
        child: const ButtonDisplayLatencyApp(),
      ),
    ),
  );
}

/// Root application widget for the Button Display Latency test app.
///
/// Sets up the necessary providers for state management and configures
/// the MaterialApp with a dark theme optimized for testing visibility.
///
/// Uses [MultiProvider] to provide:
/// - [ButtonService]: Manages the current button implementation
/// - [ButtonPressService]: Tracks button press state
class ButtonDisplayLatencyApp extends StatelessWidget {
  /// Creates a [ButtonDisplayLatencyApp].
  const ButtonDisplayLatencyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provides the current button implementation
        StateNotifierProvider<ButtonService, BaseButton>(
          create: (_) => StaticButtonFactory.button,
        ),
        // Provides the button press state for visual feedback
        StateNotifierProvider<ButtonPressService, bool>(
          create: (_) => StaticButtonFactory.pressState,
        ),
      ],
      child: MaterialApp(
        title: 'Button Display Latency App',
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        // Dark theme for better contrast during testing
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
        ),
        home: const BDLHome(title: 'title'),
      ),
    );
  }
}

/// Home screen widget for the Button Display Latency test application.
///
/// Displays the main testing interface with:
/// - Button type selection dropdown
/// - Bela protocol and LSL controls
/// - Logging control buttons
/// - Test button in the center
/// - Visual indicators for button press and sync pulses
///
/// The layout is optimized for testing with [RepaintBoundary] widgets
/// to minimize unnecessary redraws and improve timing accuracy.
class BDLHome extends StatelessWidget {
  /// Creates a [BDLHome] widget.
  ///
  /// The [title] parameter sets the app bar title.
  const BDLHome({super.key, required this.title});

  /// The title displayed in the app bar.
  final String title;

  @override
  Widget build(BuildContext context) {
    final session = TimingSession.instance;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title.tr()),
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final belaMode = session.belaMode;
          return Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 20),
                  // Button type selection dropdown with repaint boundary
                  RepaintBoundary(child: ButtonTypeDropdown()),
                  const SizedBox(height: 8),
                  const RepaintBoundary(child: BelaControls()),
                  const SizedBox(height: 12),
                  // Control buttons for logging and sync operations
                  LoggingControls(),
                  const SizedBox(height: 40),
                  // Main test button area
                  Expanded(
                    child: Center(
                      child: RepaintBoundary(
                        child: Consumer<BaseButton>(
                          builder: (context, button, _) =>
                              RepaintBoundary(child: button),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (belaMode)
                // The photodiode patch. Painted last so nothing overlaps it.
                PhotodiodePatch(controller: session.flash)
              else ...[
                // Visual indicator for button press (right, vertical centre)
                DirectPressIndicator(key: StaticButtonFactory.pressIndicatorKey),
                // Visual indicator for sync pulses (left, vertical centre)
                SyncPulseIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}
