# Button Display Latency Test App

A Flutter application designed to measure and compare input detection latency and screen render timing across different button implementation methods.

## 🎯 Purpose

This app helps researchers and developers measure the complete input→display pipeline latency by:

- **Comparing Button Implementations**: Test different Flutter input detection methods
- **High-Precision Timing**: Microsecond-accurate measurements using `Stopwatch`
- **Frame-Accurate Rendering**: Track exact frame timing using Flutter's `scheduleFrameCallback`
- **External Device Sync**: Precise sync pulses for aligning with external measurement tools
- **Visual Feedback**: Real-time indicators for button presses and sync signals

## 📱 Features

### Button Types Tested

Because different button implementations can have varying latency characteristics, this app includes multiple button types for comparison:

Ordered fastest first, which is also the order the dropdown lists them:

- `RawPointerDownButton` - taps `PlatformDispatcher.onPointerDataPacket`, the
  first Dart code the engine runs for a touch. No hit-test walk, no gesture
  arena; the button's rectangle is matched in physical pixels by the app
  itself. The default.
- `ListenerPointerDownButton` - Uses `Listener.onPointerDown`. The fastest path
  that stays inside the framework, and still carries the OS touch timestamp.
- `GestureDetectorPanDownButton` - Uses `GestureDetector.onPanDown`
- `GestureDetectorTapDownButton` - Uses `GestureDetector.onTapDown`
- `RawGestureDetectorTapButton` - Uses `RawGestureDetector.onTap`
- `GestureDetectorTapButton` - Uses `GestureDetector.onTap`; fires only once the
  arena resolves, i.e. after the pointer is lifted

Only the first two can report `PointerEvent.timeStamp`, the OS's own hardware
timestamp for the touch. That split — "the OS reported it" versus "Dart saw
it" — is exactly what the slower paths add, so the implementations that cannot
supply it are the ones where it would have mattered most.


### Measurement Capabilities
- **Touch Detection**: Timestamp when input is first detected
- **Frame Timing**: Start/end timestamps for frame rendering
- **Display Feedback**: When visual changes begin/end
- **Sync Pulses**: Reference signals for external device alignment

### Visual Indicators
- **White Square (Right)**: Appears when button is pressed
- **White Square (Left)**: Flashes with sync pulses
- **Photodiode patch (top-left corner)**: shown in Bela mode instead of the two
  squares above. Repaints without a rebuild or a layout pass.


## 🚀 Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- iOS/Android device or simulator
- **Optional**: Force Sensitive Resistor (FSR) and photodiodes for external measurements

### Installation
1. Clone the repository
```bash
git clone https://github.com/NexusDynamic/button_display_latency
cd button_display_latency
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the app
```bash
flutter run --release
```

## 🔬 Usage

### Basic Testing
1. **Select Button Type**: Use dropdown to choose implementation
2. **Clear Logs**: Start fresh measurement session
3. **Test**: Tap the main button repeatedly
4. **Export**: Get CSV data for analysis (via share dialogue)

### Advanced Sync Testing with External Devices
For the best results, you should have a Force Sensitive Resistor (FSR) and photodiode connected to your measurement device:

- Position FSR over the main test button
- Position photodiode over the left-side sync square
- Position a second photodiode over the right-side button press indicator
- Connect both to your measurement device (oscilloscope, data logger, etc.). For the Bela / BeagleBone Black rig, see [Bela latency rig](#-bela-latency-rig) below.


### Controls
- **Bela mode**: swap the two indicator squares for the photodiode patch, pin
  the display at its maximum refresh rate, and start the outlet if LSL is on
- **LSL**: open or close the outlet, independently of Bela mode, so the display
  side can be exercised with no network at all
- **Clear Logs**: Reset all timing data and the trial counter
- **Sync Pulse**: Generate single sync event (and display)
- **Start Sync**: Begin continuous sync pulse generation (100ms intervals)
- **Stop Sync**: End sync pulse generation
- **Export Logs**: Share CSV data (also printed to the console in debug builds)

The status line under the toggles shows the trial count, rejected touches, the
display's reported refresh rate, the live `os→dart` dispatch gap, whether the
Bela has an inlet open, and the stream name / source id.

## 🔌 Bela latency rig

The app is the iPad end of the Bela timing rig in
[`bela-lsl-timing`](../bela-lsl-timing) (`render.cpp`). The Bela measures the
motor→photon chain from an FSR under the button and a photodiode over the
patch; the app contributes the two timestamps the sensors cannot see — when the
OS reported the touch, and when Dart handled it — over LSL.

**LSL is optional.** With it off the app never opens a socket and behaves as a
stand-alone latency logger, exactly as it did before. Both the outlet and the
Bela display protocol are runtime toggles in the controls row, and their
startup defaults come from `--dart-define`.

### Running a session

```sh
flutter run --release \
  --dart-define=LSL_ENABLED=true \
  --dart-define=DEVICE_MODEL='iPad Pro 11 M4' \
  --dart-define=LSL_SOURCE_ID=ipad-pro-11-a \
  --dart-define=LSL_KNOWN_PEERS=192.168.1.20
