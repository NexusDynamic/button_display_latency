import 'sync_pulse.dart';

/// Types of events that can be logged in the performance testing system.
///
/// Each event type represents a specific point in the input→display pipeline:
/// - [touchDetected]: When touch input is first detected by the button
/// - [frameStart]: Beginning of frame rendering (scheduleFrameCallback)
/// - [frameEnd]: End of frame rendering (addPostFrameCallback)
/// - [displayStart]: When visual feedback starts (setState called)
/// - [displayEnd]: When visual feedback ends (setState called)
/// - [syncPulse]: Sync signal for external device alignment
enum EventType {
  /// Touch input detected by button handler
  touchDetected,

  /// Frame rendering started
  frameStart,

  /// Frame rendering completed
  frameEnd,

  /// Visual display feedback started
  displayStart,

  /// Visual display feedback ended
  displayEnd,

  /// Synchronization pulse for external device alignment
  syncPulse,
}

/// A single logged event with precise timing information.
///
/// Contains all necessary data to analyze the timing of input→display pipeline:
/// - Event type and timestamp for analysis
/// - Optional button type for comparing different implementations
/// - Optional frame number for correlating with rendering pipeline
class LogEvent {
  /// The type of event that occurred.
  final EventType type;

  /// Timestamp in microseconds since logging started.
  ///
  /// Uses [Stopwatch.elapsedMicroseconds] for high precision.
  final int timestampMicros;

  /// Optional button implementation type that triggered the event.
  ///
  /// Used for comparing latency between different button implementations.
  final String? buttonType;

  /// Optional frame number for render-related events.
  ///
  /// Links events to specific frame render cycles.
  final int? frameNumber;

  /// Creates a new log event.
  ///
  /// The [type] and [timestampMicros] are required. The [buttonType] and
  /// [frameNumber] are optional and should be provided based on event context.
  LogEvent({
    required this.type,
    required this.timestampMicros,
    this.buttonType,
    this.frameNumber,
  });

  /// Returns a CSV-formatted string representation of this event.
  ///
  /// Format: `eventType,timestampMicros,buttonType,frameNumber`
  /// Empty fields are represented as empty strings.
  @override
  String toString() =>
      '$type,$timestampMicros,${buttonType ?? ''},${frameNumber ?? ''}';
}

/// High-performance event logging system for latency measurement.
///
/// Example usage:
/// ```dart
/// // Start logging
/// PerformanceLogger.clear();
///
/// // Log events
/// PerformanceLogger.logEvent(EventType.touchDetected, buttonType: 'GestureDetector');
/// PerformanceLogger.logEvent(EventType.displayStart);
///
/// // Export data
/// final csvData = PerformanceLogger.exportCsv();
/// ```
class PerformanceLogger {
  /// Internal list of logged events. Use [getEvents] for safe access.
  static final List<LogEvent> _events = <LogEvent>[];

  static String buttonType = 'GestureDetectorTapButton';

  /// Current frame counter for correlating events with render cycles.
  static int _frameCounter = 0;

  /// High-precision stopwatch for microsecond timing.
  static final Stopwatch _stopwatch = Stopwatch()..start();

  /// Logs a new event with the current timestamp.
  ///
  /// Captures the precise moment when called using [Stopwatch.elapsedMicroseconds].
  /// Frame numbers are automatically assigned for frame-related events.
  ///
  /// Parameters:
  /// - [type]: The type of event being logged
  /// - [buttonType]: Optional button implementation identifier for comparison
  ///
  /// Example:
  /// ```dart
  /// PerformanceLogger.logEvent(EventType.touchDetected, buttonType: 'GestureDetector');
  /// ```
  static void logEvent(EventType type, {String? buttonType}) {
    _events.add(
      LogEvent(
        type: type,
        timestampMicros: _stopwatch.elapsedMicroseconds,
        buttonType: buttonType ?? PerformanceLogger.buttonType,
        frameNumber: type == EventType.frameStart || type == EventType.frameEnd
            ? _frameCounter
            : null,
      ),
    );
  }

  /// Increments the frame counter for frame-related event correlation.
  ///
  /// Should be called once per frame in SchedulerBinding.scheduleFrameCallback.
  static void incrementFrame() => _frameCounter++;

  /// Returns an unmodifiable list of all logged events.
  ///
  /// Events are returned in chronological order based on when they were logged.
  /// Use this for analysis or custom export formats.
  static List<LogEvent> getEvents() => List.unmodifiable(_events);

  /// Clears all logged events and resets timing.
  ///
  /// Resets the internal stopwatch and frame counter to start fresh timing.
  /// Call this before starting a new test session.
  static void clear() {
    _events.clear();
    _frameCounter = 0;
    _stopwatch.reset();
    _stopwatch.start();
  }

  /// Exports all logged events as CSV data.
  ///
  /// Returns a string containing CSV-formatted data with headers:
  /// `EventType,TimestampMicros,ButtonType,FrameNumber`
  ///
  /// This format is suitable for analysis in spreadsheet applications
  /// or data analysis tools.
  static String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln('EventType,TimestampMicros,ButtonType,FrameNumber');
    for (final event in _events) {
      buffer.writeln(event.toString());
    }
    return buffer.toString();
  }

  /// Logs a single synchronization pulse event with visual feedback.
  ///
  /// Used for creating reference points that can be detected by
  /// external measurement devices for time alignment.
  /// Also triggers a brief visual flash of the sync pulse indicator.
  static void generateSyncPulse() {
    logEvent(EventType.syncPulse);
    // Also trigger visual feedback through the sync pulse generator
    PreciseSyncPulseGenerator.triggerSinglePulse();
  }

  /// Generates a distinctive pattern of sync pulses for device alignment.
  ///
  /// Creates a recognizable pattern:
  /// - 3 short pulses (100ms apart)
  /// - 500ms pause
  /// - 2 long pulses (300ms apart)
  ///
  /// This pattern can be detected by external devices to establish
  /// time synchronization between the app and external measurements.
  ///
  /// **Note**: Uses `Future.delayed` which may have timing inaccuracies.
  /// For precise timing, use [PreciseSyncPulseGenerator] instead.
  static void generateSyncPattern() async {
    // Short pulse pattern
    for (int i = 0; i < 3; i++) {
      generateSyncPulse();
      await Future.delayed(Duration(milliseconds: 100));
    }
    // Pause
    await Future.delayed(Duration(milliseconds: 500));
    // Long pulse pattern
    for (int i = 0; i < 2; i++) {
      generateSyncPulse();
      await Future.delayed(Duration(milliseconds: 300));
    }
  }

  /// Calculates time offset between app events and external device timestamps.
  ///
  /// Compares sync pulse timestamps from the app with corresponding
  /// timestamps from an external measurement device to determine
  /// the time alignment offset.
  ///
  /// Parameters:
  /// - [externalTimestamps]: List of timestamps from external device
  ///
  /// Returns the offset in microseconds that should be applied to
  /// align external timestamps with app timestamps.
  ///
  /// Returns 0 if no sync events are available for comparison.
  static int calculateTimeOffset(List<int> externalTimestamps) {
    final appSyncEvents = _events
        .where((e) => e.type == EventType.syncPulse)
        .toList();
    if (appSyncEvents.isEmpty || externalTimestamps.isEmpty) return 0;

    // Use first sync event for alignment
    return externalTimestamps.first - appSyncEvents.first.timestampMicros;
  }
}
