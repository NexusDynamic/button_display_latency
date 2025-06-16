import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fullscreen/flutter_fullscreen.dart';
import 'package:flutter_refresh_rate_control/flutter_refresh_rate_control.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show WakelockPlus;
import 'widgets/buttons.dart';

/// Button Display Latency Test Application
///
/// A Flutter application designed to measure and compare input detection latency
/// and screen render timing across different button implementation methods.
///
/// This app provides:
/// - Multiple button detection methods (GestureDetector, Listener, etc.)
/// - High-precision timing measurements using microsecond timestamps
/// - Frame-accurate render timing with scheduleFrameCallback
/// - Precise sync pulse generation for external device alignment
/// - Real-time visual feedback indicators
/// - CSV data export for analysis
///
/// The app is optimized for performance testing with:
/// - Full screen mode for maximum screen real estate
/// - High refresh rate support
/// - Wakelock to prevent screen dimming
/// - RepaintBoundary widgets to minimize unnecessary repaints
///
/// For external measurement synchronization, the app generates precise
/// sync pulses using an isolate with busy-wait timing to avoid Dart's
/// async scheduler inaccuracies.

/// Application entry point.
///
/// Initializes the Flutter app with optimal settings for latency testing:
/// - Enables full screen mode for maximum measurement area
/// - Requests high refresh rate for smoother visual feedback
/// - Enables wakelock to prevent interruptions during testing
/// - Sets up localization support
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize localization first
  await EasyLocalization.ensureInitialized();

  // Enable full screen mode for maximum measurement area
  await FullScreen.ensureInitialized();
  FullScreen.setFullScreen(true);

  // Prevent screen from sleeping during testing
  await WakelockPlus.enable();

  // Request high refresh rate for better timing precision
  final refreshRateControl = FlutterRefreshRateControl();
  try {
    bool success = await refreshRateControl.requestHighRefreshRate();
    if (success) {
      if (kDebugMode) {
        print('High refresh rate requested successfully.');
      }
    } else {
      if (kDebugMode) {
        print('Failed to enable high refresh rate');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error requesting high refresh rate: $e');
    }
  }

  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en'), Locale('da')],
      path: 'assets/translations',
      fallbackLocale: Locale('en'),
      useOnlyLangCode: true,
      useFallbackTranslations: true,
      child: const ButtonDisplayLatencyApp(),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title.tr()),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),
              // Button type selection dropdown with repaint boundary
              RepaintBoundary(child: ButtonTypeDropdown()),
              const SizedBox(height: 20),
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
          // Visual indicator for button press (top-right red square)
          DirectPressIndicator(key: StaticButtonFactory.pressIndicatorKey),
          // Visual indicator for sync pulses (top-left red square)
          SyncPulseIndicator(),
        ],
      ),
    );
  }
}
