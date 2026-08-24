import 'dart:typed_data';

import 'package:button_display_latency/core/bela_protocol.dart';
import 'package:button_display_latency/core/logging.dart';
import 'package:button_display_latency/core/native_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bela sample layout', () {
    test('matches the outlet spec channel order', () {
      final buffer = Float64List(BelaProtocol.channelCount);
      fillBelaSample(
        buffer,
        event: BelaEvent.touchRegistered,
        eventClock: 1234.5,
        trial: 7,
        seq: 42,
        auxA: 1234.25,
      );

      expect(BelaProtocol.channelCount, 6);
      expect(buffer[0], 2.0); // TOUCH_REGISTERED
      expect(buffer[1], 1234.5); // event_clock
      expect(buffer[2], 7.0); // trial
      expect(buffer[3], 42.0); // seq
      expect(buffer[4], 1234.25); // aux_a
      expect(buffer[5], 0.0); // aux_b, never NaN
    });

    test('stream name carries the prefix the Bela filters on', () {
      expect('LSLTest-iPad', contains(BelaProtocol.streamNamePrefix));
    });

    test('event codes are the ones render.cpp logs', () {
      expect(BelaEvent.sessionStart.code, 1);
      expect(BelaEvent.touchRegistered.code, 2);
      expect(BelaEvent.flashRequested.code, 3);
      expect(BelaEvent.flashPresented.code, 4);
      expect(BelaEvent.sessionEnd.code, 5);
    });
  });

  group('clock offsets', () {
    test('measure every POSIX clock against the LSL clock', () {
      final offsets = ClockOffsets.measure(trials: 21);
      expect(offsets.supported, isTrue);
      for (final clock in PosixClock.values) {
        final offset = offsets.offsets[clock];
        expect(offset, isNotNull, reason: '${clock.name} was not measured');
        // A sandwich this wide would mean the process was descheduled between
        // the two reads on every one of the attempts.
        expect(offset!.uncertainty, lessThan(1e-3));
      }
      // The pointer and engine mappings must resolve to something measured.
      expect(offsets.pointer.valid, isTrue);
      expect(offsets.engine.valid, isTrue);
      expect(offsets.wall.valid, isTrue);
      // The wall clock is a different epoch entirely, so its offset is huge;
      // the monotonic ones share a hardware counter and should be close.
      expect(offsets.wall.offset.abs(), greaterThan(1e6));
    });

    test('the app clock advances monotonically', () {
      final first = AppClock.now();
      final second = AppClock.now();
      expect(second, greaterThanOrEqualTo(first));
      expect(first, greaterThan(0));
    });
  });

  group('CSV export', () {
    test('carries the LSL clock and the session metadata', () {
      PerformanceLogger.clear();
      PerformanceLogger.sessionMetadata['aux_epoch'] = 'lsl_local_clock';
      PerformanceLogger.logEvent(
        EventType.touchDetected,
        buttonType: 'RawPointerDownButton',
        lslClock: 100.5,
        trial: 3,
        seq: 9,
        auxA: 100.25,
      );

      final csv = PerformanceLogger.exportCsv();
      expect(csv, contains('# aux_epoch=lsl_local_clock'));
      expect(
        csv,
        contains(
          'EventType,TimestampMicros,ButtonType,FrameNumber,LslClock,Trial,Seq,AuxA,AuxB',
        ),
      );
      expect(csv, contains('RawPointerDownButton'));
      expect(csv, contains('100.500000000'));
      expect(csv, contains(',3,9,100.250000000,'));
      PerformanceLogger.clear();
    });
  });
}
