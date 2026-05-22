# flutter_face_liveness

[![pub version](https://img.shields.io/badge/pub-3.2.0-blue)](https://pub.dev/packages/flutter_face_liveness)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)]()
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-yellow)](https://buymeacoffee.com/sanjaysharmajw)

![flutter_face_liveness banner](https://raw.githubusercontent.com/sanjaysharmajw/flutter_face_liveness/main/screenshots/banner.png)

Production-ready AI-powered Flutter SDK for **real-time face liveness detection, replay attack prevention, and persistent face identity** — powered by Google ML Kit + TensorFlow Lite. All processing runs **entirely on-device** with zero server calls (except one-time model downloads).

---

## Table of Contents

- [Features](#features)
- [Replay Attack Detection](#replay-attack-detection)
- [Accessory Validation](#accessory-validation)
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
- [Lighting & Brightness](#lighting--brightness)
- [Security](#security)
- [Example App](#example-app)
- [Changelog](#changelog)

---

## Features

| Category | Feature |
|----------|---------|
| **Liveness** | 7 challenge actions — blink, turn left/right, look up/down, smile, open mouth |
| **Face Landmarks** | 10 ML Kit landmark positions per frame (`leftEyePosition`, `rightEyePosition`, `noseBasePosition`, cheeks, mouth corners, ears) |
| **Face ID** | Same face → always same ID, across sessions and restarts. Powered by FaceNet TFLite (auto-downloaded, ~23 MB) |
| **New/Returning** | `isFaceIdNew` flag — first-time or returning face |
| **Anti-Spoof** | 9-signal composite engine — eye variance, geometry, pose, micro-motion, quality, tracking, brightness variance, motion jitter |
| **8-Signal Replay Detection** | Five new pure-Dart signals (S5–S8) run alongside MiniFASNet. Final score = min of all signals — must defeat every layer simultaneously |
| **Screen Detection** | Specular highlight density + skin chromatic warmth (iOS) + temporal backlight stability |
| **Optical Flow** | 32×32 face thumbnail block-MAD: stasis detection + spatial variance for static/rigid replay |
| **Face Geometry** | 3-D depth via cos(yaw) correlation · eye-ratio consistency · landmark velocity naturalness |
| **TFLite Models** | FaceAntiSpoofing (3.9 MB) + MiniFASNet-V2 (1.7 MB) — both auto-download & run in background isolates |
| **Frame Quality** | BT.601 platform-correct brightness (NV21 + BGRA8888), blur, overexposure — 6-frame debounce |
| **Face Mesh** | MediaPipe Face Mesh (468 3-D landmarks) via `enableFaceMesh: true` — depth score exposed via `liveMeshDepthScore` |
| **Replay Guard** | FNV-1a frame hashing detects looped / static-image attacks |
| **Session Security** | Cryptographically unique session IDs via `Random.secure()` |
| **Action Randomisation** | Fisher-Yates shuffle prevents predictable replay attacks |
| **Isolate ML** | YUV→NV21 conversion, quality analysis, TFLite inference — all in background isolates |
| **Theming** | Dark / light / system mode via `LivenessConfig.themeMode` |
| **Debug Overlay** | 8 real-time signal scores + Euler angles + eye/smile probabilities |

---

## Replay Attack Detection

> **v3.1.0** introduces a full 8-signal on-device replay detection pipeline. All signals run locally — no server, no network calls during verification.

### How it works

Every frame is analysed by up to 8 independent signals. At session end, the **minimum score across all signals** is the final replay decision. An attacker must simultaneously defeat every single layer.

| # | Signal | Type | What it catches |
|---|--------|------|----------------|
| S1 | Spatial Laplacian variance | Pixel analysis | H.264 compression smooths skin micro-texture (pores, wrinkles) |
| S2 | Temporal brightness variance | History | Screen backlight is perfectly stable; real rooms fluctuate |
| S3 | Motion heterogeneity CV² | 9-region AEC-invariant | Uniform AEC gain = screen; non-uniform regional motion = real face |
| S4 | MiniFASNet-V2 TFLite | Deep learning | Learned anti-spoof features across face texture + geometry |
| S5 | ReplayAnalyzer | Multi-signal | Perceptual fingerprint (loop detection) + angular micro-jitter (stabilised video) + motion direction entropy + blink consistency |
| S6 | ScreenArtifactDetector | Pixel analysis | Specular highlights (screen glare) + skin chromatic warmth (LCD blue boost) + backlight stability |
| S7 | OpticalFlowAnalyzer | Frame differencing | Stasis (static photo) + rigid-body motion (replay on tripod) |
| S8 | FaceGeometryAnalyzer | Landmark-based | Flat surface (no 3-D depth via cos(yaw)) + no micro-tremor (landmark velocity) + eye asymmetry |

### Enable it

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  config: LivenessConfig(
    enableVideoReplayDetection: true,   // activates all 8 signals
    videoReplayThreshold: 0.50,         // score below this = rejected
  ),
  onSuccess:  (result) => print('Live: ${result.videoReplayScore}'),
  onFailed:   (reason) => print('Rejected: $reason'),
)
```

### Debug overlay (8 signals)

Enable `showDebugOverlay: true` to see all signals live during development:

```
VR-B:  45.2% ⚠       ← S2 temporal brightness variance
LAP:   312   ok       ← S1 Laplacian texture variance
HET:   0.0312 ok      ← S3 motion heterogeneity CV²
TF:    78.4% real     ← S4 MiniFASNet TFLite
RA:    82.1% ok       ← S5 ReplayAnalyzer
SCR:   91.3% ok       ← S6 ScreenArtifactDetector
FLOW:  67.8% ok       ← S7 OpticalFlowAnalyzer
GEO:   73.5% ok       ← S8 FaceGeometryAnalyzer
```

### Tuning for your target devices

Replay detection performance depends on camera sensor quality. For best results:

- **Good lighting** — low-light scenes reduce texture variance (S1) and may lower the score on genuine faces. Move to a well-lit area or lower `videoReplayThreshold` slightly.
- **Low-end devices** — older camera sensors produce noisier frames. If you see occasional false rejections, adjust `videoReplayThreshold` from `0.50` down to `0.40`–`0.45`.
- **High-security apps** — raise `videoReplayThreshold` to `0.60`+ and combine with `enableTFLite: true` for maximum protection.

```dart
// Standard (balanced)
config: LivenessConfig(
  enableVideoReplayDetection: true,
  videoReplayThreshold: 0.50,
)

// More lenient — older / low-end devices
config: LivenessConfig(
  enableVideoReplayDetection: true,
  videoReplayThreshold: 0.42,
)

// High-security
config: LivenessConfig(
  enableVideoReplayDetection: true,
  videoReplayThreshold: 0.60,
  enableTFLite: true,
)
```

---

## Use Cases

### KYC (Know Your Customer)

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.turnRight],
  config: LivenessConfig(
    enableAntiSpoof: true,
    enableFaceId: true,
    enableVideoReplayDetection: true,
    randomizeActions: true,
  ),
  onSuccess: (result) {
    final faceId    = result.faceId;        // "FID-3A9F2B1C4E8D…"
    final isNew     = result.isFaceIdNew;   // true = first time, false = returning
    final sessionId = result.sessionId;     // "LV-018F3A2B9C4E-D7E31F08"
    final score     = result.confidenceScore;
  },
  onFailed: (reason) => showError(reason),
)
```

### Banking / Fintech

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft, LivenessAction.smile],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdSimilarityThreshold: 0.72,
    enableAntiSpoof: true,
    enableVideoReplayDetection: true,
    sessionTimeoutMs: 30000,
  ),
  onSuccess: (result) {
    if (result.isFaceIdNew == false && result.faceId == storedFaceId) {
      authoriseTransaction();
    } else {
      flagForReview();
    }
  },
  onFailed: (reason) => showError(reason),
)
```

### Attendance / Access Control

```dart
FlutterFaceLiveness(
  actions: [LivenessAction.blink],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdMode: FaceIdMode.auto,
    enableAntiSpoof: true,
    enableVideoReplayDetection: true,
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

---

## Getting Started

### 1. Add the dependency

```yaml
dependencies:
  flutter_face_liveness: ^3.2.0
```

### 2. Platform permissions

**Android** — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.CAMERA" />
<!-- Required only when enableFaceId: true or enableVideoReplayDetection: true -->
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

```yaml
# pubspec.yaml
dependency_overrides:
  tflite_flutter:
    git:
      url: https://github.com/tensorflow/flutter-tflite.git
      ref: main
```

---

## Quick Start

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
    enableVideoReplayDetection: true,  // full 8-signal protection
  ),
  onSuccess: (LivenessResult result) {
    print('Session   : ${result.sessionId}');
    print('Confidence: ${(result.confidenceScore * 100).toStringAsFixed(1)}%');
    print('Replay    : ${result.videoReplayDetected ? "BLOCKED" : "PASSED"}');
  },
  onFailed: (String reason) => print('Failed: $reason'),
)
```

---

## Face Identity (Face ID)

> **Key guarantee:** A Face ID (`FID-XXXX`) is permanently tied to one physical person's face — across sessions, restarts, days, and lighting changes. Embeddings are stored **encrypted on-device** (XOR stream cipher, per-installation key).
>
> ```
> Day 1  →  FID-3A9F2B1C4E8D7F62   isFaceIdNew: true
> Day 7  →  FID-3A9F2B1C4E8D7F62   isFaceIdNew: false  ← same ID
> Day 30 →  FID-3A9F2B1C4E8D7F62   isFaceIdNew: false  ← same ID
> Different person → FID-A817C3F0B24E9D51  isFaceIdNew: true
> ```

### Operation modes (`FaceIdMode`)

| Mode | Behaviour | Use case |
|------|-----------|----------|
| `FaceIdMode.auto` *(default)* | Match existing face → return its ID. Unknown face → register and return new ID | Combined login + registration flows |
| `FaceIdMode.registrationOnly` | Register only. Rejects if face already exists (`faceAlreadyRegistered: true`) | One-time enrolment — guarantees one ID per person |
| `FaceIdMode.verificationOnly` | Match only. Unknown faces fail with `"Face not recognized"` — never registers | Pure login flows where enrolment is separate |

### Enable it

```dart
// Auto — match or register (default)
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdMode: FaceIdMode.auto,
  ),
  onSuccess: (result) {
    print(result.isFaceIdNew! ? 'Registered: ${result.faceId}' : 'Welcome back: ${result.faceId}');
    print('Match score: ${result.faceMatchScore}');
  },
  onFailed: (reason) => print('Failed: $reason'),
)

// Registration only — duplicate prevention
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdMode: FaceIdMode.registrationOnly,
  ),
  onSuccess: (result) => print('Enrolled: ${result.faceId}'),
  onFailed: (reason) => print(reason), // "Face already registered"
)

