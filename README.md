# flutter_face_liveness

[![pub version](https://img.shields.io/pub/v/flutter_face_liveness.svg)](https://pub.dev/packages/flutter_face_liveness)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)]()

Production-ready AI-powered Flutter SDK for **real-time face liveness detection, anti-spoof protection, and persistent face identity** — powered by Google ML Kit + TensorFlow Lite. All processing runs **entirely on-device** with zero network calls (except the one-time FaceNet model download when Face ID is enabled).

---

## Table of Contents

- [Features](#features)
- [Use Cases](#use-cases)
- [Getting Started](#getting-started)
- [Quick Start](#quick-start)
- [Face Identity (Face ID)](#face-identity-face-id)
- [LivenessConfig Reference](#livenessconfig-reference)
- [Liveness Actions](#liveness-actions)
- [LivenessResult Fields](#livenessresult-fields)
- [TFLite Integration](#tflite-integration-optional)
- [Architecture](#architecture)
- [Performance](#performance)
- [Security](#security)
- [Example App](#example-app)
- [Changelog](#changelog)

---

## Features

| Category | Feature |
|----------|---------|
| **Liveness** | 7 challenge actions — blink, turn left/right, look up/down, smile, open mouth |
| **Face ID** | **Same face → always same ID**, across sessions, restarts, and days. Powered by FaceNet TFLite (auto-downloaded, one-time ~23 MB) |
| **Anti-Spoof** | 7-signal composite engine — eye variance, geometry, pose, micro-motion, quality, tracking |
| **Frame Quality** | Brightness (platform-correct BT.601 luminance), blur, overexposure — with debounce |
| **Replay Guard** | FNV-1a frame hashing detects looped / static-image attacks |
| **Session Security** | Cryptographically unique session IDs via `Random.secure()` |
| **Action Randomisation** | Fisher-Yates shuffle prevents predictable replay attacks |
| **Isolate ML** | YUV→NV21 conversion + quality analysis offloaded to background isolate |
| **TFLite Plug-in** | Drop in your own deepfake-detection model without changing package APIs |
| **Theming** | Dark / light mode via `LivenessConfig.themeMode` |
| **Debug Overlay** | Real-time Euler angles, eye/smile probabilities, brightness, blur on screen |

---

## Use Cases

### KYC (Know Your Customer)
Financial onboarding, account opening, and identity verification flows require proof that a real human is present — not a printed photo or screen replay.

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight],
  config: LivenessConfig(
    enableAntiSpoof: true,
    enableFaceId: true,          // assign a stable FID to this user
    randomizeActions: true,
  ),
  onSuccess: (result) {
    final faceId    = result.faceId;       // "FID-3A9F2B1C4E8D…"
    final sessionId = result.sessionId;    // "LV-018F3A2B9C4E-D7E31F08"
    final score     = result.confidenceScore;
    // Send faceId + sessionId to your backend for audit trail
  },
  onFailed: (reason) => showError(reason),
)
```

### Banking / Fintech
Transaction authorisation, step-up authentication, and high-risk operation confirmation. Face ID ensures the authorising person is the account holder across every session.

```dart
// On every login / transaction:
config: LivenessConfig(
  enableFaceId: true,
  faceIdSimilarityThreshold: 0.72,  // stricter for banking
  enableAntiSpoof: true,
  sessionTimeoutMs: 30000,           // 30-second window
),
onSuccess: (result) {
  if (result.faceId == storedFaceId) {
    authoriseTransaction();
  } else {
    flagForReview();   // different face from enrolled user
  }
}
```

### Attendance Systems
Employee / student attendance where the same person must be recognised across multiple daily check-ins.

```dart
// Enrolment (first check-in): faceId is new → store in database
// Daily check-in: same faceId returned → mark present
config: LivenessConfig(
  enableFaceId: true,
  enableAntiSpoof: true,
  actions: [LivenessAction.blink],   // quick single-action check
),
```

### Authentication / Biometric Login
Replace or augment PIN/password with a liveness-verified face. The persistent Face ID acts as the biometric credential stored on-device.

```dart
config: LivenessConfig(
  enableFaceId: true,
  faceIdSimilarityThreshold: 0.70,
  enableBrightnessCheck: true,
),
onSuccess: (result) {
  if (result.faceId == prefs.getString('enrolled_face_id')) {
    unlockApp();
  } else {
    showError('Face not recognised — please contact support');
  }
}
```

### Enterprise Security
Multi-factor authentication, access control, and audit logging for enterprise applications.

```dart
// Log who performed each sensitive action
onSuccess: (result) {
  auditLog.record(
    userId:    result.faceId,
    sessionId: result.sessionId,
    timestamp: DateTime.now(),
    actions:   result.completedActions.map((a) => a.name).toList(),
    score:     result.confidenceScore,
  );
}
```

---

## Getting Started

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

| Platform | Minimum | Notes |
|----------|---------|-------|
| Android  | API 26 (Android 8.0) | Required by TFLite Flutter 0.12+ |
| iOS      | iOS 13.0 | |
| Dart     | 3.0.0 | |
| Flutter  | 3.10.0 | |

**Android** — `android/app/build.gradle`:

```groovy
defaultConfig {
    minSdk 26
}
```

### 4. Internet permission (only if using Face ID)

Face ID downloads the FaceNet model (~23 MB) on first launch. Add internet permission:

**Android** — `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

The model is cached permanently after the first download — no subsequent network calls.

---

## Quick Start

```dart
import 'package:flutter_face_liveness/flutter_face_liveness.dart';

class VerificationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FlutterFaceLiveness(
      actions: [
        LivenessAction.blink,
        LivenessAction.turnLeft,
        LivenessAction.turnRight,
      ],
      config: LivenessConfig(
        randomizeActions: true,
        enableAntiSpoof: true,
      ),
      onSuccess: (LivenessResult result) {
        print('Verified!');
        print('Session ID  : ${result.sessionId}');
        print('Confidence  : ${(result.confidenceScore * 100).toStringAsFixed(1)}%');
        print('Duration    : ${result.sessionDurationMs}ms');
        print('Anti-spoof  : ${result.spoofDetected ? "FAILED" : "PASSED"}');
      },
      onFailed: (String reason) {
        print('Failed: $reason');
      },
    );
  }
}
```

---

## Face Identity (Face ID)

> **Key guarantee**
>
> A Face ID (`FID-XXXX`) is **permanently tied to one physical person's face**.
> No matter how many times the same person is detected — different sessions,
> different days, different lighting, after app restarts — they will **always
> receive the exact same Face ID**. A new ID is only generated the very first
> time a completely unknown face is seen.
>
> ```
> User scans face on Day 1  →  FID-3A9F2B1C4E8D7F62
> User scans face on Day 7  →  FID-3A9F2B1C4E8D7F62   ← same ID
> User scans face on Day 30 →  FID-3A9F2B1C4E8D7F62   ← same ID
> Different person scans    →  FID-A817C3F0B24E9D51   ← new ID
> ```

### How it works

1. **First detection** — FaceNet extracts a 128-dimensional embedding from the verified face crop. A unique ID is generated (`FID-3A9F2B1C4E8D…`) and persisted in `SharedPreferences`.
2. **Every subsequent detection** — The new embedding is compared against all stored embeddings using cosine similarity. If the best match scores ≥ `faceIdSimilarityThreshold` (default `0.65`), **the same `FID-XXXX` is returned — no new ID is ever created for that person**.
3. **Adapts over time** — On every confirmed match the stored template blends toward the new observation (`75% old + 25% new`, re-normalised). This means the Face ID stays accurate even as lighting, hairstyle, or camera angle changes.
4. **Survives everything** — Face IDs persist across app restarts, app updates, phone restarts, and re-installs (data lives in `SharedPreferences`; only cleared explicitly via `clearFaceIdentities()`).

### Enable it

```dart
config: LivenessConfig(
  enableFaceId: true,
  // optional — raise for stricter, lower for more lenient matching
  faceIdSimilarityThreshold: 0.65,
),
onSuccess: (result) {
  final faceId = result.faceId;   // e.g. "FID-3A9F2B1C4E8D7F62A091"
  print('Face ID: $faceId');
},
```

### First-run download progress

On first launch with `enableFaceId: true`, the FaceNet model (~23 MB) is downloaded automatically. The built-in loading screen shows download progress. No code required.

To show custom progress UI, listen to the controller:

```dart
// Using LivenessController directly (advanced use)
final controller = LivenessController(
  actions: [...],
  config: LivenessConfig(enableFaceId: true),
  onSuccess: ...,
  onFailed: ...,
);
// controller.faceIdModelDownloadProgress — double? (0.0–1.0 during download, null otherwise)
```

### Managing stored faces

```dart
// Access the controller
final controller = LivenessController(...);

// Delete all stored faces (e.g. on logout)
await controller.clearFaceIdentities();

// Or use FaceIdentityService directly:
final service = FaceIdentityService();
await service.initialize();

List<String> ids = service.registeredFaceIds;  // all IDs on this device
await service.removeFace('FID-3A9F2B…');        // remove one face
await service.clearAllFaces();                  // remove all faces
```

### Cosine similarity thresholds guide

| Threshold | Behaviour |
|-----------|-----------|
| `0.50` | Very lenient — may match different people in similar conditions |
| `0.65` | **Default** — good balance for normal use (different lighting, slight angle) |
| `0.72` | Stricter — recommended for banking / high-security apps |
| `0.80` | Very strict — may produce new IDs for same person in different lighting |

---

## LivenessConfig Reference

```dart
LivenessConfig({
  // Session
  int sessionTimeoutMs = 60000,
  bool randomizeActions = true,

  // Camera
  ResolutionPreset cameraResolution = ResolutionPreset.high,
  int targetFps = 20,

  // Anti-spoof
  bool enableAntiSpoof = true,
  double antiSpoofThreshold = 0.45,

  // Frame quality
  bool enableBrightnessCheck = true,
  double brightnessMin = 0.12,
  double brightnessMax = 0.92,
  bool enableBlurDetection = true,
  double blurThreshold = 80.0,
  bool enableDuplicateFrameDetection = true,
  int duplicateFrameWindowSize = 8,

  // Face geometry
  double faceTooFarRatio = 0.015,
  double faceTooCloseRatio = 0.70,

  // Face Identity
  bool enableFaceId = false,
  double faceIdSimilarityThreshold = 0.65,

  // TFLite (optional custom model)
  bool enableTFLite = false,
  String? tfliteModelPath,
  int tfliteInputSize = 128,

  // UI
  ThemeMode themeMode = ThemeMode.dark,
  bool showDebugOverlay = false,
})
```

### Full parameter table

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sessionTimeoutMs` | `int` | `60000` | Auto-fail after this many ms. Set lower for quick checks. |
| `randomizeActions` | `bool` | `true` | Shuffle action order each session (prevents replay attacks) |
| `cameraResolution` | `ResolutionPreset` | `high` | Camera resolution. `medium` reduces CPU on low-end devices |
| `targetFps` | `int` | `20` | Frame processing rate (1–30 fps) |
| `enableAntiSpoof` | `bool` | `true` | 7-signal composite anti-spoof heuristic check |
| `antiSpoofThreshold` | `double` | `0.45` | Minimum composite score to pass (0.0–1.0) |
| `enableBrightnessCheck` | `bool` | `true` | Block frames that are too dark or overexposed |
| `brightnessMin` | `double` | `0.12` | Minimum Y-luminance ratio. Below this = genuinely dark room |
| `brightnessMax` | `double` | `0.92` | Maximum Y-luminance ratio. Above this = overexposed / direct sun |
| `enableBlurDetection` | `bool` | `true` | Block blurry frames |
| `blurThreshold` | `double` | `80.0` | Y-plane variance; below this = blurry |
| `enableDuplicateFrameDetection` | `bool` | `true` | Hash-based looped-video / static-image detection |
| `duplicateFrameWindowSize` | `int` | `8` | Sliding window size for duplicate streak detection |
| `faceTooFarRatio` | `double` | `0.015` | Face bounding-box area ratio below which = "too far" |
| `faceTooCloseRatio` | `double` | `0.70` | Face bounding-box area ratio above which = "too close" |
| `enableFaceId` | `bool` | `false` | Enable persistent face identity. Model auto-downloaded on first run |
| `faceIdSimilarityThreshold` | `double` | `0.65` | Cosine similarity cutoff for same-face matching (0.0–1.0) |
| `enableTFLite` | `bool` | `false` | Enable custom TFLite deepfake/PAD model inference |
| `tfliteModelPath` | `String?` | `null` | Flutter asset path to `.tflite` model file |
| `tfliteInputSize` | `int` | `128` | Model input size (square, px) |
| `themeMode` | `ThemeMode` | `dark` | Widget theme. `ThemeMode.system` follows device theme |
| `showDebugOverlay` | `bool` | `false` | Show Euler angles, eye/smile probabilities, brightness, blur |

---

## Liveness Actions

| Action | Enum | How it triggers |
|--------|------|----------------|
| Blink | `LivenessAction.blink` | Both eye open-probability drops below 0.40, then returns above 0.75 |
| Turn Left | `LivenessAction.turnLeft` | Yaw angle > +15° held for ≥ 80 ms |
| Turn Right | `LivenessAction.turnRight` | Yaw angle < −15° held for ≥ 80 ms |
| Look Up | `LivenessAction.lookUp` | Pitch angle > +15° held for ≥ 80 ms |
| Look Down | `LivenessAction.lookDown` | Pitch angle < −15° held for ≥ 80 ms |
| Smile | `LivenessAction.smile` | Smile probability > 0.80 |
| Open Mouth | `LivenessAction.openMouth` | Face bounding-box height grows > 8% with smile probability < 0.30 |

### Recommended action combinations

```dart
// Quick check (low friction)
[LivenessAction.blink]

// Standard (recommended for most apps)
[LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight]

// High-security KYC
[LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight, LivenessAction.smile]

// Full challenge
[LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight,
 LivenessAction.lookUp, LivenessAction.openMouth]
```

---

## LivenessResult Fields

```dart
class LivenessResult {
  final bool   isSuccess;
  final List<LivenessAction> completedActions;
  final double confidenceScore;    // 0.0–1.0 composite anti-spoof score
  final bool   isRealHuman;        // true when anti-spoof passes
  final bool   spoofDetected;      // true if heuristic anti-spoof triggered
  final bool   deepfakeDetected;   // true if TFLite model triggered (when enabled)
  final double? tfliteScore;       // raw TFLite model output (when enabled)
  final String? failureReason;     // human-readable reason on failure
  final int?   sessionDurationMs;  // total session time in milliseconds
  final String? sessionId;         // e.g. "LV-018F3A2B9C4E-D7E31F08"
  final String? faceId;            // e.g. "FID-3A9F2B1C4E8D7F62A091" (when enableFaceId: true)
}
```

### Handling the result

```dart
onSuccess: (LivenessResult result) {
  // 1. Always check isSuccess
  assert(result.isSuccess);

  // 2. Confidence score
  if (result.confidenceScore < 0.6) {
    // Low confidence — show a re-attempt prompt
  }

  // 3. Face ID (only set when enableFaceId: true)
  if (result.faceId != null) {
    final isReturningUser = myDatabase.contains(result.faceId!);
    if (isReturningUser) {
      loginUser(result.faceId!);
    } else {
      registerUser(result.faceId!);
    }
  }

  // 4. Session ID — send to backend for server-side audit
  myBackend.logSession(
    sessionId: result.sessionId!,
    faceId:    result.faceId,
    score:     result.confidenceScore,
  );
},
```

---

## TFLite Integration (Optional)

The package includes a plug-in interface for a custom deepfake / presentation-attack-detection model. Use this to layer additional ML-based anti-spoof on top of the built-in heuristics.

### Expected model contract

| Property | Requirement |
|----------|------------|
| Input shape | `[1, H, W, 3]` float32 |
| Input range | `0.0–1.0` (BGR, normalised) |
| Output shape | `[1, 2]` |
| Output meaning | `[real_probability, spoof_probability]` |

### Setup

1. Place your `.tflite` model in `assets/`:
   ```
   assets/
   └── anti_spoof.tflite
   ```

2. Register in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/anti_spoof.tflite
   ```

3. Pass the path via config:
   ```dart
   config: LivenessConfig(
     enableTFLite: true,
     tfliteModelPath: 'assets/anti_spoof.tflite',
     tfliteInputSize: 128,  // or 256, 224, etc.
   ),
   ```

4. Read the result:
   ```dart
   onSuccess: (result) {
     print('TFLite score : ${result.tfliteScore}');
     print('Deepfake     : ${result.deepfakeDetected}');
   },
   ```

---

## Architecture

```
FlutterFaceLiveness (Widget)
    └── LivenessController (ChangeNotifier)
            │
            ├── Camera Layer
            │       ├── CameraService        — camera lifecycle, frame streaming, throttling
            │       └── CameraValidator      — distance, centering, geometry checks
            │
            ├── ML Layer
            │       ├── FaceDetectorService  — Google ML Kit face detection + RawFrameData capture
            │       └── FrameProcessor       — compute() isolate
            │               ├── YUV → NV21 conversion (Android) / BGRA pass-through (iOS)
            │               ├── BT.601 brightness (platform-correct)
            │               ├── Y-plane blur score (variance)
            │               └── FNV-1a frame hash
            │
            ├── Liveness Layer
            │       ├── LivenessEngine       — action sequencing, session lifecycle, debounce
            │       ├── BlinkDetector        — open→close→open eye state machine
            │       ├── HeadMovementDetector — Euler angle threshold + hold timer
            │       └── SessionManager       — secure session ID + timeout
            │
            ├── Security Layer
            │       ├── AntiSpoofEngine      — 7-signal composite scoring (12-frame rolling window)
            │       ├── FrameHasher          — FNV-1a sliding-window duplicate detection
            │       └── TFLiteService        — optional custom deepfake model inference
            │
            └── Face Identity Layer (optional)
                    ├── FaceIdentityService  — cosine matching + SharedPreferences persistence
                    ├── FaceEmbeddingModel   — FaceNet TFLite interpreter (128-dim embeddings)
                    ├── FacePreprocessor     — face crop + resize + normalise (compute isolate)
                    └── FaceModelDownloader  — streaming HTTP download + cache validation
```

---

## Performance

| Metric | Value |
|--------|-------|
| Per-frame latency (mid-range Android) | 40–60 ms |
| Per-frame latency (iPhone 12+) | 20–35 ms |
| Frame processing rate (default) | 20 fps |
| FaceNet inference (on-device) | ~80 ms (first inference after load) |
| FaceNet inference (warm) | ~30–50 ms |
| Memory footprint (base, no Face ID) | ~45 MB |
| Memory footprint (with Face ID loaded) | ~90 MB |

**Threading model:**
- ML Kit face detection — main isolate (platform channel requirement)
- YUV conversion + brightness/blur/hash — background isolate (`compute()`)
- Face crop + FaceNet inference — background isolate (`compute()`)
- UI rendering — main thread, never blocked

**Tuning tips:**
- Lower `targetFps` to `15` on low-end devices to reduce CPU load
- Use `ResolutionPreset.medium` if 60 fps UI rendering is dropping frames
- Set `enableFaceId: false` if you don't need identity — saves ~45 MB RAM and skips FaceNet inference

---

## Security

| Threat | Mitigation |
|--------|-----------|
| Printed photo | Eye variance + face geometry signals in `AntiSpoofEngine` |
| Screen replay (looped video) | FNV-1a frame hash sliding-window in `FrameHasher` |
| Static image | Duplicate frame detection + micro-motion requirement |
| Pre-recorded live video | Micro-motion signal (yaw/pitch variance over rolling window) |
| Deepfake / synthetic face | Optional TFLite model plug-in for ML-based PAD |
| Predictable action sequence | Fisher-Yates shuffle per session |
| Session replay attack | Cryptographically unique `sessionId` via `Random.secure()` |
| Face spoofing (different person) | FaceNet cosine similarity ≥ threshold for Face ID matching |
| Low-quality frames sneaking through | Brightness debounce + blur check before any liveness evaluation |

> **Note:** This package provides strong on-device liveness verification. For high-assurance KYC (banking, government), pair the `sessionId` and `faceId` with a server-side signature verification step.

---

## Example App

The `example/` directory contains a full demo app with:

- Home screen with four challenge presets (Standard, Extended, Full, With Face ID)
- Registered face IDs card — shows all stored Face IDs, tap any to copy, "Clear all" resets
- Permission handling with a bottom sheet
- Result screen with:
  - Confidence score, completed actions, anti-spoof status, session duration
  - Face ID row — tap to copy to clipboard
  - Session ID

```sh
cd example
flutter run
```

> **Testing Face ID:** Use the **"With Face ID"** button. Complete the check → note the `FID-XXXX` in the result screen (tap it to copy). Close the app completely, reopen it, run the check again — **the exact same `FID-XXXX` will be returned**. This is the core guarantee: one face, one ID, forever.

---

## License

MIT — see [LICENSE](LICENSE)

---

## Author

Developed by [Cerise Tech Solutions](https://cerisetechsolutions.com)  
GitHub: [sanjaysharmajw/flutter_face_liveness](https://github.com/sanjaysharmajw/flutter_face_liveness)  
Issues: [github.com/sanjaysharmajw/flutter_face_liveness/issues](https://github.com/sanjaysharmajw/flutter_face_liveness/issues)
