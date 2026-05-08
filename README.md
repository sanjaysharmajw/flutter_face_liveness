# flutter_face_liveness

Production-ready AI-powered Flutter SDK for **real-time face detection, liveness verification, and anti-spoof protection** — powered by Google ML Kit and optional TensorFlow Lite. All processing runs **on-device** with zero network calls.

---

## Features

- **7 liveness challenge actions** — blink, turn left/right, look up/down, smile, open mouth
- **Isolate-based ML preprocessing** — YUV conversion + quality analysis offloaded from the main thread
- **Frame quality validation** — brightness, overexposure, and blur detection before every check
- **7-signal anti-spoof engine** — eye variance, geometry, pose, natural eyes, tracking, micro-motion, and quality
- **Replay-attack prevention** — FNV-1a frame hashing detects duplicate / looped frames
- **Session management** — unique session IDs with elapsed time and frame counting for audit trails
- **Randomised action order** — Fisher-Yates shuffle prevents predictable replay attacks
- **TFLite plug-in point** — swap in your own deepfake-detection model without changing package APIs
- **Dark / light theme** — adaptive UI controlled via `LivenessConfig`
- **Step indicator** — animated progress dots show current and completed challenges
- **Instant detection** — fires while the user is still in the peak pose (no return-to-neutral wait)

---

## Getting started

### 1. Add the dependency

```yaml
dependencies:
  flutter_face_liveness: ^2.0.0
```

### 2. Platform permissions

**Android** — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

**iOS** — `ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is required for face liveness verification.</string>
```

### 3. Minimum SDK versions

| Platform | Minimum |
|----------|---------|
| Android  | API 21 (Android 5.0) |
| iOS      | iOS 12.0 |

---

## Quick start

```dart
import 'package:flutter_face_liveness/flutter_face_liveness.dart';

FlutterFaceLiveness(
  actions: [
    LivenessAction.blink,
    LivenessAction.turnLeft,
    LivenessAction.turnRight,
  ],
  config: LivenessConfig(
    randomizeActions: true,
    enableAntiSpoof: true,
  ),
  onSuccess: (result) {
    print('Verified! Session: \${result.sessionId}');
    print('Confidence: \${(result.confidenceScore * 100).toStringAsFixed(1)}%');
  },
  onFailed: (reason) => print('Failed: \$reason'),
)
```

---

## LivenessConfig options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `randomizeActions` | `bool` | `true` | Shuffle action order each session |
| `enableAntiSpoof` | `bool` | `true` | Run 7-signal composite anti-spoof check |
| `antiSpoofThreshold` | `double` | `0.45` | Minimum score to pass anti-spoof (0–1) |
| `enableBrightnessCheck` | `bool` | `true` | Reject frames that are too dark or overexposed |
| `brightnessMin` | `double` | `0.20` | Minimum Y-plane luminance ratio |
| `brightnessMax` | `double` | `0.90` | Maximum Y-plane luminance ratio |
| `enableBlurDetection` | `bool` | `true` | Reject blurry frames |
| `blurThreshold` | `double` | `80.0` | Y-plane variance; below this = blurry |
| `enableDuplicateFrameDetection` | `bool` | `true` | Hash-based replay-frame detection |
| `duplicateFrameWindowSize` | `int` | `8` | Sliding window for duplicate streak detection |
| `sessionTimeoutMs` | `int` | `60000` | Auto-fail after this many ms (60 s) |
| `cameraResolution` | `ResolutionPreset` | `high` | Camera resolution preset |
| `targetFps` | `int` | `20` | Frame processing rate |
| `faceTooFarRatio` | `double` | `0.015` | Face area ratio below which = "too far" |
| `faceTooCloseRatio` | `double` | `0.70` | Face area ratio above which = "too close" |
| `enableTFLite` | `bool` | `false` | Enable optional TFLite model inference |
| `tfliteModelPath` | `String?` | `null` | Asset path to `.tflite` model file |
| `tfliteInputSize` | `int` | `128` | Model input size (square, px) |
| `themeMode` | `ThemeMode` | `dark` | Widget theme (`dark` / `light`) |
| `showDebugOverlay` | `bool` | `false` | Show Euler angles + quality metrics on screen |

---

## Liveness actions

| Action | Enum | Trigger |
|--------|------|---------|
| Blink | `LivenessAction.blink` | Both eye open probability drops below threshold |
| Turn Left | `LivenessAction.turnLeft` | Yaw angle exceeds +15° and held for 80 ms |
| Turn Right | `LivenessAction.turnRight` | Yaw angle drops below −15° and held for 80 ms |
| Look Up | `LivenessAction.lookUp` | Pitch angle exceeds +15° and held for 80 ms |
| Look Down | `LivenessAction.lookDown` | Pitch angle drops below −15° and held for 80 ms |
| Smile | `LivenessAction.smile` | Smile probability exceeds 0.80 |
| Open Mouth | `LivenessAction.openMouth` | Bounding-box height growth > 8% and low smile probability |