// Verification only — login flow
FlutterFaceLiveness(
  actions: [LivenessAction.blink, LivenessAction.turnLeft],
  config: LivenessConfig(
    enableFaceId: true,
    faceIdMode: FaceIdMode.verificationOnly,
  ),
  onSuccess: (result) => print('Login OK: ${result.faceId}'),
  onFailed: (reason) => print(reason), // "Face not recognized — please register first"
)
```

### Managing stored faces

```dart
await controller.clearFaceIdentities();  // delete all on logout

final service = FaceIdentityService();
await service.initialize();
List<String> ids = service.registeredFaceIds;  // all enrolled face IDs
int total = service.totalEmbeddingCount;        // total embeddings stored
await service.removeFace('FID-3A9F2B…');
await service.clearAllFaces();
service.dispose();
```

### Cosine similarity thresholds

| Threshold | Behaviour |
|-----------|-----------|
| `0.72` | Lenient |
| `0.82` | **Default** — gallery-based best-of-5 matching |
| `0.86` | Stricter — recommended for banking / high-security |

> **`registrationDuplicateThreshold`** (default `0.75`) — used only in `registrationOnly` mode. Intentionally lower than `faceIdSimilarityThreshold` so borderline cases are rejected rather than double-registered.

> **`minEmbeddingQuality`** (default `0.50`) — embeddings below this quality score (L2 norm + variance check) are discarded before averaging. Prevents degenerate low-light or motion-blur crops from polluting the gallery.

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

  // Anti-spoof (heuristic, 9 signals)
  bool   enableAntiSpoof      = true,
  double antiSpoofThreshold   = 0.45,

  // Frame quality
  bool   enableBrightnessCheck = true,
  double brightnessMin         = 0.12,
  double brightnessMax         = 0.92,
  bool   enableBlurDetection   = true,
  double blurThreshold         = 80.0,
  bool   enableDuplicateFrameDetection = true,
  int    duplicateFrameWindowSize      = 8,

  // Face geometry
  double faceTooFarRatio   = 0.015,
  double faceTooCloseRatio = 0.70,

  // Face Mesh (MediaPipe 468 landmarks)
  bool   enableFaceMesh  = false,

  // Face Identity
  bool       enableFaceId                      = false,
  FaceIdMode faceIdMode                        = FaceIdMode.auto,
  double     faceIdSimilarityThreshold         = 0.82,
  double     registrationDuplicateThreshold    = 0.75,
  double     minEmbeddingQuality               = 0.50,

  // TFLite anti-spoof (FaceAntiSpoofing, 3.9 MB — auto-download)
  bool    enableTFLite            = false,
  String? tfliteModelPath         = null,
  String? tfliteModelUrl          = null,
  int?    tfliteInputSize         = null,
  double  tfliteDeepfakeThreshold = 0.40,

  // Video replay detection — activates all 8 signals (MiniFASNet-V2, 1.7 MB — auto-download)
  bool    enableVideoReplayDetection = false,
  String? videoReplayModelPath       = null,
  String? videoReplayModelUrl        = null,
  int?    videoReplayInputSize       = null,
  double  videoReplayThreshold       = 0.50,

  // UI
  ThemeMode themeMode       = ThemeMode.dark,
  bool      showDebugOverlay = false,
})
```

