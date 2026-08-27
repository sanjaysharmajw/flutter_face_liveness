## 3.6.0

### New Features

- **SCRFD-2.5G-KPS detection backend for face identity** — `FaceDetectorBackend` gains a third value, `scrfd`, alongside `mlkit` (default) and `yolov8`. Uses InsightFace's SCRFD-2.5G-KPS (anchor-based, FCOS-style distance regression, 3 detection heads at strides 8/16/32) instead of ML Kit's own landmarks for the face box + eye keypoints fed into `FaceEmbeddingModel` — generally more accurate than YOLOv8n-face at small/angled faces, similar extra per-frame inference cost. Liveness actions (blink/smile/head-pose) always use ML Kit regardless of this setting, unchanged from the `yolov8` backend's behavior. Configured via `LivenessConfig.faceDetectorBackend`, `scrfdModelUrl`, `scrfdConfidenceThreshold`, `scrfdIouThreshold`.
  - `ScrfdFaceDetectorService` / `ScrfdFaceDetection` — same isolate-worker architecture as `YoloFaceDetectorService` (inference never blocks the caller's isolate). Decode differs from YOLO's single unified output tensor: SCRFD emits 9 raw tensors (`score`/`bbox`/`kps` × 3 strides), auto-classified at load time by channel count (1/4/10) and anchor count — never hardcoded by tensor index — then decoded with SCRFD's own `distance2bbox`/`distance2kps` math (no `+0.5` cell-center offset, distances pre-multiplied by stride) and greedy NMS. Preprocessing also differs from YOLO: top-left-aligned zero-padded resize (not centered letterboxing) and `(pixel - 127.5) / 128.0` normalization (not `pixel / 255`), matching InsightFace's own reference preprocessing exactly.
  - `ScrfdModelDownloader` — same cache-on-first-use pattern as `YoloModelDownloader`/`FaceModelDownloader`.
  - `ScrfdModelDownloader.bundledModelUrl` points to a hosted `scrfd_2.5g_bnkps_float32.tflite` release asset, converted from the verified official InsightFace ONNX export (a third-party GitHub-LFS mirror was used as the source — InsightFace's own release bundles only ship the 500M variant, not 2.5G — verified by parsing the ONNX graph's input/output tensor names and shapes before conversion) via `onnx2tf`. Works out of the box, no setup required. Override `LivenessConfig.scrfdModelUrl` only if you want to swap in a custom model.
  - The `LivenessController._processFrame()` fire-and-forget dispatch (unawaited, guarded by a busy flag so a slow model never throttles camera-frame delivery — see the 3.5.0 blink-detection fix below) is now backend-generic: a small internal `_IdentityFaceBox` adapter normalises either detector's output before the shared frontal-frame-tracking/embedding code runs, so `scrfd` gets the same non-blocking guarantee as `yolov8` with no separate bug class to reintroduce.

- **Example app: SCRFD backend option** — the existing ML Kit/YOLOv8 toggle is now a 3-way segmented selector (ML Kit / YOLOv8 / SCRFD) so all three can be compared live, applied to every Face ID preset.

- **Live confirmation that `yolov8`/`scrfd` are actually detecting** — `YOLOv8n-face`/`SCRFD-2.5G-KPS` results never reach the on-screen face-tracking oval (that always reflects ML Kit, which drives liveness actions regardless of backend), so there was previously no visible proof either backend was running at all. `LivenessController` gains `isSecondaryDetectorActive`, `secondaryDetectorRunCount`, and `lastSecondaryDetectionCount`; `FlutterFaceLiveness` shows a small badge (top-right, only when a secondary backend is active) reading e.g. "SCRFD-2.5G-KPS · face detected (4x)" that updates live as the backend runs.
- **Example app: clarified that the backend selector only affects Face ID presets** — the YOLOv8/SCRFD subtitle text was easy to miss; toggling the backend and then launching Standard/Extended/TFLite (none of which set `enableFaceId: true`) looked like the backend had no effect, since it genuinely doesn't apply there. Subtitles now say so explicitly, pointing at Register/Verify Face as the presets to test with.

### Bug Fixes

- **`FlutterFaceLiveness`'s loading screen showed no download progress for the `yolov8`/`scrfd` backends** — `_loadingView()` only read `tfliteModelDownloadProgress`/`faceIdModelDownloadProgress`; the YOLOv8n-face/SCRFD-2.5G-KPS model downloads (which, like every other model, complete before the camera opens — see `LivenessController.initialize()`) ran with no visible percentage, just a spinner and "Starting camera…", making a multi-second first-time download look stuck. Now shows a labelled progress bar for whichever model is currently downloading (Anti-Spoof / Face ID / YOLOv8n-face / SCRFD-2.5G-KPS), same as the existing models.
- **`coordinatesInSensorSpace` could be set incorrectly when a YOLOv8 detection had a box but no confident eye keypoints** — `_onEngineComplete()` fell back to ML Kit's own eye landmarks (rotated display-space) in that case but still tagged the coordinates as sensor-space (since a detection object was present), skipping the un-rotation ML Kit's coordinates need — silently cropping the wrong region for the identity embedding. Fixed by deriving the flag from which source actually supplies the coordinates that get used, not merely whether a detection exists. (SCRFD is unaffected — its `hasEyes` is always true.)
- **`FaceCaptureService.initialize()` had no error isolation for YOLOv8/SCRFD model loads** — unlike `LivenessController`, a failed download/load threw an uncaught exception instead of the documented silent fallback, and a subsequent `captureAndIdentify()` call with a `null` detector reported the misleading `'No face detected'` instead of the real cause. Both fixed: `initialize()` now catches load failures per-backend, and `captureAndIdentify()` reports a clear `'... detector unavailable — model failed to load or download'` rejection when relevant.
- **`enableBestFrontalCapture`'s JPEG was rotated 180° off from correct on the common Android `sensorOrientation` values (90/270)** — `frame_encoder.dart` rotated raw sensor pixels by `sensorOrientation` directly, but that value's 90°/270° cases need to be swapped relative to `copyRotate`'s angle — verified by deriving the correct transform as the algebraic inverse of this codebase's own already-tested `FacePreprocessor._landmarkToSensor`, composed with the `image` package's actual per-angle pixel mapping.
- **`faceDetectorBackend: yolov8`/`scrfd` dispatched an inference request on every qualifying camera frame (~20-30fps), not just identity-eligible candidate frames (~7-15 per session)** — a regression introduced while generalizing the fire-and-forget dispatch for the `scrfd` backend: the detector's async call was constructed (which, being an async function, starts executing — sending the isolate request — immediately, before its first `await`) *before* the candidacy/busy-flag guard was checked, rather than inside it. Fixed by moving construction back inside the guard, restoring the original throttling.
- **`ScrfdFaceDetectorService` collapsed all 9 output tensors' batch-dimension detection into one shared flag, keeping only the last tensor's value** — harmless for the bundled model (all 9 tensors are `[1,N,C]`), but a custom SCRFD export (explicitly supported via `scrfdModelUrl`) with a mix of batched/unbatched output tensors would silently corrupt decoding for whichever tensors didn't match the last one's shape. Fixed by tracking each output tensor's batch-dim-ness independently and applying the correct one per score/bbox/kps buffer.
- **The frame that completed the last liveness action could be silently excluded from frontal-frame identity bookkeeping** — a side effect of the 3.5.0 blink-latency fix, which moved `_engine.processFrame()` before the frontal-frame-tracking code. When that same frame finished the session, engine completion (which runs `_onEngineComplete()` synchronously up to its first `await`) could snapshot `_frontalFrames`/`_bestFrontalFrame` before this frame got a chance to update them. Fixed by reordering the frontal-frame-tracking block (which never itself awaits) ahead of the engine call — closes the race for the default `mlkit` backend entirely, without reintroducing the original blink-latency issue.

## 3.5.0

### New Features

- **Example app: `faceDetectorBackend` toggle** — `LivenessConfig.faceDetectorBackend` (ML Kit / YOLOv8n-face) was previously only settable in code with no example-app UI, so it always silently used the `mlkit` default. Added a home-screen toggle (alongside the existing performance-mode toggle) so both backends can be compared live, applied to every Face ID preset.

- **Example app: "Verify Face — Head Turn Only" preset** — demonstrates that `LivenessConfig.actions` fully controls the challenge set with zero SDK changes required: `FaceIdMode.verificationOnly` using only `[LivenessAction.turnLeft, LivenessAction.turnRight]`, no blink. A reminder that trimming which actions are *required* is an app-level config choice — see [Liveness Actions](#liveness-actions) — as opposed to removing detector code from the SDK itself, which would also weaken the anti-spoof/replay-detection signals that read eye/smile data independently of the requested action list (`AntiSpoofEngine`, `ReplayAnalyzer`, `FaceGeometryAnalyzer`).

### Bug Fixes

- **Blink/turn/smile actions slow or not registering with `faceDetectorBackend: yolov8`** — two compounding issues, both in `_processFrame()`:
  1. `_engine.processFrame()` (the actual blink/turn/smile detection) ran *after* `await`ing YOLO detection for identity-eligible frames, instead of immediately after ML Kit detection. Fixed by moving it up, before any `await` in the rest of the function.
  2. Even after (1), YOLO detection was still `await`ed inline — and `CameraService` holds its `_isProcessingFrame` guard for the *entire* `_processFrame()` call, so the next camera frame couldn't be accepted until YOLO's round-trip finished. This throttled overall frame throughput to YOLO's inference rate, which is still too slow to catch fast transitions like an eye-closed→open blink even though each individual frame's action detection was no longer delayed. Fixed by making YOLO detection fire-and-forget (`unawaited`, guarded by a new `_isYoloRunning` flag — same pattern already used for the TFLite/video-replay models), with the best-frontal/frontal-frame-collection bookkeeping moved into a `_recordFrontalFrame()` helper called either synchronously (ML Kit backend) or from YOLO's `.then()` callback once it resolves. Camera frame delivery, and therefore liveness-action detection, is no longer coupled to YOLO's latency at all.

### Dependencies

- **Widened outdated constraints** flagged by pub.dev's dependency-freshness check: `google_mlkit_face_detection` `^0.13.2` → `^0.14.0`, `google_mlkit_face_mesh_detection` `^0.4.2` → `^0.5.0`. No breaking API usage found in this codebase after the upgrade — `flutter analyze` clean on both the package and example app.
  - Capped at these versions deliberately, not the latest (`0.15.1`/`0.6.1`): those require Dart SDK `^3.12.0`, which broke resolution for anyone on an older Flutter/Dart install (reported: Dart 3.10.4). `0.14.0`/`0.5.0` need only `>=3.8.0 <4.0.0`, matching this package's own broad `sdk: ">=3.0.0 <4.0.0"` declaration. Revisit once `^3.12.0` is a safe minimum to require.
  - **`permission_handler` deliberately left at `^12.0.1`** (not bumped to `^13.0.1`): the newer version pulls in `permission_handler_android 14.0.0`, whose `build.gradle.kts` uses a Kotlin Gradle Plugin 2.0+-only DSL (`compilerOptions { jvmTarget = ... }`) that failed to compile against this project's configured Kotlin toolchain (reported: `Unresolved reference: compilerOptions`). Revisit once the project's Kotlin/AGP versions are updated to match.

## 3.4.0

### New Features

- **`LivenessConfig.faceDetectorPerformanceMode`** — ML Kit precision/speed trade-off is now configurable (was hardcoded). Default switched from `FaceDetectorMode.fast` to `.accurate`, which improves face tracking through moderate off-angle head positions (turn-left/right, look-up/down), where `.fast` was more prone to losing the face mid-turn before an action registered — set it back to `.fast` for lower per-frame latency if your target devices need it. Trade-off not yet re-benchmarked (see README Performance table). Does not extend ML Kit's fundamental angle ceiling; very steep/near-profile angles can still lose tracking either way. `FaceDetectorMode` is now exported from the package. Demoed in the example app via a new toggle on the home screen.

- **`LivenessConfig.enableBestFrontalCapture`** — automatically captures the most-frontal frame seen during a session (by `|yaw|+|pitch|`) and exposes it as `LivenessResult.bestFrontalImageBytes` (upright JPEG) on success, for apps that want a human-viewable photo of the user alongside the liveness/identity result (e.g. a KYC review screen) without a separate capture step. Independent of `enableFaceId` — shares the same internal frame-tracking at no extra cost when both are on, but works standalone. JPEG quality configurable via `bestFrontalJpegQuality` (default `85`).
  - `encodeFrameToJpeg()` (`lib/src/ml/frame_encoder.dart`) — converts the raw NV21/BGRA frame to an upright JPEG (rotation-corrected via `LivenessConfig`'s existing sensor-orientation handling), reusing `FacePreprocessor.yuv2rgbNv21` rather than a third copy of the YUV conversion. Runs on a background isolate (`Isolate.run`) so a full-resolution encode never blocks the UI thread.

### Bug Fixes

- **Swift Package Manager build failure** — `ios/flutter_face_liveness/Package.swift` exported its library product as `flutter_face_liveness` (underscore). Flutter's auto-generated `FlutterGeneratedPluginSwiftPackage` requires plugin product names to be hyphenated (`flutter-face-liveness`) per the [Flutter SPM naming convention](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers), so any app built with `flutter config --enable-swift-package-manager` failed with `product 'flutter-face-liveness' ... not found`. Fixed by renaming the library product (target name unchanged).

- **`ConcurrentModificationError` on `_frontalFrames` in release builds** — when `enableFaceId: true`, `_onEngineComplete()` iterates `_frontalFrames` with a `for` loop that awaits per-frame embedding computation. Because `_processFrame()` had no guard against the engine already being complete, a camera frame arriving during that async window could still append to the same list mid-iteration, throwing `Concurrent modification during iteration`. Fixed by (1) short-circuiting `_processFrame()` once `_engine.isComplete` is true, and (2) iterating a `List.of(_frontalFrames)` snapshot as defense in depth.

## 3.3.0

### New Features

- **YOLOv8n-face detection backend for face identity** — `FaceDetectorBackend` (`mlkit` default, `yolov8`) lets the identity/embedding pipeline use a YOLOv8n-face TFLite model instead of ML Kit's own landmarks for the face box + eye keypoints fed into `FaceEmbeddingModel`. Liveness actions (blink/smile/head-pose) always use ML Kit regardless of this setting, since only ML Kit exposes that classification output. Configured via `LivenessConfig.faceDetectorBackend`, `yoloModelUrl`, `yoloConfidenceThreshold`, `yoloIouThreshold`.
  - `YoloFaceDetectorService` / `YoloFaceDetection` — TFLite inference + letterbox preprocessing + NMS decode (standard Ultralytics raw pose-export layout: box + confidence + 5 keypoints).
  - `YoloModelDownloader` — same cache-on-first-use pattern as `FaceModelDownloader`/`TFLiteModelDownloader`.
  - `YoloModelDownloader.bundledModelUrl` already points to a hosted `yolov8n-face.tflite` release asset — works out of the box, no setup required. Override `LivenessConfig.yoloModelUrl` only if you want to swap in a custom model.

- **`FaceCaptureService`** — enrollment/verification from a single captured photo (as opposed to a full live liveness session): decode → detect (either backend) → pre-capture quality gate (brightness/blur/face-size, distinct from `FaceIdentityService`'s post-hoc embedding-quality check) → eye-aligned crop → embed → match/register, reusing `FaceIdentityService`'s gallery so a person registered via live session or via photo capture is the same lookup. Returns `FaceCaptureResult` (either a `FaceMatchResult` or a pre-match rejection reason).
  - `FaceEmbeddingModel`/`FacePreprocessor` gained a static-RGB entry point (`FacePreprocessor.prepareFromRgb`, `FaceIdentityService.computeEmbeddingFromRgb`) so the same loaded model/gallery serve both the live-frame and captured-photo paths — no duplicate model instance.

- **`image` package** now a direct dependency (decoding captured photos for `FaceCaptureService`).

## 3.2.0

### New Features

- **Face ID operation modes (`FaceIdMode`)** — three distinct modes replace the previous single-threshold matching:
  - `FaceIdMode.auto` *(default)* — match existing face or register new one
  - `FaceIdMode.registrationOnly` — enrolment-only; rejects duplicate registrations with `onFailed("Face already registered")`. Use for one-time sign-up flows that guarantee one ID per person
  - `FaceIdMode.verificationOnly` — login-only; never registers unknown faces; fails with `onFailed("Face not recognized — please register first")`
  - Configured via `LivenessConfig.faceIdMode`

- **`FaceMatchResult` / `FaceMatchOutcome`** — rich result types returned by `FaceIdentityService.identifyFromEmbeddings()`:
  - `FaceMatchOutcome` enum: `matched`, `registered`, `alreadyExists`, `notFound`
  - `FaceMatchResult` fields: `outcome`, `faceId`, `similarity`, `qualityScore`

- **`LivenessResult` new fields**:
  - `faceAlreadyRegistered` (`bool?`) — `true` when `registrationOnly` mode detects a duplicate face
  - `faceMatchScore` (`double?`) — cosine similarity returned from gallery search; useful for UI feedback

- **`LivenessConfig` new fields**:
  - `faceIdMode` (`FaceIdMode`, default `FaceIdMode.auto`)
  - `registrationDuplicateThreshold` (`double`, default `0.75`) — duplicate block threshold for `registrationOnly`; intentionally lower than `faceIdSimilarityThreshold` to reject borderline cases
  - `minEmbeddingQuality` (`double`, default `0.50`) — discard degenerate embeddings (bad L2 norm, near-zero variance) before averaging

- **Encrypted embedding storage (v4)** — face embeddings are now stored as XOR-encrypted Float32 bytes (base64-encoded) using a 64-byte per-installation key generated with `Random.secure()` on first run. Key stored in `SharedPreferences`; gallery stored under key `ffl_known_faces_v4`. Previous unencrypted galleries (v1–v3) are automatically invalidated on first launch.

- **Accessory Validation** — `LivenessConfig.enableAccessoryValidation` (default `false`). When enabled, verification is blocked if the user is wearing sunglasses/goggles or a cap/hat, with a clear suggestion message shown in the status badge. Detection is purely heuristic — no extra model required:
  - `wearingSunglasses` — both eye-open probabilities < 0.25 for 6+ consecutive frames
  - `wearingCap` — forehead gap above eye landmarks < 12% of face bounding-box height for 6+ frames
  - Two new `DetectionStatus` values: `wearingSunglasses`, `wearingCap`
  - `StatusIndicatorWidget` updated: amber `"REMOVE GLASSES"` / `"REMOVE CAP"` badges
  - Blink action guard: sunglasses check is automatically skipped during blink challenge to prevent false positives from intentional eye closure

### Improvements

- **Gallery-based face matching (best-of-5)** — `FaceIdentityService` now stores up to 5 embeddings per face ID (rolling window, oldest dropped first). Matching uses the **maximum cosine similarity across all stored embeddings** for a face. This handles within-class variance (lighting, pose, expression) across sessions and significantly reduces false "new face" registrations.

- **Eye-landmark filtered frame collection** — frontal frames are now only collected when both `leftEyePosition` and `rightEyePosition` landmarks are detected. This ensures all embeddings in the averaging pool are eye-aligned. The fallback (bounding-box-only crop) is still used when no frontal frames are available.

- **Embedding quality filter** — embeddings with quality score below `minEmbeddingQuality` are discarded before averaging. Quality is scored 0.0–1.0 based on: L2 norm deviation from 1.0 (weight 0.60) + embedding variance (weight 0.40). Degenerate embeddings (all-zero, constant vector, out-of-range norm) score 0.0 and are always discarded.

- **`faceIdSimilarityThreshold` default raised from `0.65` → `0.82`** — recalibrated for gallery-based best-of-5 matching. The higher threshold is reliable now that multiple aligned embeddings are averaged per session.

- **`FaceIdentityService` constructor exposes all config** — `similarityThreshold`, `registrationDuplicateThreshold`, `minEmbeddingQuality`, `mode`, `maxEmbeddingsPerFace` are all constructor parameters.

- **Faster action detection on low-end devices** — detection thresholds recalibrated based on real ML Kit output ranges across device tiers:

  | Action | Old threshold | New threshold | Reason |
  |--------|--------------|---------------|--------|
  | Blink (closed) | `0.50` | `0.60` | Slow-camera devices report 0.55–0.60 for closed eyes |
  | Blink (open guard) | `0.65` | `0.65` | Kept — maintains 0.05 hysteresis gap above closed threshold |
  | Turn Left / Right | `±15°` | `±12°` | Cheap Android devices cap ML Kit yaw output at ~12–13° |
  | Look Up / Down | `±15°` | `±12°` | Same sensor limitation |
  | Hold duration | `80 ms` | `50 ms` | 1 frame at 20 fps is sufficient; 80 ms was 1.6 frames |
  | Inter-action debounce | `800 ms` | `600 ms` | Reduces dead zone between consecutive actions |
  | Smile | `> 0.80` | `> 0.72` | Natural smiles rarely reach 0.80 on ML Kit |

### Bug Fixes

- **Face preprocessor inverse similarity transform (`cos(-srcAngle)` → `cos(srcAngle)`)** — `FacePreprocessor._alignedCrop()` used `math.cos(-srcAngle)` and `math.sin(-srcAngle)` for the inverse transform. For a tilted face (e.g. `srcAngle = -0.245 rad`), this mapped the output left-eye pixel to the wrong source y-coordinate (~70 px instead of ~90 px), producing misaligned crops and inconsistent embeddings across sessions. The correct inverse of the forward `R(-srcAngle)` rotation is `R(+srcAngle)`. Fixed by removing the negation.

- **`verificationOnly` mode silently passed as success when face not found** — when `FaceIdMode.verificationOnly` found no matching face (`FaceMatchOutcome.notFound`), the controller printed a debug log but did not fail the session. If all liveness actions were completed, `onSuccess` was called with `isSuccess: true` and `faceId: null`. Fixed: `match.isNotFound` now immediately calls `onFailed('Face not recognized — please register first')` and returns, matching the `faceAlreadyRegistered` pattern.

- **Camera never starts after model download (race condition)** — `LivenessController.initialize()` ran model downloads as a fire-and-forget coroutine. If the widget was disposed while a download was in progress, `_isDisposed` was set to `true` but `initialize()` continued and opened the camera anyway. `_processFrame()` then silently dropped all frames. Fixed by adding `if (_isDisposed) return` guards after each major `await` in the initialization chain — after each model download, after FaceID model load, and critically before `_cameraService.initialize()`.

- **Blink false positives (hysteresis gap removed)** — `_openThreshold` was mistakenly lowered to equal `_closedThreshold` (both `0.60`), eliminating the hysteresis gap. Users with naturally droopy eyelids (~0.60 probability) would oscillate rapidly between "closed" and "open" states, triggering false blinks. Fixed by keeping `_openThreshold = 0.65`, maintaining a 0.05 gap above `_closedThreshold`.

- **`AccessoryValidator` not reset on session retry** — `LivenessEngine.reset()` did not call `_accessoryValidator.reset()`, causing `_sunglassesCount` and `_capCount` to carry over into a new session after a retry. Fixed by adding `_accessoryValidator.reset()` to `LivenessEngine.reset()`.

---

## 3.1.0

### New Features

- **8-signal on-device replay detection** — five new pure-Dart pixel-level signals run every frame alongside MiniFASNet. Final score = **minimum** of all available signals, so an attacker must simultaneously defeat every layer:

  | Signal | File | What it catches |
  |--------|------|----------------|
  | S5 – ReplayAnalyzer | `analysis/replay_analyzer.dart` | Looped video (perceptual fingerprint), stabilised video (angular micro-jitter), periodic replay (motion entropy), frozen replay (blink consistency) |
  | S6 – ScreenArtifactDetector | `analysis/screen_artifact_detector.dart` | LCD/OLED glare (specular highlight density), screen backlight (skin chromatic warmth, iOS only), steady backlight (temporal luma stability) |
  | S7 – OpticalFlowAnalyzer | `analysis/optical_flow_analyzer.dart` | Static photo (stasis — all blocks near-zero MAD), rigid-body replay (low spatial variance of block motion energies) |
  | S8 – FaceGeometryAnalyzer | `analysis/face_geometry_analyzer.dart` | Flat surface (3-D depth via cos(yaw) Pearson correlation, eye-ratio consistency), no motion (nose landmark velocity), suspicious asymmetry (eye-open symmetry) |

- **Face landmarks** — `FaceDetectorOptions.enableLandmarks: true` now active. `FaceData` exposes 10 `LandmarkPoint? ({double x, double y})` fields: `leftEyePosition`, `rightEyePosition`, `noseBasePosition`, `leftCheekPosition`, `rightCheekPosition`, `leftMouthPosition`, `rightMouthPosition`, `bottomMouthPosition`, `leftEarPosition`, `rightEarPosition`.

- **New `LivenessController` score getters** — `liveReplayScore`, `liveScreenScore`, `liveFlowScore`, `liveGeoScore` expose rolling per-signal scores for custom overlays.

### Improvements

- **`openMouth` detection faster and more reliable** — replaced single-frame bbox delta (required 8% jump in one frame — too strict) with a 6-frame rolling median baseline comparison at 5% threshold, held for 2 frames. Added `smilingProbability > 0.65` as a secondary OR-signal (ML Kit raises this when teeth are visible). Net result: detection fires in ~2 frames (~100 ms at 20 fps).

- **MiniFASNet preprocessing corrected** — `NormalisedMiniFAS` wrapper expects input `[−1, 1]`; the previous wrapper-compensation formula produced `[−4.6, +4.3]` which collapsed outputs to a degenerate ~0.94 for all inputs. Changed to simple BGR `p / 127.5 − 1.0`.

- **Debug overlay extended** — `showDebugOverlay: true` now shows all 8 signals: `VR-B`, `LAP`, `HET`, `TF`, `RA`, `SCR`, `FLOW`, `GEO` with inline `⚠`/`ok` indicators.

---

## 3.0.0

### New Features

- **Video Replay Attack Detection** — `enableVideoReplayDetection: true` adds a second TFLite model (MiniFASNet-V2, 1.7 MB) that runs alongside the existing anti-spoof model to detect pre-recorded video replay attacks. Auto-downloads and caches on first use — no manual model management.
  - `LivenessConfig.enableVideoReplayDetection` (default `false`)
  - `LivenessConfig.videoReplayThreshold` (default `0.50`) — score below this flags `videoReplayDetected: true`
  - `LivenessConfig.videoReplayModelPath` / `videoReplayModelUrl` / `videoReplayInputSize` — custom model support
  - `LivenessResult.videoReplayScore` — raw MiniFASNet real-face probability (0.0–1.0)
  - `LivenessResult.videoReplayDetected` — `true` when a video replay attack is flagged
  - `VideoReplayModelDownloader` — streaming HTTP download with progress, primary + fallback URL, cache validation

- **Deepfake threshold** — `LivenessConfig.tfliteDeepfakeThreshold` (default `0.40`). `deepfakeDetected` is now correctly set based on TFLite real-face score vs this threshold.

### Improvements

- **Anti-spoof engine upgraded to 9 signals** — two new heuristic signals added:
  - Signal 8 — Brightness variance (weight 0.12): screens have a stable backlight; real rooms flicker subtly
  - Signal 9 — Motion jitter (weight 0.05): real humans have micro-tremors; video playback is unnaturally smooth
  - Composite threshold raised from 0.45 → 0.50

- **TFLite `_singleScore` uses softmax** — replaced raw value clamping with numerically stable softmax. Fixes incorrect 0% real-face scores when model outputs raw logits with negative values.

### Bug Fixes

- **`_dualScore` spoof fraction inverted** — leaf[i]=1 means a spoof vote; `realScore` is now correctly `1.0 − spoofFraction` (was using `spoofFraction` as real score, giving ~8% for real faces).
- **`deepfakeDetected` always false** — was never set; now correctly derived from `tfliteScore < tfliteDeepfakeThreshold`.

---

## 2.9.0

### New Features

- **Bundled anti-spoof model — zero-config TFLite** — `enableTFLite: true` is now all you need. The package automatically downloads `FaceAntiSpoofing.tflite` (3.9 MB) on first launch and caches it permanently. No `tfliteModelUrl`, no `tfliteInputSize`, no model file to bundle. Custom models are still fully supported via `tfliteModelPath` / `tfliteModelUrl`.
  - `TFLiteModelDownloader.bundledModelUrl` — package-internal constant; not exposed in the public API.
  - `TFLiteModelDownloader.bundledInputSize` — `256` (required by the bundled FaceAntiSpoofing model).
  - `LivenessConfig.tfliteInputSize` changed from `int` (default `128`) to `int?` (default `null` → resolves to `256` for the bundled model automatically).
  - `LivenessConfig.tfliteModelUrl` — still accepted for custom models; when omitted, the bundled URL is used.

### Improvements

- **TFLite inference moved to a persistent background isolate** — `TFLiteService` now spawns a long-lived `Isolate` that owns the `Interpreter`. All frame preprocessing (pixel iteration, YUV→RGB, bbox crop/resize) and `invoke()` run entirely off the main thread. The camera preview and face-detection pipeline are never blocked, fixing the lag introduced when TFLite was enabled in v2.8.0.
  - `Interpreter.fromBuffer()` is used in the worker isolate so no Flutter asset bundle is required there.
  - `TransferableTypedData` is used for per-frame image bytes — zero-copy transfer to the worker isolate.
  - Main thread only sends a message and awaits a `Completer`; it yields the event loop while waiting.

- **`_tfliteWarning` banner auto-clears** — The red warning banner now disappears automatically once a successful TFLite inference result is received, rather than persisting for the whole session.

- **Race condition fix — `tfliteScore` always non-null on success** — `LivenessController._onEngineComplete()` now tracks `_tfliteFuture` and `await`s it before reading `_lastTfliteScore`. Previously, if the session completed on the same frame that fired the last `unawaited` inference, the score was always `null`.

### Bug Fixes

- **Camera lag and eye-blink detection broken when TFLite enabled** — Root cause: `allocateTensors()` was being called on every camera frame (an expensive synchronous native call). Fixed by calling `resizeInputTensor()` + `allocateTensors()` once at model-load time in `load()` and removing them from `run()`. Combined with the isolate move above, the main thread is now completely free of TFLite work.

- **Blink detection: instant fire on close** — `BlinkDetector` previously required the full close → re-open cycle before confirming a blink, adding 150–300 ms of latency. Now fires immediately when both eyes drop below the closed threshold. A `_wasOpenWindowMs = 1500 ms` guard (both eyes must have been clearly open within the last 1.5 s) prevents false positives from naturally droopy eyelids.

- **Blink detection: raised closed threshold to `0.50`** — Fast blinks at 20 fps often only drop ML Kit's eye-open probability to `0.45–0.55`. The previous threshold of `0.25` (and even `0.40`) silently missed these. `0.50` catches them reliably.

- **Blink detection: L/R eye sync window widened to 200 ms** — ML Kit at `FaceDetectorMode.fast` often reports left and right eye close events 1–3 frames apart. The previous implementation required both eyes in the exact same frame. The new `_eyeSyncWindowMs = 200 ms` window (≈ 4 frames at 20 fps) counts them as simultaneous.

- **Blink debounce lowered to 400 ms** — Was 800 ms; user can retry a missed blink in under half a second.

---

## 2.8.0

### Bug Fixes

- **TFLite inference was never executed** — `TFLiteService.load()` printed a success log but never instantiated an `Interpreter`; `TFLiteService.run()` returned `null` immediately because `_interpreter` was always `null`; `LivenessController._processFrame()` never called `_tflite?.run()` during frame processing. Net effect: `LivenessResult.tfliteScore` was always `null` regardless of `enableTFLite: true`.
  - Fixed `TFLiteService.load()` to call `Interpreter.fromFile()` (absolute path) or `Interpreter.fromAsset()` (Flutter asset key) depending on whether `tfliteModelPath` starts with `/`.
  - Fixed `TFLiteService.run()` — now accepts raw camera frame bytes + face bounding box + sensor orientation, internally crops and resizes the face region to `inputSize × inputSize`, and calls `_interpreter!.runForMultipleInputs()` for real inference.
  - Fixed `LivenessController._processFrame()` to fire `_tflite!.run()` asynchronously on every frame where a face is detected; `_isTfliteRunning` guard prevents frame queue-up when inference is slower than the camera rate.
  - Fixed `LivenessController._onEngineComplete()` to attach the cached `_lastTfliteScore` to `LivenessResult` via the new `withTfliteScore()` method.
  - Added `LivenessResult.withTfliteScore()` helper (mirrors the existing `withFaceId()` pattern).
  - `captureRawFrame` in `_processFrame()` is now also enabled when `enableTFLite: true` (was only enabled for `enableFaceId`).

- **`tfliteModelPath` accepted asset paths in docs but required absolute paths in code** — updated `LivenessConfig.tfliteModelPath` documentation and `TFLiteService.load()` to explicitly support both Flutter asset keys and absolute filesystem paths.

---

## 2.7.0

### Bug Fixes
- **iOS headLeft / headRight detection inverted** — iOS front-camera delivers horizontally-mirrored BGRA8888 frames; `_buildInputImage()` passes them to ML Kit with `rotation0deg` and no mirror correction. This caused ML Kit to report a flipped `headEulerAngleY` sign: physical right turn produced positive yaw (mapped to `turnLeft`), physical left turn produced negative yaw (mapped to `turnRight`). Fixed in `FaceData.fromFace()` by negating `headEulerAngleY` on `Platform.isIOS`, aligning both platforms to the same convention (positive yaw = user physically turned left). Android is unaffected — ML Kit's sensor-rotation correction already provides the correct sign there.

---

## 2.5.0

### Bug Fixes
- Added `library;` declaration to `flutter_face_liveness.dart` — fixes dangling library doc comment lint warning
- Enclosed `for` loop body in `face_embedding_model.dart` with braces — fixes `curly_braces_in_flow_control_structures` lint warning
- Wrapped home screen `Column` in `SingleChildScrollView` in example app — fixes `RenderFlex` overflow on small screens; replaced `Spacer()` with `SizedBox(height: 20)` (Spacer is incompatible with scroll views)

---

## 2.6.0

### Improvements
- Added Swift Package Manager (SPM) support for iOS — `ios/flutter_face_liveness/Package.swift` added with correct `Sources/` structure

### Bug Fixes
- Removed unnecessary `as List<double>` cast in `TFLiteService._runInference()` (line 88) — type was already inferred correctly from `List.filled`
- Removed unused `_Float32Reshape` extension on `Float32List` — `reshape()` call it depended on was already commented out

---

## 2.2.0

### Improvements
- Added banner image to README for pub.dev and GitHub documentation
- Upgraded Android Gradle Plugin to 8.9.1 (required by `androidx.camera:1.6.0`)
- Upgraded Gradle wrapper to 8.11.1
- Updated `permission_handler` to `^12.0.1` (requires Flutter 3.24+ / Dart 3.5+)
- Example app Face ID history screen — locally stores and displays all registered Face IDs with match/new status

---

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
