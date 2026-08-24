import 'dart:io' show Platform;

import 'bela_protocol.dart';

/// Session-wide knobs for the Bela latency protocol.
///
/// Compile-time defaults come from `--dart-define`, so a build can be pinned
/// for a run without touching source:
///
/// ```sh
/// flutter run --release \
///   --dart-define=LSL_ENABLED=true \
///   --dart-define=LSL_SOURCE_ID=ipad-pro-11-a \
///   --dart-define=LSL_KNOWN_PEERS=192.168.1.20 \
///   --dart-define=FLASH_MS=100
/// ```
abstract final class TimingConfig {
  /// Whether the LSL outlet is created at startup.
  ///
  /// LSL is *optional*: with this false the app is a self-contained
  /// input/display latency logger, exactly as before, and never touches the
  /// network. It can also be toggled at runtime from the controls row.
  static const bool lslEnabledByDefault =
      bool.fromEnvironment('LSL_ENABLED', defaultValue: false);

  /// Stream name. Must contain [BelaProtocol.streamNamePrefix] or the Bela
  /// will not open an inlet for it.
  static const String streamName =
      String.fromEnvironment('LSL_STREAM_NAME', defaultValue: 'LSLTest-iPad');

  /// Stable, non-empty per-device id: the join key in the Bela's logs and what
  /// makes the inlet recoverable across a Wi-Fi dropout. Defaults to the
  /// device hostname, which is stable per device; override for a run where two
  /// devices might share one.
  static const String sourceIdOverride =
      String.fromEnvironment('LSL_SOURCE_ID', defaultValue: '');

  /// Comma-separated peer IPs written into the liblsl api config.
  ///
  /// Naming the Bela here makes resolution deterministic and skips multicast
  /// discovery, so there is less background traffic competing with the very
  /// packets whose latency is being measured. Strongly recommended for real
  /// runs; mirrors the `KnownPeers` guidance in the Bela's `lsl_api.cfg`.
  static const String knownPeersRaw =
      String.fromEnvironment('LSL_KNOWN_PEERS', defaultValue: '');

  static List<String> get knownPeers => knownPeersRaw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  /// How long the photodiode patch stays white. The falling edge gives a
  /// second, independent check on the same trial.
  static const int flashMillis = int.fromEnvironment('FLASH_MS', defaultValue: 100);

  /// Patch size in logical pixels. Panel scanout is row-by-row, so the patch
  /// sits at the top of the screen where the fixed positional offset is
  /// smallest; its geometry is recorded in the stream header.
  static const int patchSizePx = int.fromEnvironment('PATCH_PX', defaultValue: 200);

  static const double patchSize = patchSizePx + 0.0;

  /// Exact hardware model, recorded in the stream header. There is no
  /// dependency-free way to read this from Dart, so pin it per run:
  /// `--dart-define=DEVICE_MODEL='iPad Pro 11 M4'`.
  static const String deviceModel =
      String.fromEnvironment('DEVICE_MODEL', defaultValue: '');

  /// App version recorded in the stream header. Keep in step with `pubspec.yaml`.
  static const String appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.1.0');

  /// Minimum spacing between trials. The spec asks for > 1 s so that pairing
  /// an FSR edge to a trial is never ambiguous; touches inside the window are
  /// logged but do not open a trial, which makes them identifiable offline as
  /// exactly what they are. Set to zero to disable the lockout.
  static const int minTrialIntervalMillis =
      int.fromEnvironment('MIN_TRIAL_MS', defaultValue: 1000);

  /// Free-text note recorded in the stream header, e.g. the rig serial.
  static const String note = String.fromEnvironment('SESSION_NOTE', defaultValue: '');

  /// Resolved once per session.
  static String? _sourceId;

  /// The stable device id actually used for the outlet.
  static String get sourceId {
    if (_sourceId != null) return _sourceId!;
    if (sourceIdOverride.isNotEmpty) return _sourceId = sourceIdOverride;
    String host;
    try {
      host = Platform.localHostname;
    } catch (_) {
      host = 'unknown';
    }
    final slug = host
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return _sourceId = '${Platform.operatingSystem}-${slug.isEmpty ? 'device' : slug}';
  }
}