### Full parameter table

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sessionTimeoutMs` | `int` | `60000` | Auto-fail after this many ms |
| `randomizeActions` | `bool` | `true` | Fisher-Yates shuffle per session |
| `cameraResolution` | `ResolutionPreset` | `high` | `medium` reduces CPU on low-end devices |
| `targetFps` | `int` | `20` | Frame processing rate (1–30 fps) |
| `enableAntiSpoof` | `bool` | `true` | 9-signal composite heuristic |
| `antiSpoofThreshold` | `double` | `0.45` | Minimum composite score to pass |
| `enableBrightnessCheck` | `bool` | `true` | Block too-dark or overexposed frames |
| `brightnessMin` | `double` | `0.12` | BT.601 luminance below this = dark. 6-frame debounce |
| `brightnessMax` | `double` | `0.92` | Luminance above this = overexposed. Same debounce |
| `enableBlurDetection` | `bool` | `true` | Block blurry frames |
| `blurThreshold` | `double` | `80.0` | Y-plane variance below this = blurry |
| `enableDuplicateFrameDetection` | `bool` | `true` | FNV-1a sliding-window exact-duplicate detection |
| `duplicateFrameWindowSize` | `int` | `8` | Sliding window size |
| `faceTooFarRatio` | `double` | `0.015` | Bbox area ratio below which = too far |
| `faceTooCloseRatio` | `double` | `0.70` | Bbox area ratio above which = too close |
| `enableFaceMesh` | `bool` | `false` | MediaPipe Face Mesh (468 3-D landmarks); exposes `liveMeshDepthScore` |
| `enableFaceId` | `bool` | `false` | Persistent face identity via FaceNet TFLite |
| `faceIdMode` | `FaceIdMode` | `auto` | `auto` · `registrationOnly` · `verificationOnly` |
| `faceIdSimilarityThreshold` | `double` | `0.82` | Cosine similarity cutoff for matching (gallery best-of-5) |
| `registrationDuplicateThreshold` | `double` | `0.75` | Duplicate block threshold for `registrationOnly` mode |
| `minEmbeddingQuality` | `double` | `0.50` | Discard embeddings below this quality score before averaging |
| `enableTFLite` | `bool` | `false` | FaceAntiSpoofing model (auto-downloads 3.9 MB, cached) |
| `tfliteModelPath` | `String?` | `null` | Override: asset key or absolute path |
| `tfliteModelUrl` | `String?` | `null` | Override: custom download URL |
| `tfliteInputSize` | `int?` | `null` | Override: null = auto (256 for bundled model) |
| `tfliteDeepfakeThreshold` | `double` | `0.40` | TFLite score below this → `deepfakeDetected: true` |
| `enableVideoReplayDetection` | `bool` | `false` | Activates all 8 signals + MiniFASNet-V2 (auto-downloads 1.7 MB) |
| `videoReplayModelPath` | `String?` | `null` | Override: local path for MiniFASNet model |
| `videoReplayModelUrl` | `String?` | `null` | Override: download URL |
| `videoReplayInputSize` | `int?` | `null` | Override: input size (default 80) |
| `videoReplayThreshold` | `double` | `0.50` | Min score below this → `videoReplayDetected: true` |
| `themeMode` | `ThemeMode` | `dark` | `ThemeMode.system` follows device |
| `showDebugOverlay` | `bool` | `false` | 8 signal scores + face metrics |

---

## Liveness Actions

| Action | Enum | How it triggers |
|--------|------|----------------|
| Blink | `LivenessAction.blink` | Both eye probabilities drop below **0.60** — fires on close, no re-open wait |
| Turn Left | `LivenessAction.turnLeft` | Yaw > +12° held for ≥ 50 ms |
| Turn Right | `LivenessAction.turnRight` | Yaw < −12° held for ≥ 50 ms |
| Look Up | `LivenessAction.lookUp` | Pitch > +12° held for ≥ 50 ms |
| Look Down | `LivenessAction.lookDown` | Pitch < −12° held for ≥ 50 ms |
| Smile | `LivenessAction.smile` | Smile probability > 0.72 |
| Open Mouth | `LivenessAction.openMouth` | Bbox height > 5% above 6-frame baseline **OR** smile probability > 0.65 (teeth visible), held 2 frames |

### Recommended combinations

```dart
// Quick (low friction)
actions: [LivenessAction.blink]

