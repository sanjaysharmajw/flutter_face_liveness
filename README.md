# flutter_face_liveness

A production-ready Flutter package for real-time face detection and liveness verification using **Google ML Kit Face Detection**.

Designed for KYC, attendance, and identity verification — built with clean architecture, throttled frame processing, and an anti-spoofing heuristic layer.

---

## Features

| Feature | Details |
|---|---|
| **Real-time detection** | Camera stream (not image capture) with ~10 fps ML processing |
| **Face tracking** | Bounding box, Euler angles (yaw/pitch/roll), tracking ID |
| **Liveness actions** | Blink, turn left/right, look up/down, smile |
| **Anti-spoofing** | Heuristic validator rejects photos, screens, and cartoon faces |
| **Clean architecture** | Camera layer → ML layer → Liveness engine → UI overlay |
| **Provider state** | `ChangeNotifier`-based controller; works with any state management |
| **Null safety** | Full Dart 3 / null-safe codebase |
| **Platform** | Android (API 21+) · iOS 13+ |

---

## Getting started

### 1. Add dependency

```yaml
dependencies:
  flutter_face_liveness: ^1.0.0
```

### 2. Android — camera permission

Add to your app's `AndroidManifest.xml` (inside `<manifest>`):

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera.front" android:required="true" />
```

Enable Proguard rules (already included in the package via `consumerProguardFiles`).

### 3. iOS — camera permission

Add to your app's `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for face liveness verification.</string>
```

Minimum deployment target: **iOS 13.0**  
Set in `ios/Podfile`: `platform :ios, '13.0'`

### 4. Request permission before navigating

```dart
import 'package:permission_handler/permission_handler.dart';

final status = await Permission.camera.request();
if (status.isGranted) {
  // navigate to liveness screen
}
```

---

## Usage

### Basic

```dart
import 'package:flutter_face_liveness/flutter_face_liveness.dart';

FlutterFaceLiveness(
  actions: [
    LivenessAction.blink,
    LivenessAction.turnLeft,
    LivenessAction.turnRight,
  ],
  onSuccess: (LivenessResult result) {
    print('Verified! confidence=${result.confidenceScore}');
    print('Completed: ${result.completedActions}');
    print('Session: ${result.sessionDurationMs}ms');
  },
  onFailed: (String reason) {
    print('Failed: $reason');
  },
)
```

### All available actions

```dart
actions: [
  LivenessAction.blink,       // close both eyes and re-open
  LivenessAction.turnLeft,    // yaw head to the left
  LivenessAction.turnRight,   // yaw head to the right
  LivenessAction.lookUp,      // pitch head upward
  LivenessAction.lookDown,    // pitch head downward
  LivenessAction.smile,       // smile probability > 0.8
],
```

### Optional parameters

```dart
FlutterFaceLiveness(
  actions: [...],
  onSuccess: ...,
  onFailed: ...,
  sessionTimeoutMs: 45000,                      // default 60 000 ms
  cameraResolution: ResolutionPreset.medium,    // default high
  showDebugInfo: true,                          // show Euler angles overlay
)
```

### Headless usage (controller only)

Use `LivenessController` directly if you want to build your own UI:

```dart
final controller = LivenessController(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  onSuccess: (result) { ... },
  onFailed: (reason) { ... },
);

await controller.initialize();

// Read state
controller.status;          // DetectionStatus
controller.currentAction;   // LivenessAction?
controller.progress;        // 0.0–1.0
controller.completedCount;  // int

// Cleanup
await controller.dispose();
```

---

## Architecture

```
flutter_face_liveness/
├── lib/
│   ├── flutter_face_liveness.dart          # Public API barrel
│   └── src/
│       ├── models/
│       │   ├── face_data.dart              # Processed ML Kit face output
│       │   ├── liveness_action.dart        # Challenge action enum
│       │   ├── liveness_result.dart        # Success/failure result
│       │   └── detection_status.dart       # UI state enum
│       ├── camera/
│       │   └── camera_service.dart         # Camera lifecycle + frame throttle
│       ├── ml/
│       │   ├── face_detector_service.dart  # ML Kit wrapper + image conversion
│       │   └── human_validator.dart        # Anti-spoof heuristic scoring
│       ├── liveness/
│       │   ├── liveness_engine.dart        # Orchestrator / state machine
│       │   ├── blink_detector.dart         # Eye-open probability FSM
│       │   └── head_movement_detector.dart # Euler angle FSM
│       ├── ui/
│       │   ├── face_overlay_painter.dart   # Custom painter (oval + bounds)
│       │   ├── liveness_instructions_widget.dart
│       │   └── status_indicator_widget.dart
│       ├── liveness_controller.dart        # ChangeNotifier glue layer
│       └── flutter_face_liveness_widget.dart # Main exported widget
```

### Data flow

```
CameraStream → CameraService (throttle 100ms)
     ↓
FaceDetectorService (ML Kit) → List<FaceData>
     ↓
LivenessEngine
  ├─ HumanValidator     (anti-spoof confidence score)
  ├─ BlinkDetector      (eye-open probability FSM)
  └─ HeadMovementDetector (Euler angle FSM)
     ↓
LivenessController (ChangeNotifier) → Widget tree
```

---

## Anti-spoofing approach

Because ML Kit does not expose a dedicated depth/texture spoof model, `HumanValidator` combines five signals:

| Signal | Weight | What it catches |
|---|---|---|
| Eye-open probability variance over 10 frames | 30% | Static photos (frozen eye states) |
| Face bounding-box aspect ratio | 20% | Cartoons, masks, extreme crops |
| Head roll angle plausibility | 15% | Flat screens held edge-on |
| Natural eye-open values (not exactly 0 or 1) | 20% | Photo artefacts |
| Tracking ID stability across frames | 15% | Temporary objects |

The composite score threshold is **0.55**. Combined with the active liveness challenge (which requires physical movement), this provides strong practical anti-spoofing for mobile KYC use cases.

---

## Performance

- Frame throttle: **100 ms** between ML Kit calls (~10 fps processing, 30+ fps preview)
- `FaceDetectorMode.fast` — optimises for mobile latency
- Landmarks and contours are disabled (not needed for liveness)
- `minFaceSize: 0.15` — ignores background noise faces
- All ML processing happens on the camera image stream callback; the Flutter UI isolate is not blocked

---

## Error states

| `DetectionStatus` | Shown when |
|---|---|
| `noFace` | No face in frame for 15+ consecutive frames |
| `multipleFaces` | More than one face detected |
| `faceTooFar` | Face bounding box < 4% of image area |
| `faceTooClose` | Face bounding box > 60% of image area |
| `faceNotCentered` | Face center > 25% from image center |
| `fakeDetected` | Human validator confidence < 0.55 |
| `failed` | Session timeout (default 60 s) |

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