---

## LivenessResult fields

```dart
class LivenessResult {
  final bool   isSuccess;
  final List<LivenessAction> completedActions;
  final double confidenceScore;   // 0.0 – 1.0
  final bool   isRealHuman;
  final bool   spoofDetected;
  final bool   deepfakeDetected;  // only set when TFLite is enabled
  final double? tfliteScore;
  final String? failureReason;
  final int?   sessionDurationMs;
  final String? sessionId;        // e.g. "LV-18f3a2b-9c4e"
}
```

---

## TFLite integration (optional)

The package ships with a plug-in interface for a custom deepfake/presentation-attack model. To enable it:

1. Add `tflite_flutter` to your app's `pubspec.yaml`:
   ```yaml
   dependencies:
     tflite_flutter: ^0.10.4
   ```

2. Place your `.tflite` model in `assets/` and register it:
   ```yaml
   flutter:
     assets:
       - assets/anti_spoof_model.tflite
   ```

3. Pass the path via config:
   ```dart
   config: LivenessConfig(
     enableTFLite: true,
     tfliteModelPath: 'assets/anti_spoof_model.tflite',
     tfliteInputSize: 128,
   ),
   ```

The model is expected to accept a `[1, H, W, 3]` float32 input (BGR image, normalised 0–1) and output `[1, 2]` — `[real_probability, spoof_probability]`.

---

## Architecture

```
FlutterFaceLiveness (Widget)
    └── LivenessController (ChangeNotifier)
            ├── CameraService        — camera lifecycle, frame streaming
            ├── FaceDetectorService  — ML Kit face detection
            │       └── FrameProcessor (compute isolate)
            │               ├── YUV → NV21 conversion
            │               ├── Brightness / blur analysis
            │               └── FNV-1a frame hash
            ├── LivenessEngine       — action sequencing, session lifecycle
            │       ├── BlinkDetector
            │       ├── HeadMovementDetector
            │       ├── SmileDetector
            │       ├── CameraValidator  — distance / centering checks
            │       ├── FrameHasher      — sliding-window replay detection
            │       └── SessionManager   — session ID + timeout
            └── AntiSpoofEngine      — 7-signal composite scoring
                    └── TFLiteService (optional)
```

---

## Performance notes

- ML Kit inference runs on the **main isolate** (required by platform channels); YUV byte conversion and quality analysis run on a **background isolate** via `compute()`.
- Frame processing is throttled to `config.targetFps` (default 20 fps) to balance detection speed against battery usage.
- Anti-spoof scoring uses a rolling history of the last 12 frames, so it works without any model file.
- On mid-range Android devices (e.g. Snapdragon 665), end-to-end per-frame latency is typically 40–60 ms.

---

## Security considerations

| Threat | Mitigation |
|--------|-----------|
| Printed photo attack | Eye variance + geometry signals in anti-spoof engine |
| Screen replay | Frame hash sliding window detects looped video |
| Pre-recorded video | Micro-motion signal (yaw/pitch variance over time) |
| Deepfake | Optional TFLite model plug-in |
| Fixed action sequence | Fisher-Yates shuffle each session |
| Session replay | Unique session ID + server-side validation |

---

## Example app

The `example/` directory contains a full demo app with:
- Light-themed home screen with three challenge presets
- Permission handling with a bottom sheet
- Result screen showing confidence, actions, session ID, anti-spoof status, and duration

Run it with:
```sh
cd example
flutter run
```

---

## Changelog

### 2.0.0
- Isolate-based ML preprocessing via `FrameProcessor`
- Frame quality validation (brightness, blur, overexposure)
- 7-signal `AntiSpoofEngine` with composite scoring
- FNV-1a frame hashing for replay-attack prevention
- `SessionManager` with unique session IDs
- `LivenessConfig` for all tunable parameters
- Random action ordering (Fisher-Yates)
- `openMouth` challenge action
- `LivenessStepIndicator` UI component
- Dark / light theme support
- TFLite plug-in interface
- `@Deprecated showDebugInfo` replaced by `LivenessConfig.showDebugOverlay`

### 1.x
- Initial release with blink, head-turn, look-up/down, smile actions
- Google ML Kit face detection
- Provider-based state management

---

## License

MIT — see [LICENSE](LICENSE)