// Standard
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
  final double confidenceScore;         // 0.0–1.0 composite anti-spoof score
  final bool   isRealHuman;
  final bool   spoofDetected;
  final bool   deepfakeDetected;        // true if TFLite score < tfliteDeepfakeThreshold
  final double? tfliteScore;            // FaceAntiSpoofing real-face probability
  final double? videoReplayScore;       // MiniFASNet real-face probability (min of 8 signals)
  final bool   videoReplayDetected;     // true when videoReplayScore < videoReplayThreshold
  final String? failureReason;
  final int?   sessionDurationMs;
  final String? sessionId;              // "LV-{12-char-hex}-{8-char-hex}"

  // Face Identity — non-null when enableFaceId: true
  final String? faceId;                 // "FID-{24-char-hex}"
  final bool?   isFaceIdNew;            // true = first-time, false = recognised
  final bool?   faceAlreadyRegistered;  // true when registrationOnly + face already exists
  final double? faceMatchScore;         // cosine similarity from gallery search (0.0–1.0)
}
```

---

## LivenessController API

```dart
final controller = LivenessController(
  actions:   [LivenessAction.blink, LivenessAction.turnLeft],
  config:    LivenessConfig(enableFaceId: true, enableVideoReplayDetection: true),
  onSuccess: (result) { ... },
  onFailed:  (reason) { ... },
);
await controller.initialize();
```

### Public getters

| Getter | Type | Description |
|--------|------|-------------|
| `isInitialized` | `bool` | True after camera + models ready |
| `isComplete` | `bool` | True when all liveness actions finished |
| `status` | `DetectionStatus` | Current detection state |
| `currentAction` | `LivenessAction?` | Action user must perform now |
| `completedActions` | `List<LivenessAction>` | Completed this session |
| `remainingActions` | `List<LivenessAction>` | Still to complete |
| `completedCount` | `int` | Number of completed actions |
| `progress` | `double` | 0.0–1.0 completion fraction |
| `sessionId` | `String?` | Current session ID (`LV-…`) |
| `currentFace` | `FaceData?` | Latest detected face (includes landmark positions) |
| `lastQuality` | `FrameQuality?` | Latest frame quality |
| `tfliteWarning` | `String?` | Non-null if TFLite model failed to load or inference errored |
| `tfliteModelDownloadProgress` | `double?` | 0.0–1.0 while TFLite model is downloading |
| `faceIdModelDownloadProgress` | `double?` | 0.0–1.0 while FaceNet model is downloading |
| `lastTfliteScore` | `double?` | Latest FaceAntiSpoofing real-face probability |
| `lastVideoReplayScore` | `double?` | Latest MiniFASNet raw real-face score |
| `liveHeuristicScore` | `double?` | S2 rolling brightness-variance score |
| `liveLaplacianScore` | `double?` | S1 rolling Laplacian texture variance |
| `liveHetScore` | `double?` | S3 motion heterogeneity CV² |
| `liveReplayScore` | `double?` | S5 ReplayAnalyzer rolling score |
| `liveScreenScore` | `double?` | S6 ScreenArtifactDetector rolling score |
| `liveFlowScore` | `double?` | S7 OpticalFlowAnalyzer rolling score |
| `liveGeoScore` | `double?` | S8 FaceGeometryAnalyzer rolling score |
| `liveMeshDepthScore` | `double?` | Face Mesh 3-D depth score (non-null when `enableFaceMesh: true`) |
| `error` | `String?` | Non-null if initialization failed |
| `cameraController` | `CameraController?` | Underlying camera controller |

### DetectionStatus values

| Status | Meaning |
|--------|---------|
| `initializing` | Camera / models loading |
| `noFace` | No face detected |
| `multipleFaces` | More than one face visible |
| `faceTooFar` | Move closer |
| `faceTooClose` | Move back |
| `faceNotCentered` | Centre face in oval |
| `lowLight` | Too dark (6-frame debounce) |
| `overExposed` | Too bright (6-frame debounce) |
| `blurry` | Out of focus |
| `fakeDetected` | Spoof / duplicate-frame triggered |
| `ready` | Face detected and centred — waiting for action to begin |
| `actionInProgress` | Performing challenge |
| `completed` | All actions done |
| `failed` | Timed out or manually failed |

### Methods

```dart
await controller.initialize();
await controller.reset();
await controller.clearFaceIdentities();
await controller.dispose();
```

---

## TFLite Integration (Optional)

Both models auto-download on first use, run in **background isolates**, and are cached permanently.

### FaceAntiSpoofing (3.9 MB)

```dart
config: LivenessConfig(
  enableTFLite: true,
  tfliteDeepfakeThreshold: 0.40,
)
```

### MiniFASNet-V2 Video Replay (1.7 MB)

Enables the full 8-signal replay detection pipeline.

```dart
config: LivenessConfig(
  enableVideoReplayDetection: true,
  videoReplayThreshold: 0.50,
)
```

```dart
onSuccess: (result) {
  print('Replay score : ${result.videoReplayScore}');    // min of 8 signals
  print('Replay attack: ${result.videoReplayDetected}'); // true = rejected
},
onFailed: (reason) => print('Rejected: $reason'),
// e.g. "Video replay attack detected (23.4% real)"
```

### Custom model

```dart
config: LivenessConfig(
  enableTFLite: true,
  tfliteModelUrl:  'https://your-cdn.com/custom_model.tflite',
  tfliteInputSize: 128,
),
```

---

## Architecture

```
Camera stream (20 fps)
    │
    ├─ FrameProcessor (background isolate)
    │     YUV→NV21  ·  brightness  ·  blur  ·  FNV-1a hash
    │
    ├─ ML Kit FaceDetector (main isolate, platform channel)
    │     Euler angles  ·  eye probabilities  ·  10 landmarks
    │
    ├─ Per-frame signals (main isolate, pure Dart)
    │     S1  Laplacian variance       (face crop texture)
    │     S2  Brightness variance      (AEC-sensitive)
    │     S3  Motion heterogeneity     (9-region CV², AEC-invariant)
    │     S5  ReplayAnalyzer           (fingerprint + jitter + entropy + blink)
    │     S6  ScreenArtifactDetector   (specular + warmth + stability)
    │     S7  OpticalFlowAnalyzer      (32×32 block-MAD)
    │     S8  FaceGeometryAnalyzer     (landmarks + depth + velocity)
    │
    ├─ TFLite inference (persistent background isolates)
    │     S4  MiniFASNet-V2            (video replay model)
    │         FaceAntiSpoofing         (deepfake model)
    │
    ├─ LivenessEngine
    │     Active challenge tracking  ·  action detection  ·  timeout
    │
    └─ LivenessController (ChangeNotifier)
          Combine all signals  ·  build LivenessResult  ·  fire callbacks
