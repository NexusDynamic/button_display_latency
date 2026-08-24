import 'native_clock.dart';
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
/// - [flashRequested]: Photodiode patch repaint requested (Bela protocol)
/// - [flashPresented]: Frame carrying the patch reached the panel (Bela protocol)
/// - [sessionStart]/[sessionEnd]: Bela session boundaries
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

  /// Photodiode patch repaint requested
  flashRequested,

  /// Frame carrying the photodiode patch was presented
  flashPresented,

  /// Bela measurement session opened
  sessionStart,

  /// Bela measurement session closed
  sessionEnd,
}

/// A single logged event with precise timing information.
///
/// Contains all necessary data to analyze the timing of input→display pipeline:
/// - Event type and timestamp for analysis
/// - Optional button type for comparing different implementations
/// - Optional frame number for correlating with rendering pipeline
/// - The LSL clock reading, so a Flutter-side row can be joined directly
///   against the Bela's CSVs without going through a sync pulse
class LogEvent {
  /// The type of event that occurred.
  final EventType type;

  /// Timestamp in microseconds since logging started.
  ///
  /// Uses [Stopwatch.elapsedMicroseconds] for high precision.
  final int timestampMicros;

  /// The same instant on the LSL clock (`lsl_local_clock`), in seconds.
  ///
  /// This is the app's real time base — see [AppClock]. It is what makes a row
  /// here comparable with a row in the Bela's `_lsl.csv`.
  final double lslClock;

  /// Optional button implementation type that triggered the event.
  ///
  /// Used for comparing latency between different button implementations.
  final String? buttonType;

  /// Optional frame number for render-related events.
  ///
  /// Links events to specific frame render cycles.
  final int? frameNumber;

  /// Trial counter shared by every event of one trial (Bela protocol ch2).
  final int? trial;

  /// Session-wide LSL sample counter for this event, if it was pushed (ch3).
  final int? seq;

  /// Event-specific extra clocks, seconds on the LSL clock. For
  /// [EventType.touchDetected] this is the OS touch timestamp; for
  /// [EventType.flashPresented], the frame's vsync start and raster finish.
  final double? auxA;
  final double? auxB;

  /// Creates a new log event.
  ///
  /// The [type] and [timestampMicros] are required. The remaining fields are
  /// optional and should be provided based on event context.
  LogEvent({
    required this.type,
    required this.timestampMicros,
    this.lslClock = 0.0,
    this.buttonType,
    this.frameNumber,
    this.trial,
    this.seq,
    this.auxA,
    this.auxB,
  });

  static String _clock(double? value) =>
      value == null || value == 0.0 ? '' : value.toStringAsFixed(9);

  /// Returns a CSV-formatted string representation of this event.
  ///
  /// Format: `eventType,timestampMicros,buttonType,frameNumber,lslClock,trial,seq,auxA,auxB`
  /// Empty fields are represented as empty strings.
  @override
  String toString() =>
      '$type,$timestampMicros,${buttonType ?? ''},${frameNumber ?? ''},'
      '${_clock(lslClock)},${trial ?? ''},${seq ?? ''},'
      '${_clock(auxA)},${_clock(auxB)}';
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

  static String buttonType = 'RawPointerDownButton';

  /// Current frame counter for correlating events with render cycles.
  static int _frameCounter = 0;

  /// High-precision stopwatch for microsecond timing.
  static final Stopwatch _stopwatch = Stopwatch()..start();

  /// Session metadata written above the CSV rows on export.
  static final Map<String, String> sessionMetadata = <String, String>{};

  /// Logs a new event with the current timestamp.
  ///
  /// Captures the precise moment when called using [Stopwatch.elapsedMicroseconds].
  /// Frame numbers are automatically assigned for frame-related events.
  ///
  /// Parameters:
  /// - [type]: The type of event being logged
  /// - [buttonType]: Optional button implementation identifier for comparison
  /// - [lslClock]: The LSL-clock instant this event refers to. When omitted,
  ///   the clock is read now; pass it explicitly when the event was observed
  ///   earlier (a touch already timestamped, a frame already presented) so the
  ///   row carries the observation time rather than the logging time.
  ///
  /// Example:
  /// ```dart
  /// PerformanceLogger.logEvent(EventType.touchDetected, buttonType: 'GestureDetector');
  /// ```
  static void logEvent(
    EventType type, {
    String? buttonType,
    double? lslClock,
    int? trial,
    int? seq,
    double? auxA,
    double? auxB,
    int? frameNumber,
  }) {
    _events.add(
      LogEvent(
        type: type,
        timestampMicros: _stopwatch.elapsedMicroseconds,
        lslClock: lslClock ?? AppClock.now(),
        buttonType: buttonType ?? PerformanceLogger.buttonType,
        frameNumber:
            frameNumber ??
            (type == EventType.frameStart || type == EventType.frameEnd
                ? _frameCounter
                : null),
        trial: trial,
        seq: seq,
        auxA: auxA,
        auxB: auxB,
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
  /// Rows are preceded by `# key=value` comment lines carrying the session
  /// metadata — most importantly the measured clock offsets, without which the
  /// `auxA`/`auxB` columns cannot be interpreted.
  static String exportCsv() {
    final buffer = StringBuffer();
    for (final entry in sessionMetadata.entries) {
      buffer.writeln('# ${entry.key}=${entry.value}');
    }
    buffer.writeln(
      'EventType,TimestampMicros,ButtonType,FrameNumber,LslClock,Trial,Seq,AuxA,AuxB',
    );
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
