import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'logging.dart';

void runPreciseInterval<T>(
  Duration interval,
  T Function(T state) callback, {
  required Completer<void> completer,
  dynamic state,
  Duration startBusyAt = const Duration(milliseconds: 1),
}) {
  final sw = Stopwatch()..start();

  for (int i = 1; true; i++) {
    final nextAwake = interval * i;
    final toSleep = (nextAwake - sw.elapsed) - startBusyAt;
    if (toSleep > Duration.zero) {
      sleep(toSleep);
    }

    while (sw.elapsed < nextAwake) {}

    state = callback(state);
    if (completer.isCompleted) {
      break;
    }
  }
}

class SyncPulseIsolateData {
  final SendPort sendPort;
  final Duration interval;
  final Duration pulseDuration;

  SyncPulseIsolateData({
    required this.sendPort,
    required this.interval,
    required this.pulseDuration,
  });
}

class SyncPulseState {
  bool isHigh;
  int pulseCount;
  Stopwatch pulseTimer;

  SyncPulseState({this.isHigh = false, this.pulseCount = 0})
    : pulseTimer = Stopwatch();
}

void syncPulseIsolate(SyncPulseIsolateData data) {
  final completer = Completer<void>();
  final sw = Stopwatch()..start();

  runPreciseInterval<SyncPulseState>(
    data.interval,
    (state) {
      final currentTime = sw.elapsedMicroseconds;

      if (!state.isHigh) {
        state.isHigh = true;
        state.pulseTimer.reset();
        state.pulseTimer.start();
        state.pulseCount++;

        data.sendPort.send({
          'type': 'pulse_start',
          'timestamp': currentTime,
          'pulseCount': state.pulseCount,
        });
      } else if (state.pulseTimer.elapsed >= data.pulseDuration) {
        state.isHigh = false;
        state.pulseTimer.stop();

        data.sendPort.send({
          'type': 'pulse_end',
          'timestamp': currentTime,
          'pulseCount': state.pulseCount,
        });
      }

      data.sendPort.send({
        'type': 'state_update',
        'isHigh': state.isHigh,
        'timestamp': currentTime,
      });

      return state;
    },
    completer: completer,
    state: SyncPulseState(),
  );
}

class PreciseSyncPulseGenerator {
  static Isolate? _isolate;
  static ReceivePort? _receivePort;
  static StreamController<bool>? _stateController;
  static final List<LogEvent> _syncEvents = [];

  // Initialize the stream controller immediately so widgets can subscribe
  static StreamController<bool> get _ensureStateController {
    _stateController ??= StreamController<bool>.broadcast();
    return _stateController!;
  }

  static Stream<bool> get stateStream {
    return _ensureStateController.stream;
  }

  static Future<void> start({
    Duration interval = const Duration(milliseconds: 100),
    Duration pulseDuration = const Duration(milliseconds: 20),
  }) async {
    if (_isolate != null) await stop();

    _receivePort = ReceivePort();
    // Ensure we have a stream controller (don't replace existing one)
    _ensureStateController;

    final isolateData = SyncPulseIsolateData(
      sendPort: _receivePort!.sendPort,
      interval: interval,
      pulseDuration: pulseDuration,
    );

    _isolate = await Isolate.spawn(syncPulseIsolate, isolateData);

    _receivePort!.listen((message) {
      if (message is Map<String, dynamic>) {
        switch (message['type']) {
          case 'pulse_start':
          case 'pulse_end':
            _syncEvents.add(
              LogEvent(
                type: EventType.syncPulse,
                timestampMicros: message['timestamp'],
              ),
            );
            PerformanceLogger.logEvent(EventType.syncPulse);
            break;
          case 'state_update':
            _ensureStateController.sink.add(message['isHigh'] ?? false);
            break;
        }
      }
    });
  }

  static Future<void> stop() async {
    _isolate?.kill();
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    await _stateController?.close();
    _stateController = null;
  }

  static List<LogEvent> getSyncEvents() => List.unmodifiable(_syncEvents);
  static void clearSyncEvents() => _syncEvents.clear();

  /// Triggers a single sync pulse with visual feedback.
  ///
  /// Shows a brief flash of the sync pulse indicator without starting
  /// continuous pulse generation. Useful for manual sync point creation.
  static void triggerSinglePulse({
    Duration pulseDuration = const Duration(milliseconds: 100),
  }) {
    // Trigger visual feedback immediately
    _ensureStateController.sink.add(true);

    // Turn off the visual indicator after the pulse duration
    Future.delayed(pulseDuration, () {
      _ensureStateController.sink.add(false);
    });
  }
}
