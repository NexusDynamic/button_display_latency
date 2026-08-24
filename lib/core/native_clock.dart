import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' show calloc;
import 'package:liblsl/lsl.dart' show LSL;

/// The application's single time base.
///
/// Everything the app timestamps — log rows, LSL samples, frame events — is
/// expressed on `lsl_local_clock()`. That is deliberate:
///
/// * it is the clock the Bela rig correlates against, so no conversion is
///   needed on the hot path (the conversion would itself add jitter);
/// * `lslLocalClockFast` is bound with `isLeaf: true`, so a call is a plain
///   monotonic clock read with no VM safepoint transition (tens of ns);
/// * it is monotonic, so it is immune to wall-clock adjustments mid session.
///
/// Timestamps that come from *outside* Dart (the OS touch clock, the engine's
/// frame clock) live on other epochs and are mapped onto this one with the
/// offsets measured by [ClockOffsets].
abstract final class AppClock {
  /// Seconds on the LSL local clock. Safe to call from the input hot path.
  @pragma('vm:prefer-inline')
  static double now() => LSL.localClock();
}

/// POSIX `struct timespec`. `tv_sec`/`tv_nsec` are both C `long`, which is
/// 32-bit on 32-bit ABIs — [Long] tracks that automatically.
final class _Timespec extends Struct {
  @Long()
  external int tvSec;

  @Long()
  external int tvNsec;
}

typedef _ClockGetTimeNative = Int32 Function(Int32, Pointer<_Timespec>);
typedef _ClockGetTimeDart = int Function(int, Pointer<_Timespec>);

/// Which POSIX clock a reading came from.
enum PosixClock {
  /// `CLOCK_REALTIME` — wall clock, Unix epoch. The engine's
  /// `FrameTiming.rasterFinishWallTime` lives here.
  realtime,

  /// `CLOCK_MONOTONIC`. On Android this backs `SystemClock.uptimeMillis()`,
  /// which is what `MotionEvent.getEventTime()` (and therefore
  /// `PointerEvent.timeStamp`) reports.
  monotonic,

  /// `CLOCK_MONOTONIC_RAW`. On Apple platforms this is what libc++'s
  /// `std::chrono::steady_clock` reads, which is the engine's `fml::TimePoint`
  /// epoch and (almost certainly) liblsl's own `local_clock` epoch.
  monotonicRaw,

  /// `CLOCK_UPTIME_RAW` on Darwin (`CLOCK_BOOTTIME` on Linux). On Apple
  /// platforms this is `mach_absolute_time()` / `CACurrentMediaTime()`, which
  /// is where `UITouch.timestamp` — and therefore iOS
  /// `PointerEvent.timeStamp` — comes from.
  uptimeRaw;

  /// The numeric `clockid_t`, which differs between Darwin and Linux.
  int get id {
    final darwin = Platform.isIOS || Platform.isMacOS;
    switch (this) {
      case PosixClock.realtime:
        return 0;
      case PosixClock.monotonic:
        return darwin ? 6 : 1;
      case PosixClock.monotonicRaw:
        return 4;
      case PosixClock.uptimeRaw:
        return darwin ? 8 : 7;
    }
  }
}

/// A measured constant offset between a foreign clock and [AppClock].
class ClockOffset {
  /// Seconds to *add* to a reading on the foreign clock to land on the LSL
  /// clock.
  final double offset;

  /// Half the width of the tightest read sandwich, in seconds. The true offset
  /// is within +/- this of [offset] (plus whatever drift the two clocks have
  /// against each other, which is nil when both are the same hardware counter).
  final double uncertainty;

  /// Whether the measurement succeeded at all.
  final bool valid;

  const ClockOffset(this.offset, this.uncertainty) : valid = true;

  const ClockOffset.unavailable() : offset = 0.0, uncertainty = double.nan, valid = false;

  /// Maps [seconds] on the foreign clock onto the LSL clock.
  @pragma('vm:prefer-inline')
  double toLsl(double seconds) => seconds + offset;

  @override
  String toString() => valid
      ? '${offset.toStringAsFixed(9)}s +/-${(uncertainty * 1e6).toStringAsFixed(1)}us'
      : 'unavailable';
}

/// Measures, once per session, how each OS clock relates to [AppClock].
///
/// Nothing here is guessed from platform lore alone: every offset is measured
/// by sandwiching an `lsl_local_clock()` read between two reads of the POSIX
/// clock and keeping the tightest of many attempts. Which POSIX clock backs
/// which foreign timestamp *is* platform lore (see [PosixClock]), so all four
/// offsets are recorded — if the mapping assumption is ever wrong, the raw
/// numbers needed to redo it offline are in the session record.
class ClockOffsets {
  final Map<PosixClock, ClockOffset> offsets;

  /// Whether `clock_gettime` was resolvable (false on Windows).
  final bool supported;

