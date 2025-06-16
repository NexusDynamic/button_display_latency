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

- `GestureDetectorTapButton` - Uses `GestureDetector.onTap`
- `GestureDetectorTapDownButton` - Uses `GestureDetector.onTapDown`
- `GestureDetectorPanDownButton` - Uses `GestureDetector.onPanDown`
- `RawGestureDetectorTapButton` - Uses `RawGestureDetector.onTap`
- `ListenerPointerDownButton` - Uses `Listener.onPointerDown`


### Measurement Capabilities
- **Touch Detection**: Timestamp when input is first detected
- **Frame Timing**: Start/end timestamps for frame rendering
- **Display Feedback**: When visual changes begin/end
- **Sync Pulses**: Reference signals for external device alignment

### Visual Indicators
- **White Square (Right)**: Appears when button is pressed
- **White Square (Left)**: Flashes with sync pulses


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
- Connect both to your measurement device (oscilloscope, data logger, etc.) -> Bela / Beaglebone Black code to come soon


### Controls
- **Clear Logs**: Reset all timing data
- **Sync Pulse**: Generate single sync event (and display)
- **Start Sync**: Begin continuous sync pulse generation (100ms intervals)
- **Stop Sync**: End sync pulse generation
- **Export Logs**: Print CSV data to console

## 📊 Data Analysis

### CSV Output Format
```csv
EventType,TimestampMicros,ButtonType,FrameNumber
touchDetected,1234567,GestureDetectorTapButton,
displayStart,1234580,,15
frameStart,1234590,,15
frameEnd,1234610,,15
displayEnd,1284567,,
syncPulse,1300000,,
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Considerations

- **Android Timing Variance**: Sync pulse timing may vary on some Android devices due to system scheduling
- **Refresh Rate Limitations**: High refresh rate requests may not be honored on all devices
- **Precision Limits**: Some older devices may have limited timing precision capabilities
- **Background Processing**: System background tasks may affect timing measurements
