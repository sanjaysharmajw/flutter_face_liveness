## 2.0.0

### New Features

**Persistent Face Identity (Face ID)**
- `FaceIdentityService` — assigns a stable `FID-XXXX` identifier to each unique face that persists across all app sessions using `SharedPreferences`
- `FaceEmbeddingModel` — wraps a FaceNet TFLite model (128-dim L2-normalised embeddings); model is auto-downloaded on first use (~23 MB, cached permanently)
- `FaceModelDownloader` — streaming HTTP download with progress callback; primary URL + fallback URL; re-downloads automatically if the cached file is corrupted
- `FacePreprocessor` — crops + resizes face region to 160×160, normalises pixels to `[-1, 1]`; runs in a `compute()` isolate; handles both NV21 (Android) and BGRA8888 (iOS) input
- `LivenessConfig.enableFaceId` flag (default `false`) — zero-config opt-in; no model file to bundle
- `LivenessConfig.faceIdSimilarityThreshold` (default `0.65`) — cosine-similarity cutoff for same-face matching
- `LivenessResult.faceId` — returned alongside `sessionId` on successful verification
- `LivenessController.clearFaceIdentities()` — removes all stored embeddings (e.g. on logout)
- Embedding adaptation — stored embedding is updated toward each confirmed new observation (`75% old + 25% new`, then re-normalised) so the template improves over time

**Isolate-based ML Preprocessing**
- `FrameProcessor` — YUV→NV21 conversion, brightness, blur score, and FNV-1a hash all computed in a background `compute()` isolate; UI thread stays at 60 fps

**Frame Quality Validation**
- Per-frame brightness check with debounce (6 consecutive bad frames required before reporting `lowLight`/`overExposed`, absorbing camera auto-exposure settling time)
- Platform-correct brightness calculation: iOS BGRA8888 uses BT.601 luminance (`Y = (77R + 150G + 29B) >> 8`); Android NV21 uses Y-plane directly
- Blur detection via Y-plane variance

**Anti-Spoof Engine**
- 7-signal composite scoring: eye variance, face geometry, head pose naturalness, eye-open probability, face tracking continuity, micro-motion (yaw/pitch variance), and frame quality
- Rolling 12-frame history — no model file required

**Security**
- `SessionManager` — cryptographically unique session IDs using `Random.secure()` (12-char timestamp hex + 8-char secure random hex, e.g. `LV-018F3A2B9C4E-D7E31F08`)
- `FrameHasher` — FNV-1a sliding-window replay detection
- Fisher-Yates shuffle for randomised action sequences

**New Liveness Action**
- `LivenessAction.openMouth` — detected via bounding-box height growth (>8%) with low smile probability

**UI**
- `LivenessStepIndicator` — animated progress dots for current / completed / remaining steps
- Download-progress loading screen — shows `%` while FaceNet model downloads on first run
- Dark / light theme support via `LivenessConfig.themeMode`
- `@Deprecated showDebugInfo` — replaced by `LivenessConfig.showDebugOverlay`

**New Exports**
- `FaceIdentityService`, `FaceModelDownloader`, `FaceModelDownloadException`
- `AntiSpoofEngine`, `AntiSpoofResult`, `TFLiteService`
- `SessionManager`, `RawFrameData`

### Bug Fixes

- **iOS brightness falsely reported as "too dark"** — single-plane BGRA frames were being sampled as if they were NV21 Y-plane data (Blue channel average ≠ luminance); fixed with BT.601 per-pixel luminance
- **iOS face crop height clamping** — `_resampleBgra` used `w-1` for both axes; portrait/landscape frames could produce out-of-bounds crops; fixed to `h-1` for the Y axis
- **iOS raw frame bytes mismatch** — `RawFrameData` stored NV21-converted bytes even on iOS where `FacePreprocessor` expects BGRA8888; now stores `image.planes[0].bytes` (original BGRA) on iOS
- **Same face → different Face ID** — similarity threshold `0.78` was too strict for cross-session lighting/angle variation; lowered to `0.65`; stored embedding now adapts toward each confirmed match
- **Session ID collision** — old generator used deterministic XOR of timestamp; replaced with `Random.secure()`
- **`tflite_flutter 0.10.4` compilation failure** on Dart ≥ 3.4 — `UnmodifiableUint8ListView` was removed from `dart:typed_data`; resolved by overriding to `tflite_flutter` git `main` (v0.12.1)
- **`completedActions` / `remainingActions` not defined** on `LivenessController` — fixed broken `_EngineSequence` extension; getters added directly to controller
- **`brightness > 0.90` false overexposure** — threshold raised to `0.92` to match real sensor output

### Breaking Changes

- **Android `minSdkVersion` raised from 21 → 26** — required by `tflite_flutter 0.12.1`
- `LivenessResult` gains optional `faceId` field (non-breaking; `null` when `enableFaceId` is `false`)
- `brightnessMin` default changed from `0.20` → `0.12`
- `brightnessMax` default changed from `0.90` → `0.92`

### Dependencies Added

```yaml
tflite_flutter: (git main — v0.12.1)
shared_preferences: ^2.2.2
http: ^1.2.1
path_provider: ^2.1.3
```

---

## 1.0.0

- Initial release
- Real-time face detection via Google ML Kit Face Detection
- Liveness actions: blink, turnLeft, turnRight, lookUp, lookDown, smile
- Anti-spoofing heuristic validator (5-signal composite score)
- Animated face overlay with status indicator and progress bar
- Clean architecture: Camera → ML → Liveness engine → UI layers
- Full null-safety support (Dart 3 / Flutter 3.10+)
- Android API 21+ and iOS 13+ support
- Example app with standard and custom challenge modes