```

| define | default | meaning |
|---|---|---|
| `LSL_ENABLED` | `false` | open the outlet and enter Bela mode at startup |
| `LSL_STREAM_NAME` | `LSLTest-iPad` | must contain `LSLTest` — the Bela's filter |
| `LSL_SOURCE_ID` | device hostname | stable per-device id; the join key in the logs |
| `LSL_KNOWN_PEERS` | *(none)* | Bela IP(s); skips multicast discovery entirely |
| `FLASH_MS` | `100` | how long the patch stays white |
| `PATCH_PX` | `200` | patch edge length in logical pixels |
| `MIN_TRIAL_MS` | `1000` | inter-trial lockout (0 disables) |
| `DEVICE_MODEL` | *(none)* | exact model, recorded in the stream header |
| `APP_VERSION` | `1.1.0` | recorded in the stream header |
| `SESSION_NOTE` | *(none)* | free text, recorded in the stream header |

On the Bela side, list the iPad in `lsl_api.cfg` under `KnownPeers`. That makes
resolution deterministic, removes multicast traffic from the network whose
latency is being measured, and — on iOS specifically — means the app never
needs Apple's multicast entitlement, because it only has to answer unicast
resolve queries. `ios/Runner/Runner.entitlements` is there for the case where
you cannot name peers and must fall back to multicast; it does nothing until
you add the Multicast Networking capability to the Runner target in Xcode.

### Stream layout

Implements `bela-lsl-timing/docs/flutter_outlet_spec.md`: a 6-channel
`cf_double64` stream at `IRREGULAR_RATE`, type `Timing`, pushed one sample at a
time with an explicit timestamp equal to `event_clock`.

| ch | name | contents |
|---|---|---|
| 0 | `event_code` | 1 `SESSION_START`, 2 `TOUCH_REGISTERED`, 3 `FLASH_REQUESTED`, 4 `FLASH_PRESENTED`, 5 `SESSION_END` |
| 1 | `event_clock` | `lsl_local_clock()` when the event was observed |
| 2 | `trial` | trial counter, shared by every event of a trial |
| 3 | `seq` | session-wide sample counter, +1 per push |
| 4 | `aux_a` | touch: OS touch timestamp. flash: `FrameTiming.vsyncStart` |
| 5 | `aux_b` | flash: `FrameTiming.rasterFinishWallTime`. Otherwise 0 |

**One deviation from the spec, deliberately:** `aux_b` is converted into the LSL
epoch rather than left on the engine's wall clock, so that every timestamp the
app emits is on one clock and no consumer has to know which column needs which
conversion. The stream header records `aux_epoch=lsl_local_clock` along with
every measured offset, so the raw value can be recovered exactly.

### Clock epochs

Three foreign clocks feed into the record, and none of them is assumed:

| source | backing clock | used for |
|---|---|---|
| `PointerEvent.timeStamp` | `CLOCK_UPTIME_RAW` (iOS/macOS), `CLOCK_MONOTONIC` (Android) | ch4 on `TOUCH_REGISTERED` |
| `FrameTiming` phases | `CLOCK_MONOTONIC_RAW` (Apple), `CLOCK_MONOTONIC` (Linux/Android) | ch1/ch4 on `FLASH_PRESENTED` |
| `rasterFinishWallTime` | `CLOCK_REALTIME` | ch5 |

At startup `lib/core/native_clock.dart` measures the offset from each of those
to `lsl_local_clock()` by sandwiching a clock read between two `clock_gettime`
calls and keeping the tightest of 101 attempts. This is not academic: on a Mac
that has been asleep, `CLOCK_UPTIME_RAW` and `CLOCK_MONOTONIC_RAW` differ by
*days*, so guessing wrong is not a subtle error. All four offsets and their
uncertainties go into the stream header and the CSV.

The mapping is also checked live. The status line shows `os→dart`, the gap
between the OS touch timestamp and the instant Dart handled it; a plausible few
milliseconds there is proof the pointer clock is the right one. The exported
CSV header additionally carries what that gap would have been under *every*
measured clock, for the first touch of the session.

### What makes the numbers meaningful

- **The display is pinned.** A ProMotion iPad idles at a low refresh rate and
  ramps up on touch, which injects variable latency into every trial. The
  session runs a continuous frame loop so the panel is already at its maximum
  rate before the touch arrives. `flutter_refresh_rate_control` raises the
  ceiling; the frame loop is what actually holds it there.
- **The patch repaints without rebuilding.** `FlashController` is the
  `CustomPainter`'s `repaint` listenable, so a flash is a `markNeedsPaint` on
  one `RepaintBoundary` — no `setState`, no element rebuild, no layout. A touch
  is dispatched at the top of a frame, so the flash lands in *that* frame.
- **Nothing dirties a widget on the input path.** The status panel polls on a
  timer rather than listening to the session, because a listener would add a
  rebuild to the frame the flash has to make.
- **The patch is at the top-left corner.** Panel scanout is row by row, so
  vertical position is a fixed offset of up to one refresh period. Its position
  and size are recorded either way.
- **Trials are spaced.** Touches inside `MIN_TRIAL_MS` of the last are logged
  with `trial = -1` and neither flashed nor pushed. An FSR edge with no matching
  trial is then unambiguously a false trigger rather than a judgement call.
- **Order of operations on a touch** (`TimingSession.registerTouch`): mark the
  patch dirty, then push LSL, then log. Only the first can miss the frame.


## 📊 Data Analysis

### CSV Output Format

`#` comment lines carry the session metadata, including every measured clock
offset — without those the `AuxA`/`AuxB` columns cannot be interpreted.

```csv
# clock_base=lsl_local_clock
# clock_pointer_source=uptimeRaw
# clock_offset_uptimeRaw_s=837536.453935021
EventType,TimestampMicros,ButtonType,FrameNumber,LslClock,Trial,Seq,AuxA,AuxB
touchDetected,1234567,RawPointerDownButton,,1131082.224904000,1,2,1131082.221430000,
flashRequested,1234580,RawPointerDownButton,,1131082.224951000,1,3,,
flashPresented,1240000,RawPointerDownButton,123,1131082.234415000,1,4,1131082.223822000,1131082.234398000
syncPulse,1300000,RawPointerDownButton,,1131082.300000000,,,,
```

`LslClock` is on the same clock as the Bela's own logs, so a row here joins
directly against `<session>_lsl.csv` with no sync pulse in between.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Considerations

- **Android Timing Variance**: Sync pulse timing may vary on some Android devices due to system scheduling
- **Refresh Rate Limitations**: High refresh rate requests may not be honored on all devices; the status line reports what the display actually says it is doing
- **iOS local network**: the first LSL session prompts for local network access. Denying it leaves the outlet running but undiscoverable
- **Precision Limits**: Some older devices may have limited timing precision capabilities
- **Background Processing**: System background tasks may affect timing measurements