```

**Threading model:**

| Work | Thread |
|------|--------|
| ML Kit face detection | Main isolate (platform channel) |
| YUV → NV21 + quality | Background isolate (`compute()`) |
| S1–S3, S5–S8 pixel analysis | Main isolate (pure Dart, < 2 ms/frame) |
| S4 TFLite inference | Persistent background isolate (zero-copy transfer) |
| FaceNet embedding | Background isolate (`compute()`) |
| UI rendering | Main thread — never blocked |

---

## Performance

| Metric | Value |
|--------|-------|
| Per-frame latency — mid-range Android | 40–65 ms |
| Per-frame latency — iPhone 12+ | 20–40 ms |
| S5–S8 signal computation (pure Dart) | < 2 ms/frame |
| OpticalFlow 32×32 block-MAD | ~0.5 ms/frame |
| FaceNet inference (warm) | 30–50 ms |
| Memory — base | ~45 MB |
| Memory — with Face ID | ~90 MB |

**Tuning tips:**
- Lower `targetFps` to `15` on low-end devices
- Use `ResolutionPreset.medium` for 60 fps UI on older phones
- Set `enableFaceId: false` if you don't need identity — saves ~45 MB RAM

---

## Lighting & Brightness

The SDK checks frame brightness on every camera frame using BT.601 platform-correct luminance (NV21 Y-plane on Android, weighted RGB on iOS). Poor lighting is one of the most common causes of slow or failed detection.

### How it works

| Condition | Status triggered | Threshold |
|-----------|-----------------|-----------|
| Too dark | `DetectionStatus.lowLight` | Luminance < `brightnessMin` (default `0.12`) |
| Too bright / overexposed | `DetectionStatus.overExposed` | Luminance > `brightnessMax` (default `0.92`) |

Both statuses use a **6-frame debounce** — the camera must report bad brightness for 6 consecutive frames before the status changes. This absorbs auto-exposure settling time when the user first points the camera.

### What gets affected

**ML Kit face detection**
- Blink, turn, and smile detection all rely on accurate landmark positions. In very low light, ML Kit's keypoints become noisy or disappear entirely — actions may not register.

**Face ID embeddings**
- Low-light or overexposed crops produce face embeddings with degenerate L2 norm or near-zero variance. These are automatically discarded by the `minEmbeddingQuality` filter (`0.50` default). If all collected frames are rejected, face matching cannot complete.

**Anti-spoof score**
- The `AntiSpoofEngine` includes brightness variance as one of its 9 heuristic signals. Extremely low or high brightness reduces the composite `confidenceScore`, which may push it below `antiSpoofThreshold` and fail the session.

**Video replay detection (S1, S2)**
- S1 (Laplacian texture variance) drops in low light — skin micro-texture is lost in noise. This can lower the replay score on genuine faces.
- S2 (temporal brightness variance) expects subtle room-light fluctuation. Pitch-black or blown-out environments produce flat variance scores.

### Best lighting conditions

- Soft indoor ceiling light or natural daylight **facing the user** (not behind them)
- Avoid strong backlighting (window behind the user) — causes face underexposure
- Avoid direct sunlight into the camera — causes overexposure
- Minimum ~100 lux equivalent; standard office lighting is ideal

### Tuning

```dart
config: LivenessConfig(
  enableBrightnessCheck: true,   // default — always keep enabled
  brightnessMin: 0.10,           // lower if users are in dimmer environments
  brightnessMax: 0.95,           // raise if outdoor users hit false overexposure
)