  const ClockOffsets._(this.offsets, this.supported);

  static ClockOffsets? _instance;

  /// The offsets measured for this session. [measure] must have run first.
  static ClockOffsets get instance =>
      _instance ?? (throw StateError('ClockOffsets.measure() has not been called'));

  static bool get measured => _instance != null;

  /// `PointerEvent.timeStamp` / `PointerData.timeStamp` -> LSL clock.
  ClockOffset get pointer => offsets[_pointerClock] ?? const ClockOffset.unavailable();

  /// `FrameTiming.timestampInMicroseconds(...)` -> LSL clock, for every phase
  /// except `rasterFinishWallTime`.
  ClockOffset get engine => offsets[_engineClock] ?? const ClockOffset.unavailable();

  /// `FrameTiming.rasterFinishWallTime` -> LSL clock.
  ClockOffset get wall => offsets[PosixClock.realtime] ?? const ClockOffset.unavailable();

  /// The clock backing the OS touch timestamp on this platform.
  static PosixClock get _pointerClock =>
      (Platform.isIOS || Platform.isMacOS) ? PosixClock.uptimeRaw : PosixClock.monotonic;

  /// The clock backing `fml::TimePoint::Now()` (`std::chrono::steady_clock`).
  static PosixClock get _engineClock =>
      (Platform.isIOS || Platform.isMacOS) ? PosixClock.monotonicRaw : PosixClock.monotonic;

  static String get pointerClockName => _pointerClock.name;
  static String get engineClockName => _engineClock.name;

  /// Measures every clock offset and caches the result for the session.
  ///
  /// Costs a few hundred microseconds. Call once, before the first trial, and
  /// after the display has settled — never on the input path.
  static ClockOffsets measure({int trials = 101}) {
    final Pointer<_Timespec> ts = calloc<_Timespec>();
    _ClockGetTimeDart? clockGetTime;
    try {
      clockGetTime = DynamicLibrary.process()
          .lookupFunction<_ClockGetTimeNative, _ClockGetTimeDart>(
            'clock_gettime',
            isLeaf: true,
          );
    } catch (_) {
      calloc.free(ts);
      return _instance = const ClockOffsets._(<PosixClock, ClockOffset>{}, false);
    }

    double read(int clockId) {
      if (clockGetTime!(clockId, ts) != 0) return double.nan;
      return ts.ref.tvSec + ts.ref.tvNsec * 1e-9;
    }

    final results = <PosixClock, ClockOffset>{};
    try {
      for (final clock in PosixClock.values) {
        final id = clock.id;
        double bestHalfWidth = double.infinity;
        double bestOffset = 0.0;
        for (int i = 0; i < trials; i++) {
          final before = read(id);
          final lsl = AppClock.now();
          final after = read(id);
          if (before.isNaN || after.isNaN) {
            bestHalfWidth = double.infinity;
            break;
          }
          final halfWidth = (after - before) * 0.5;
          if (halfWidth < bestHalfWidth) {
            bestHalfWidth = halfWidth;
            bestOffset = lsl - (before + after) * 0.5;
          }
        }
        if (bestHalfWidth.isFinite) {
          results[clock] = ClockOffset(bestOffset, bestHalfWidth);
        }
      }
    } finally {
      calloc.free(ts);
    }

    return _instance = ClockOffsets._(results, results.isNotEmpty);
  }

  /// How far a foreign timestamp lands from [observedLsl] under each measured
  /// clock, in seconds.
  ///
  /// A diagnostic, not a lookup: the mapping [pointer] uses is fixed per
  /// platform, and this exists so that a wrong choice is obvious rather than
  /// silent. The correct clock produces a small positive number — the time the
  /// OS took to hand the event to Dart. A wrong one is out by the machine's
  /// uptime or by the whole Unix epoch, which no amount of jitter can imitate.
  Map<PosixClock, double> pointerEpochCandidates(
    double foreignSeconds,
    double observedLsl,
  ) {
    return <PosixClock, double>{
      for (final entry in offsets.entries)
        entry.key: observedLsl - entry.value.toLsl(foreignSeconds),
    };
  }

  /// Flat `key=value` pairs for the session record.
  Map<String, String> describe() {
    final out = <String, String>{
      'clock_base': 'lsl_local_clock',
      'clock_supported': '$supported',
      'clock_pointer_source': pointerClockName,
      'clock_engine_source': engineClockName,
    };
    for (final entry in offsets.entries) {
      out['clock_offset_${entry.key.name}_s'] = entry.value.offset.toStringAsFixed(9);
      out['clock_uncertainty_${entry.key.name}_s'] =
          entry.value.uncertainty.toStringAsFixed(9);
    }
    return out;
  }

  @override
  String toString() => describe().entries.map((e) => '${e.key}=${e.value}').join(', ');
}
