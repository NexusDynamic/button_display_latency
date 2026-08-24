import 'dart:typed_data';

/// The wire contract with the Bela timing rig (`bela-lsl-timing/render.cpp`).
///
/// Mirrors `docs/flutter_outlet_spec.md` in that repository. The Bela reads
/// `channel_count` from the stream header and logs every channel generically,
/// so a change here will not break acquisition — but it *will* break the
/// offline analysis, which assumes this layout. Keep the two in step.
abstract final class BelaProtocol {
  /// Must contain `LSLTest`: it is the Bela's `kStreamPrefixFilter`.
  static const String streamNamePrefix = 'LSLTest';

  static const String streamType = 'Timing';

  /// ch0..ch5, `cf_double64`. A double holds integers exactly to 2^53, so the
  /// codes and counters in ch0/ch2/ch3 are safe.
  static const int channelCount = 6;

  static const List<String> channelLabels = <String>[
    'event_code',
    'event_clock',
    'trial',
    'seq',
    'aux_a',
    'aux_b',
  ];

  static const List<String> channelDescriptions = <String>[
    '1=SESSION_START 2=TOUCH_REGISTERED 3=FLASH_REQUESTED 4=FLASH_PRESENTED 5=SESSION_END',
    'lsl_local_clock() at the instant the event was observed',
    'trial counter, shared by every event of one trial',
    'session-wide sample counter, +1 per pushed sample',
    'TOUCH_REGISTERED: OS touch timestamp (LSL epoch). FLASH_PRESENTED: FrameTiming.vsyncStart (LSL epoch)',
    'FLASH_PRESENTED: FrameTiming.rasterFinishWallTime (LSL epoch). Otherwise 0',
  ];
}

/// ch0 event codes.
enum BelaEvent {
  sessionStart(1),
  touchRegistered(2),
  flashRequested(3),
  flashPresented(4),
  sessionEnd(5);

  const BelaEvent(this.code);

  /// The integer written to ch0.
  final int code;
}

/// Fills [buffer] (length [BelaProtocol.channelCount]) with one sample.
///
/// Kept allocation-free so it can run on the input hot path: the caller owns a
/// single [Float64List] for the whole session.
@pragma('vm:prefer-inline')
void fillBelaSample(
  Float64List buffer, {
  required BelaEvent event,
  required double eventClock,
  required int trial,
  required int seq,
  double auxA = 0.0,
  double auxB = 0.0,
}) {
  buffer[0] = event.code.toDouble();
  buffer[1] = eventClock;
  buffer[2] = trial.toDouble();
  buffer[3] = seq.toDouble();
  buffer[4] = auxA;
  buffer[5] = auxB;
}