// Disable entirely only for controlled kiosk setups with fixed lighting:
config: LivenessConfig(
  enableBrightnessCheck: false,
)
```

---

## Security

| Threat | Mitigation |
|--------|-----------|
| Printed photo | Eye variance + geometry (AntiSpoofEngine) · Laplacian variance (S1) · Stasis detection (S7) · Flat-surface depth check (S8) |
| Static image held to camera | FNV-1a duplicate-frame detection · Stasis (S7) · Landmark velocity (S8) |
| Pre-recorded video replay | MiniFASNet-V2 (S4) · Perceptual fingerprint (S5) · Temporal stability (S6) · Rigid-motion flow (S7) |
| Mobile/tablet screen replay | Specular highlights (S6) · Skin warmth (S6, iOS) · Screen backlight stability (S2, S6) · Angular micro-jitter (S5) |
| Stabilised/compressed video | Laplacian variance (S1) · Motion jitter (S5) · Optical flow variance (S7) |
| Deepfake / synthetic face | FaceAntiSpoofing TFLite (`enableTFLite: true`) |
| Looped video | FNV-1a frame hash · Perceptual fingerprint (S5) |
| Predictable action sequence | Fisher-Yates shuffle per session |
| Session replay | `sessionId` via `Random.secure()` |
| Identity spoofing | FaceNet cosine similarity + `isFaceIdNew` flag |

> For high-assurance KYC (banking, government), pair `sessionId` and `faceId` with a server-side signature step.

---

## Example App

```sh
cd example
flutter run
```

Six challenge presets: Standard · Extended · Full · Face ID Auto · Register Face · Verify Face.

**Testing replay detection:**
1. Enable `showDebugOverlay: true` in the example config
2. Run the check normally — all 8 signal bars should be green (`ok`)
3. Play a recording of yourself on another device and point the camera at it — signals S1, S5, S6, S7 should drop below threshold and flag the session

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for full release history.

Latest: **v3.2.0** — Accessory validation, faster action detection, camera initialization race condition fix, replay attack tuning guidance.

---

## License

MIT — see [LICENSE](LICENSE)

---

## Author

Developed by Sanjay Sharma  
GitHub: [sanjaysharmajw/flutter_face_liveness](https://github.com/sanjaysharmajw/flutter_face_liveness)  
Issues: [github.com/sanjaysharmajw/flutter_face_liveness/issues](https://github.com/sanjaysharmajw/flutter_face_liveness/issues)

---

## Support

If this package saved you time, consider buying me a coffee ☕

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-yellow?style=for-the-badge&logo=buy-me-a-coffee&logoColor=white)](https://buymeacoffee.com/sanjaysharmajw)
