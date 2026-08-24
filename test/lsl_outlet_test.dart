@Tags(['lsl'])
library;

import 'package:button_display_latency/core/bela_protocol.dart';
import 'package:button_display_latency/core/lsl_timing.dart';
import 'package:button_display_latency/core/native_clock.dart';
import 'package:button_display_latency/core/timing_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liblsl/lsl.dart';

/// End-to-end check of the outlet against the Bela's `flutter_outlet_spec.md`,
/// using a local inlet in place of the rig. Needs a working loopback/LAN LSL
/// path, so it is tagged and can be skipped where that is not available.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the outlet matches the Bela outlet spec', () async {
    LslTimingService.configure();
    ClockOffsets.measure(trials: 11);

    final service = LslTimingService();
    await service.start(extraMetadata: {'device_model': 'test-harness'});
    addTearDown(() => service.stop());

    expect(service.isRunning, isTrue);

    final streams = await LSL.resolveStreamsByProperty(
      property: LSLStreamProperty.sourceId,
      value: TimingConfig.sourceId,
      waitTime: 10.0,
      minStreamCount: 1,
    );
    expect(streams, isNotEmpty, reason: 'outlet was not discoverable');

    final info = streams.first;
    expect(info.streamName, contains(BelaProtocol.streamNamePrefix));
    expect(info.streamType.value, BelaProtocol.streamType);
    expect(info.channelCount, BelaProtocol.channelCount);
    expect(info.channelFormat, LSLChannelFormat.double64);
    expect(info.sampleRate, LSL_IRREGULAR_RATE);
    expect(info.sourceId, isNotEmpty);

    final inlet = await LSL.createInlet<double>(
      streamInfo: info,
      maxBuffer: 1,
      chunkSize: 1,
      recover: true,
    );
    addTearDown(() {
      inlet.destroy();
      streams.destroy();
    });

    // Drain SESSION_START, which was pushed before the inlet existed.
    await inlet.pullSample(timeout: 0.5);

    final touchClock = AppClock.now();
    final seq = service.pushEvent(
      BelaEvent.touchRegistered,
      eventClock: touchClock,
      trial: 4,
      auxA: touchClock - 0.004,
    );
    expect(seq, greaterThan(0));

    LSLSample<double>? received;
    for (int i = 0; i < 40 && received == null; i++) {
      final sample = await inlet.pullSample(timeout: 0.25);
      if (sample.isNotEmpty && sample[0] == BelaEvent.touchRegistered.code) {
        received = sample;
      }
    }

    expect(received, isNotNull, reason: 'no TOUCH_REGISTERED arrived');
    expect(received![0], BelaEvent.touchRegistered.code.toDouble());
    expect(received[1], closeTo(touchClock, 1e-9));
    expect(received[2], 4.0);
    expect(received[3], seq.toDouble());
    expect(received[4], closeTo(touchClock - 0.004, 1e-9));
    expect(received[5], 0.0);

    // Rule 1 of the spec: the sample is pushed with an explicit timestamp, and
    // ch1 deliberately duplicates it. Any divergence is a timestamping bug.
    expect(received.timestamp, closeTo(received[1], 1e-9));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
