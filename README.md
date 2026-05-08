# flutter_face_liveness

[![pub version](https://img.shields.io/pub/v/flutter_face_liveness.svg)](https://pub.dev/packages/flutter_face_liveness)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)]()

![flutter_face_liveness banner](https://raw.githubusercontent.com/sanjaysharmajw/flutter_face_liveness/main/screenshots/banner.png)

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
- [LivenessController API](#livenesscontroller-api)
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
| **New/Returning** | `isFaceIdNew` flag tells you instantly if it's a first-time or returning face |
| **Anti-Spoof** | 7-signal composite engine — eye variance, geometry, pose, micro-motion, quality, tracking |
| **Frame Quality** | BT.601 platform-correct brightness (Android NV21 + iOS BGRA8888), blur, overexposure — with 6-frame debounce |
| **Replay Guard** | FNV-1a frame hashing detects looped / static-image attacks |
| **Session Security** | Cryptographically unique session IDs via `Random.secure()` |
| **Action Randomisation** | Fisher-Yates shuffle prevents predictable replay attacks |
| **Isolate ML** | YUV→NV21 conversion, quality analysis, and face embedding — all in background isolates |
| **TFLite Plug-in** | Drop in your own deepfake-detection model without changing package APIs |
| **Theming** | Dark / light / system mode via `LivenessConfig.themeMode` |
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
    enableFaceId: true,
    randomizeActions: true,
  ),
  onSuccess: (result) {
    final faceId    = result.faceId;        // "FID-3A9F2B1C4E8D…"
    final isNew     = result.isFaceIdNew;   // true = first time, false = returning
    final sessionId = result.sessionId;     // "LV-018F3A2B9C4E-D7E31F08"
    final score     = result.confidenceScore;
    // Send faceId + sessionId to your backend for audit trail
  },
  onFailed: (reason) => showError(reason),
)
```

### Banking / Fintech
Transaction authorisation, step-up authentication, and high-risk operation confirmation. Face ID ensures the authorising person is the account holder across every session.

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.smile],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdSimilarityThreshold: 0.72,  // stricter for banking
    enableAntiSpoof: true,
    sessionTimeoutMs: 30000,           // 30-second window
  ),
  onSuccess: (result) {
    if (result.isFaceIdNew == false && result.faceId == storedFaceId) {
      authoriseTransaction();   // returning, known face
    } else {
      flagForReview();          // new or unexpected face
    }
  },
  onFailed: (reason) => showError(reason),
)
```

### Attendance Systems
Employee / student attendance where the same person must be recognised across multiple daily check-ins.

```dart
// Enrolment (first check-in): isFaceIdNew == true → store faceId in database
// Daily check-in:             isFaceIdNew == false → mark present
FlutterFaceLiveness(
  actions: [LivenessAction.blink],   // quick single-action check
  config: LivenessConfig(
    enableFaceId: true,
    enableAntiSpoof: true,
  ),
  onSuccess: (result) {
    if (result.isFaceIdNew == true) {
      db.enrolEmployee(result.faceId!);
    } else {
      db.markAttendance(result.faceId!, DateTime.now());
    }
  },
  onFailed: (reason) => showError(reason),
)
```

### Authentication / Biometric Login
Replace or augment PIN/password with a liveness-verified face. The persistent Face ID acts as the biometric credential stored on-device.

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdSimilarityThreshold: 0.70,
    enableBrightnessCheck: true,
  ),
  onSuccess: (result) {
    final enrolled = prefs.getString('enrolled_face_id');
    if (result.isFaceIdNew == false && result.faceId == enrolled) {
      unlockApp();
    } else if (enrolled == null && result.isFaceIdNew == true) {
      prefs.setString('enrolled_face_id', result.faceId!);
      showEnrolmentSuccess();
    } else {
      showError('Face not recognised — please contact support');
    }
  },
  onFailed: (reason) => showError(reason),
)
```

### Enterprise Security
Multi-factor authentication, access control, and audit logging for enterprise applications.

```dart
onSuccess: (result) {
  auditLog.record(
    faceId:    result.faceId,
    isNewFace: result.isFaceIdNew,
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
<!-- Required only when enableFaceId: true -->
<uses-permission android:name="android.permission.INTERNET" />
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

### 4. Fix tflite_flutter for Dart 3.4+

`tflite_flutter 0.10.4` (pub.dev) uses `UnmodifiableUint8ListView` which was removed in Dart 3.4. Add a `dependency_overrides` block to pull the fixed version from git:

```yaml
# pubspec.yaml
dependency_overrides:
  tflite_flutter:
    git:
      url: https://github.com/tensorflow/flutter-tflite.git
      ref: main
```

This resolves to `tflite_flutter 0.12.1` automatically. No other changes required.

### 5. Internet permission note (Face ID only)

The FaceNet model (~23 MB) is downloaded **once** on first launch with `enableFaceId: true` and cached permanently in the app's documents directory. All subsequent launches use the local cache — no network required.

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
> User scans face on Day 1  →  FID-3A9F2B1C4E8D7F62   isFaceIdNew: true
> User scans face on Day 7  →  FID-3A9F2B1C4E8D7F62   isFaceIdNew: false  ← same ID
> User scans face on Day 30 →  FID-3A9F2B1C4E8D7F62   isFaceIdNew: false  ← same ID
> Different person scans    →  FID-A817C3F0B24E9D51   isFaceIdNew: true   ← new ID
> ```

### How it works

1. **First detection** — FaceNet extracts a 128-dimensional embedding from the verified face crop. A unique ID is generated (`FID-3A9F2B1C4E8D…`) and persisted in `SharedPreferences`. `isFaceIdNew` is `true`.
2. **Every subsequent detection** — The new embedding is compared against all stored embeddings using cosine similarity. If the best match scores ≥ `faceIdSimilarityThreshold` (default `0.65`), **the same `FID-XXXX` is returned**. `isFaceIdNew` is `false`.
3. **Adapts over time** — On every confirmed match the stored template is blended: `stored = 0.75 × stored + 0.25 × new` (then re-normalised to unit length). The Face ID stays accurate even as lighting, hairstyle, or camera angle changes session to session.
4. **Survives everything** — Face IDs persist across app restarts, app updates, phone restarts, and re-installs (stored in `SharedPreferences`; only cleared via `clearFaceIdentities()`).

### Enable it

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdSimilarityThreshold: 0.65,  // default — good for most apps
  ),
  onSuccess: (result) {
    final faceId = result.faceId!;       // "FID-3A9F2B1C4E8D7F62A091"
    final isNew  = result.isFaceIdNew!;  // true = registered, false = matched

    if (isNew) {
      print('New face registered: $faceId');
    } else {
      print('Welcome back! Recognised as: $faceId');
    }
  },
  onFailed: (reason) => print('Failed: $reason'),
)
```

### First-run download progress

On first launch with `enableFaceId: true`, the built-in loading screen shows the download percentage automatically. No code required.

To observe progress from outside the widget:

```dart
final controller = LivenessController(
  actions: [...],
  config: LivenessConfig(enableFaceId: true),
  onSuccess: ...,
  onFailed:  ...,
);

// Rebuild when this changes (it's a ChangeNotifier getter)
// double? faceIdModelDownloadProgress  →  0.0–1.0 during download, null otherwise
```

### Managing stored faces

```dart
// Via LivenessController (recommended)
await controller.clearFaceIdentities();   // delete all on logout

// Via FaceIdentityService directly (advanced)
final service = FaceIdentityService(similarityThreshold: 0.65);
await service.initialize(
  onModelDownloadProgress: (p) => print('${(p * 100).toInt()}%'),
);

List<String> ids = service.registeredFaceIds;  // all IDs on this device
await service.removeFace('FID-3A9F2B…');        // remove one specific face
await service.clearAllFaces();                  // remove all faces
service.dispose();
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
  int    sessionTimeoutMs  = 60000,
  bool   randomizeActions  = true,

  // Camera
  ResolutionPreset cameraResolution = ResolutionPreset.high,
  int    targetFps         = 20,

  // Anti-spoof
  bool   enableAntiSpoof      = true,
  double antiSpoofThreshold   = 0.45,

  // Frame quality  (brightness debounce: 6 consecutive bad frames required)
  bool   enableBrightnessCheck = true,
  double brightnessMin         = 0.12,   // below = genuinely dark room
  double brightnessMax         = 0.92,   // above = direct sunlight / overexposed
  bool   enableBlurDetection   = true,
  double blurThreshold         = 80.0,
  bool   enableDuplicateFrameDetection = true,
  int    duplicateFrameWindowSize      = 8,

  // Face geometry
  double faceTooFarRatio   = 0.015,
  double faceTooCloseRatio = 0.70,

  // Face Identity
  bool   enableFaceId                = false,
  double faceIdSimilarityThreshold   = 0.65,

  // TFLite (optional custom model)
  bool    enableTFLite    = false,
  String? tfliteModelPath = null,
  int     tfliteInputSize = 128,

  // UI
  ThemeMode themeMode       = ThemeMode.dark,
  bool      showDebugOverlay = false,
})
```

### Full parameter table

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sessionTimeoutMs` | `int` | `60000` | Auto-fail after this many ms |
| `randomizeActions` | `bool` | `true` | Fisher-Yates shuffle per session — prevents replay attacks |
| `cameraResolution` | `ResolutionPreset` | `high` | `medium` reduces CPU on low-end devices |
| `targetFps` | `int` | `20` | Frame processing rate (1–30 fps) |
| `enableAntiSpoof` | `bool` | `true` | 7-signal composite anti-spoof heuristic |
| `antiSpoofThreshold` | `double` | `0.45` | Minimum composite score to pass (0.0–1.0) |
| `enableBrightnessCheck` | `bool` | `true` | Block frames that are too dark or overexposed |
| `brightnessMin` | `double` | `0.12` | Y-luminance below this = genuinely dark room. Uses BT.601 on iOS (BGRA) and Y-plane on Android (NV21). Triggers only after **6 consecutive** dark frames to absorb camera auto-exposure settling |
| `brightnessMax` | `double` | `0.92` | Y-luminance above this = overexposed / direct sun. Same 6-frame debounce applies |
| `enableBlurDetection` | `bool` | `true` | Block blurry frames |
| `blurThreshold` | `double` | `80.0` | Y-plane variance; below this = blurry |
| `enableDuplicateFrameDetection` | `bool` | `true` | FNV-1a hash sliding-window replay detection |
| `duplicateFrameWindowSize` | `int` | `8` | Sliding window size for duplicate streak |
| `faceTooFarRatio` | `double` | `0.015` | Face bounding-box area ratio below which = "too far" |
| `faceTooCloseRatio` | `double` | `0.70` | Face bounding-box area ratio above which = "too close" |
| `enableFaceId` | `bool` | `false` | Persistent face identity. FaceNet model auto-downloaded on first run |
| `faceIdSimilarityThreshold` | `double` | `0.65` | Cosine similarity cutoff. Same face across lighting/angle typically scores 0.65–0.85 |
| `enableTFLite` | `bool` | `false` | Custom TFLite deepfake / PAD model |
| `tfliteModelPath` | `String?` | `null` | Flutter asset path to `.tflite` model |
| `tfliteInputSize` | `int` | `128` | Model input size (square, px) |
| `themeMode` | `ThemeMode` | `dark` | `ThemeMode.system` follows device theme |
| `showDebugOverlay` | `bool` | `false` | Euler angles, eye/smile probabilities, brightness, blur |

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
| Open Mouth | `LivenessAction.openMouth` | Bounding-box height grows > 8% with smile probability < 0.30 |

### Recommended action combinations

```dart
// Quick check (low friction)
actions: [LivenessAction.blink]

// Standard (recommended for most apps)
actions: [LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight]

// High-security KYC
actions: [LivenessAction.blink, LivenessAction.turnLeft,
          LivenessAction.turnRight, LivenessAction.smile]

// Full challenge
actions: [LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight,
          LivenessAction.lookUp, LivenessAction.openMouth]
```

---

## LivenessResult Fields

```dart
class LivenessResult {
  final bool   isSuccess;
  final List<LivenessAction> completedActions;
  final double confidenceScore;   // 0.0–1.0 composite anti-spoof score
  final bool   isRealHuman;       // true when anti-spoof passes
  final bool   spoofDetected;     // true if heuristic signals triggered
  final bool   deepfakeDetected;  // true if TFLite model triggered (when enabled)
  final double? tfliteScore;      // raw TFLite model output (when enabled)
  final String? failureReason;    // human-readable reason on failure
  final int?   sessionDurationMs; // total session time in ms

  // Session ID format: "LV-{12-char-timestamp-hex}-{8-char-secure-random-hex}"
  // e.g. "LV-018F3A2B9C4E-D7E31F08"  — generated via Random.secure()
  final String? sessionId;

  // Face ID format: "FID-{24 uppercase hex chars}"
  // e.g. "FID-3A9F2B1C4E8D7F62A091B3C5"  — non-null only when enableFaceId: true
  final String? faceId;

  // true  → this face was seen for the FIRST TIME — new ID was created
  // false → this face was RECOGNISED — existing ID returned
  // null  → Face ID is disabled (enableFaceId: false)
  final bool? isFaceIdNew;
}
```

### Handling the result

```dart
onSuccess: (LivenessResult result) {
  // 1. Confidence score
  final pct = (result.confidenceScore * 100).toStringAsFixed(1);
  print('Anti-spoof confidence: $pct%');

  // 2. Face ID — new vs returning user
  if (result.faceId != null) {
    if (result.isFaceIdNew == true) {
      // First time this face is seen on this device
      print('New face registered: ${result.faceId}');
      myBackend.registerUser(faceId: result.faceId!);
    } else {
      // Recognised — same ID as before
      print('Welcome back: ${result.faceId}');
      myBackend.loginUser(faceId: result.faceId!);
    }
  }

  // 3. Session ID — send to backend for audit trail
  myBackend.logSession(
    sessionId:  result.sessionId!,
    faceId:     result.faceId,
    isNewFace:  result.isFaceIdNew,
    score:      result.confidenceScore,
    durationMs: result.sessionDurationMs,
    actions:    result.completedActions.map((a) => a.name).toList(),
  );
},
```

---

## LivenessController API

For advanced use cases where you need to drive liveness from code rather than using `FlutterFaceLiveness` widget directly:

```dart
final controller = LivenessController(
  actions:   [LivenessAction.blink, LivenessAction.turnLeft],
  config:    LivenessConfig(enableFaceId: true),
  onSuccess: (result) { ... },
  onFailed:  (reason) { ... },
);

await controller.initialize();
```

### Public getters

| Getter | Type | Description |
|--------|------|-------------|
| `isInitialized` | `bool` | True after camera + models are ready |
| `status` | `DetectionStatus` | Current detection state (see below) |
| `currentAction` | `LivenessAction?` | The action the user must perform now |
| `completedActions` | `List<LivenessAction>` | Actions already completed this session |
| `remainingActions` | `List<LivenessAction>` | Actions still to complete |
| `completedCount` | `int` | Number of completed actions |
| `totalActions` | `int` | Total actions in this session |
| `progress` | `double` | 0.0–1.0 completion progress |
| `isComplete` | `bool` | True after all actions are done |
| `sessionId` | `String?` | Current session ID |
| `currentFace` | `FaceData?` | Most recent detected face data |
| `lastQuality` | `FrameQuality?` | Most recent frame quality metrics |
| `faceIdModelDownloadProgress` | `double?` | 0.0–1.0 during model download, `null` otherwise |
| `error` | `String?` | Non-null if initialization failed |
| `cameraController` | `CameraController?` | Underlying camera controller |

### DetectionStatus values

| Status | Meaning |
|--------|---------|
| `initializing` | Camera / models loading |
| `noFace` | No face detected in frame |
| `multipleFaces` | More than one face visible |
| `faceTooFar` | Move closer to camera |
| `faceTooClose` | Move further from camera |
| `faceNotCentered` | Centre your face in the oval |
| `lowLight` | Too dark — triggered after 6 consecutive dark frames |
| `overExposed` | Too bright / direct light — same 6-frame debounce |
| `blurry` | Camera out of focus |
| `fakeDetected` | Anti-spoof or duplicate-frame check triggered |
| `actionInProgress` | Performing a liveness challenge |
| `completed` | All actions done — `onSuccess` will fire |
| `failed` | Session timed out or manually failed |

### Methods

```dart
await controller.initialize();            // start camera + load models
await controller.reset();                 // restart session, keep camera running
await controller.clearFaceIdentities();   // delete all stored face embeddings
await controller.dispose();              // release all resources
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

## Performance

| Metric | Value |
|--------|-------|
| Per-frame latency (mid-range Android) | 40–60 ms |
| Per-frame latency (iPhone 12+) | 20–35 ms |
| Frame processing rate (default) | 20 fps |
| FaceNet inference (first call after load) | ~80 ms |
| FaceNet inference (warm, subsequent) | ~30–50 ms |
| Memory footprint (base, no Face ID) | ~45 MB |
| Memory footprint (with Face ID loaded) | ~90 MB |
| FaceNet model download (one-time) | ~23 MB |

**Threading model:**

| Work | Thread |
|------|--------|
| ML Kit face detection | Main isolate (platform channel requirement) |
| YUV → NV21 + brightness/blur/hash | Background isolate (`compute()`) |
| Face crop + resize + normalise | Background isolate (`compute()`) |
| FaceNet embedding inference | Background isolate (`compute()`) |
| UI rendering | Main thread — never blocked |

**Tuning tips:**
- Lower `targetFps` to `15` on low-end devices to reduce CPU load
- Use `ResolutionPreset.medium` if 60 fps UI rendering is dropping frames
- Set `enableFaceId: false` if you don't need identity — saves ~45 MB RAM and skips all FaceNet work

---

## Security

| Threat | Mitigation |
|--------|-----------|
| Printed photo | Eye variance + face geometry signals in `AntiSpoofEngine` |
| Screen replay (looped video) | FNV-1a frame hash sliding-window in `FrameHasher` |
| Static image held to camera | Duplicate frame detection + micro-motion signal |
| Pre-recorded live video | Micro-motion: yaw/pitch variance over 12-frame rolling window |
| Deepfake / synthetic face | Optional TFLite model plug-in for ML-based PAD |
| Predictable action sequence | Fisher-Yates shuffle per session |
| Session replay attack | `sessionId` generated with `Random.secure()` — cryptographically unique |
| Identity spoofing (different person) | FaceNet cosine similarity ≥ threshold; `isFaceIdNew` signals mismatches |
| Low-quality frames | BT.601 brightness with 6-frame debounce + blur check block all liveness evaluation |

> **Note:** This package provides strong on-device liveness verification. For high-assurance KYC (banking, government), pair `sessionId` and `faceId` with a server-side signature verification step.

---

## Example App

The `example/` directory contains a full demo app showcasing every feature.

### Home screen

Four challenge presets:
- **Standard Verification** — Blink · Turn Left · Turn Right
- **Extended Challenge** — Blink · Look Up · Look Down · Smile
- **Full Challenge** — Blink · Turn Left · Turn Right · Open Mouth
- **With Face ID** — Blink · Turn Left with persistent identity

**Registered Faces card** — appears after the first Face ID scan. Shows all stored `FID-XXXX` IDs with tap-to-copy. "Clear all" resets the device's face database.

### Result screen

After each successful verification:

| Field | What it shows |
|-------|---------------|
| Confidence Score | Anti-spoof composite % |
| Completed Actions | Which actions were performed |
| Anti-Spoof | Passed / Spoof Detected |
| **Face ID card** | **"New Face Registered"** (blue, first time) or **"Face Recognised — Welcome Back!"** (green, returning) with the `FID-XXXX` — tap to copy |
| Session ID | Unique audit ID |
| Duration | Session time in seconds |

### Run it

```sh
cd example
flutter run
```

> **Testing Face ID persistence:**
> 1. Tap **"With Face ID"** → complete the check → see `FID-XXXX` with **"New Face Registered"** banner
> 2. Copy the Face ID (tap the row)
> 3. Tap **Back** → run **"With Face ID"** again
> 4. The result shows the **exact same** `FID-XXXX` with **"Face Recognised — Welcome Back!"** banner
> 5. Close the app completely → reopen → scan again → same ID still returned
>
> This is the core guarantee: **one face, one ID, forever**.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history.

**Latest — v2.0.0:**
- Persistent Face ID with `isFaceIdNew` flag (new / returning face detection)
- FaceNet TFLite auto-download with progress UI
- Isolate-based ML preprocessing (YUV, brightness, embedding)
- 7-signal anti-spoof engine
- Platform-correct BT.601 brightness (fixes iOS false "too dark")
- 6-frame brightness debounce (eliminates startup flicker)
- `Random.secure()` session IDs
- `openMouth` liveness action
- Dark / light / system theming
- Android minSdk raised to 26

---

## License

MIT — see [LICENSE](LICENSE)

---

## Author

Developed by Sanjay Sharma 
GitHub: [sanjaysharmajw/flutter_face_liveness](https://github.com/sanjaysharmajw/flutter_face_liveness)  
Issues: [github.com/sanjaysharmajw/flutter_face_liveness/issues](https://github.com/sanjaysharmajw/flutter_face_liveness/issues)
