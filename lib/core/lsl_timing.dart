import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:liblsl/lsl.dart';

import 'bela_protocol.dart';
import 'native_clock.dart';
import 'timing_config.dart';

/// The LSL side of the Bela latency rig — optional, and off unless asked for.
///
/// Nothing else in the app depends on this class existing or having started:
/// every entry point is a no-op when the outlet is not running, so the timing
/// app keeps working stand-alone with no network traffic at all.
///
/// Latency-relevant choices, all of them deliberate:
///
/// * **Direct mode** (`useIsolates: false`). The isolated path would hop the
///   sample through a port message before it reaches liblsl; here
///   [pushEvent] is a synchronous memmove into a cached native buffer plus one
///   FFI call, on the same thread that observed the event.
/// * **`chunkSize: 1`** — no coalescing, the sample goes out on its own.
/// * **`maxBuffer: 1`** — for an irregular-rate stream this is in hundreds of
///   samples, i.e. the smallest the API allows. There is nothing to gain from
///   a deep outbound queue when every sample is an event.
/// * **Not** `syncBlocking`: that would park the UI thread on the socket write
///   until the Bela's TCP window accepted it, which is exactly the wrong
///   trade for a frame we are trying to present on the next vsync.
/// * Samples are pushed with an **explicit timestamp** equal to ch1, so any
///   divergence between the two exposes a timestamping bug instead of hiding
///   it.
class LslTimingService {
  LSLOutlet? _outlet;
  LSLStreamInfoWithMetadata? _info;

  /// One buffer for the whole session: [pushEvent] must not allocate.
  final Float64List _sample = Float64List(BelaProtocol.channelCount);

  int _seq = 0;
  int _pushErrors = 0;
  Object? _lastError;

  /// True once an outlet exists and samples can be pushed.
  bool get isRunning => _outlet != null;

  /// Samples pushed so far this session (the value written to ch3).
  int get seq => _seq;

  /// Pushes that threw or returned an error code.
  int get pushErrors => _pushErrors;

  Object? get lastError => _lastError;

  String get streamName => _info?.streamName ?? TimingConfig.streamName;

  String get sourceId => TimingConfig.sourceId;

  /// Applies the liblsl API configuration.
  ///
  /// Must run before any other LSL call, so it is called unconditionally at
  /// startup — including when LSL is disabled, in case it is switched on
  /// later. IPv6 is off because the rig is a flat IPv4 network and resolve
  /// attempts on a dead family are wasted airtime; naming the Bela in
  /// `knownPeers` skips multicast discovery entirely.
  static void configure() {
    final peers = TimingConfig.knownPeers;
    LSL.setConfigContent(
      LSLApiConfig(
        ipv6: IPv6Mode.disable,
        knownPeers: peers,
        // Wireless tuning recommended by the LSL docs; the Bela logs the whole
        // time-correction series with its uncertainty, so tighter, more
        // frequent probes directly tighten the bound on T4.
        timeProbeMaxRTT: 0.100,
        timeProbeInterval: 0.010,
        timeProbeCount: 10,
        timeUpdateInterval: 0.25,
        multicastMinRTT: 0.100,
        multicastMaxRTT: 30.0,
      ),
    );
  }

  /// Creates the outlet and pushes `SESSION_START`.
  ///
  /// [extraMetadata] is written verbatim into the stream header, which the
  /// Bela dumps to `<session>_stream.xml`; anything put there lands in the
  /// permanent record of the run.
  Future<void> start({Map<String, String> extraMetadata = const {}}) async {
    if (_outlet != null) return;

    final info = await LSL.createStreamInfo(
      streamName: TimingConfig.streamName,
      streamType: LSLContentType.custom(BelaProtocol.streamType),
      channelCount: BelaProtocol.channelCount,
      sampleRate: LSL_IRREGULAR_RATE,
      channelFormat: LSLChannelFormat.double64,
      sourceId: TimingConfig.sourceId,
    );

    final desc = info.description.value;
    final channels = desc.addChildElement('channels');
    for (int i = 0; i < BelaProtocol.channelCount; i++) {
      final channel = channels.addChildElement('channel');
      channel.addChildValue('label', BelaProtocol.channelLabels[i]);
      channel.addChildValue('unit', i == 1 || i == 4 || i == 5 ? 'seconds' : 'count');
      channel.addChildValue('type', BelaProtocol.channelDescriptions[i]);
    }
    for (final entry in extraMetadata.entries) {
      if (entry.value.isEmpty) continue;
      desc.addChildValue(entry.key, entry.value);
    }

    final outlet = await LSL.createOutlet(
      streamInfo: info,
      chunkSize: 1,
      maxBuffer: 1,
      useIsolates: false,
    );

    _info = info;
    _outlet = outlet;
    _seq = 0;
    _pushErrors = 0;
    _lastError = null;

    pushEvent(BelaEvent.sessionStart, eventClock: AppClock.now(), trial: 0);
  }

  /// Pushes one sample. Synchronous, allocation-free, and never throws.
  ///
  /// Returns the `seq` written to ch3, or -1 if the outlet is not running.
  /// A failure here must never take down the trial: the Flutter-side CSV still
  /// has the event, and [pushErrors] surfaces the problem in the UI.
  int pushEvent(
    BelaEvent event, {
    required double eventClock,
    required int trial,
    double auxA = 0.0,
    double auxB = 0.0,
  }) {
    final outlet = _outlet;
    if (outlet == null) return -1;
    final seq = ++_seq;
    fillBelaSample(
      _sample,
      event: event,
      eventClock: eventClock,
      trial: trial,
      seq: seq,
      auxA: auxA,
      auxB: auxB,
    );
    try {
      // Explicit timestamp == ch1, by design (see the class comment).
      outlet.pushChunkTypedSync(_sample, timestamp: eventClock);
    } catch (e) {
      _pushErrors++;
      _lastError = e;
      if (kDebugMode) {
        debugPrint('LSL push failed: $e');
      }
    }
    return seq;
  }

  /// Whether the Bela (or any other consumer) currently has an inlet open.
  bool get hasConsumers {
    final outlet = _outlet;
    if (outlet == null) return false;
    try {
      return outlet.hasConsumersSync();
    } catch (_) {
      return false;
    }
  }

  /// Pushes `SESSION_END` and tears the outlet down.
  Future<void> stop({int trial = 0}) async {
    final outlet = _outlet;
    if (outlet == null) return;
    pushEvent(BelaEvent.sessionEnd, eventClock: AppClock.now(), trial: trial);
    // Give liblsl a moment to hand the last sample to the socket before the
    // outlet is destroyed underneath it.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _outlet = null;
    outlet.destroy();
    _info?.destroy();
    _info = null;
  }
}
