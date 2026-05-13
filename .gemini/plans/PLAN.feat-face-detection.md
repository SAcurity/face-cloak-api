# feat-face-detection — Automated AI Detection & Multi-Face Control

## Goal
Implement automated face detection using the Gemini API and enable independent privacy controls (Inpainting) and image generation for each detected face in a multi-person image.

## Historical Evolution & Discussion Summary

### 1. Initial Implementation & Schema
- **Action**: Added `x_min`, `y_min`, `x_max`, `y_max` to the `face_records` table.
- **Decision**: Used Float coordinates (0.0 to 1.0) for resolution-independent mapping.
- **Initial Logic**: Uploading an image triggered a sequential process: Storage -> DB Record -> AI Detection -> Face Records creation.

### 2. Technical Obstacles (The "Large Image" Problem)
- **Problem**: Sending large images (300KB+) converted to Base64 caused Gemini to return truncated responses, leading to "unexpected end of input" and 500 JSON parsing errors.
- **Lesson**: Gemini has a strict output token limit (approx. 8k-16k) which is insufficient for high-res Base64 image data.

### 3. Dependency Shift: From MiniMagick to ChunkyPNG
- **Problem**: The environment lacked `imagemagick` binaries (`identify` not found), causing `mini_magick` to crash.
- **Solution**: Switched to `chunky_png`, a pure-Ruby library. Although slower for large operations, it has zero system dependencies and is perfect for pixel-level manipulation like cropping and Mosaic.

### 4. Architectural Refinement (Inpainting)
- **Idea**: Instead of sending the full image, only send the face snippet.
- **Implementation**: 
  - **Crop**: Snippet extracted via `chunky_png`.
  - **Resize**: Snippet reduced to `128x128` before Gemini call to ensure the resulting Base64 stays well within token limits.
  - **AI Processing**: Gemini applies styles (`comic`, `mask`) to the tiny snippet.
  - **Compositing**: Resulting snippet is resized back and pasted onto the original background.
- **Caching**: AI-generated snippets are stored in `db/storage/cache/` (keyed by Face UUID and style) to eliminate redundant API calls and costs.

### 5. Global Alignment & Seeding Strategy
- **Problem**: UUIDs are random, making it hard to "align" which face belongs to which person in YAML seeds.
- **Solution**: 
  - **Coordinate Sorting**: All face records in an image are sorted from **Left to Right** (`x_min`) then **Top to Bottom** (`y_min`).
  - **Natural Index**: Seeds use `face_index: 0` for the leftmost person.
  - **Real Scenarios**: Implemented `3-people.png` and `5-people.png` with actual coordinates detected by Gemini. Simulated "unregistered users" by leaving some faces unassigned (defaulting to blur).

### 6. API RESTful Refactoring
- **Discussion**: Should face records be global or image-specific?
- **Decision**: 
  - Moved listing and creation to `/api/v1/images/:id/face_records`.
  - Removed global `/api/v1/face_records`.
  - Improved security by using `X-Actor-Id` header for ownership instead of redundant body parameters.

### 7. Detection Reliability Fixes
- **Production Error Observed**: Image upload could log `Detection Error: expected ',' or '}' after object value, got: EOF`, caused by Gemini returning truncated or malformed JSON for face detection.
- **Root Cause**:
  - Existing specs covered upload happy paths but did not directly cover Gemini face-detection response edge cases.
  - `GeminiApi.detect_faces` parsed the model response directly after a regex-based JSON extraction, which was brittle for fenced JSON, surrounding text, and truncated JSON.
  - `detect_faces.txt` included placeholder tokens such as `ymin`/`xmin` in the JSON example, which was not valid JSON and could encourage invalid model output.
- **Fixes**:
  - Updated `detect_faces.txt` to show a syntactically valid strict JSON array example and explicitly return `[]` when no face is visible.
  - Added balanced JSON payload extraction that respects nested arrays/objects and quoted strings.
  - Added detection response schema validation: the top-level payload must be an array, `box` must contain four numeric coordinates, and malformed landmark points are ignored.
  - Added one retry for `JSON::ParserError`/detection response format errors; if retry still fails, detection is skipped with a warning instead of crashing upload.
  - Treated missing Gemini configuration as `Detection skipped: Gemini API key is not configured`, avoiding misleading error logs in test/local environments.

### 8. AI Inpainting SDK Compatibility Fix
- **Runtime Error Observed**: `AI Inpainting Failed for sunglasses: undefined method 'edit_image' for an instance of Google::Genai::Models`.
- **Root Cause**:
  - The installed `google-genai` Ruby gem (`0.1.1`) only exposes `models.generate_content`; it does not expose `models.edit_image`.
  - The original implementation assumed an image editing helper that does not exist in the local SDK.
- **Fixes**:
  - Replaced the unsupported `models.edit_image` call with direct REST `generateContent` usage against `gemini-2.5-flash-image`.
  - Added parsing for generated image parts returned as either `inlineData.data` or `inline_data.data`.
  - Preserved existing `CloakImage` fallback behavior: if AI inpainting fails, apply local blur to the target face area instead of failing the request.

### 9. AI Patch Size & Scope Fixes
- **Runtime Error Observed**: `AI Inpainting Failed for sunglasses: Background image height is too small!`.
- **Root Cause**:
  - Gemini can return an edited patch whose dimensions differ from the original context crop.
  - `ChunkyPNG#compose!` requires the foreground patch to fit within the background at the target offset; oversized patches exceeded the image bounds.
- **Fixes**:
  - Added `normalize_ai_patch` to resize generated or cached AI patches back to the exact context window dimensions before composition.
  - Added regression coverage for oversized AI patches.
- **Visual Bug Observed**: Applying `comic` to one face could also alter a nearby person's face.
- **Root Cause**:
  - AI processing uses an expanded context window for visual quality. When the entire edited context patch was composed back, any AI changes made to neighboring faces inside that context were also written back.
- **Fixes**:
  - Kept expanded context for the AI call, but changed write-back to `apply_ai_patch`.
  - `apply_ai_patch` only copies pixels inside the target face ellipse, with feathering at the edge. Neighboring faces inside the context remain unchanged.
  - Added regression coverage asserting the target mask changes while nearby context pixels remain unchanged.

### 10. Local Blur Quality & Alignment Tuning
- **Visual Issue Observed**: Local blur sometimes looked misaligned, too transparent, and not soft enough.
- **Root Cause**:
  - `DetectFaces` already persists face coordinates with 10% padding.
  - `CloakImage#get_pixel_coords` then applied another 35% expansion before local `blur`/`pixelate`, causing the rendered mask to drift outward and sometimes cover nearby areas.
  - The blur mask used a large feather region, so much of the face remained partially transparent.
- **Fixes**:
  - Reduced local filter expansion to targeted padding: 8% horizontally and 12% vertically.
  - Increased soft-focus strength by using heavier downsample/upsample passes.
  - Changed the mask alpha profile so most of the face area is fully opaque, with feathering only on the outer 18% of the ellipse.
  - Added regression coverage for local filter coordinate bounds and mask opacity behavior.

### 11. Remaining Alignment Limitation & Proposed Direction
- **Current Limitation**:
  - The renderer still fundamentally uses bounding boxes plus ellipses. This is inherently fragile when Gemini's bbox is offset, faces are angled, or people are close together.
- **Landmark-First Attempt & Rollback**:
  - Attempted to make `CloakImage#get_pixel_coords` and `CloakImage#get_context_window` prefer landmarks (`left_eye`, `right_eye`, `nose`, `mouth`) over bbox coordinates.
  - User testing showed this made alignment worse. The likely causes are noisy/inconsistent Gemini landmark locations plus simplistic axis-aligned box derivation from eye/mouth distances.
  - Rendering was rolled back to bbox-first targeting for stability.
  - Landmark helper methods remain in the service for experimentation/tests, but they are not active in the rendering path.
- **Remaining Next Steps**:
  - Store raw detection boxes without permanent padding, and let each renderer choose its own padding.
  - Do not re-enable landmark-first targeting without visual test images or a calibrated formula.
  - Consider rotated/landmark-shaped masks only after validating landmark quality and coordinate conventions against real uploads.
  - Add an owner-facing correction endpoint later if the product needs manual adjustment, because automatic face detection will not be perfect in all images.
- **Working Rule**:
  - Any future change related to face detection, face record coordinates, cloak rendering, Gemini image editing, or related specs must update this plan in the same turn.

### 12. Local OpenCV YuNet Face Detection
- **Problem**:
  - Gemini-generated bbox coordinates were not reliably landing on the actual face, causing blur to miss the target even after renderer-side tuning.
  - YOLO would likely improve localization, but this environment had no Python CV runtime, no ONNX runtime, and no model files installed.
- **Decision**:
  - Added local OpenCV-based detection before Gemini fallback.
  - First attempted OpenCV Haar cascade because it requires no model file, but seed tests showed duplicates/false positives (`3-people` produced 4 detections; `5-people` produced 7 before tuning).
  - Switched to OpenCV's official YuNet face detector via `cv2.FaceDetectorYN_create`, using `vendor/models/face_detection_yunet_2023mar.onnx`.
- **Implementation**:
  - Added `app/lib/opencv_face_detector.py`.
  - Added `app/services/face_detector.rb` as the Ruby service wrapper.
  - `DetectFaces` now uses `FaceDetector.call` first and falls back to `GeminiApi.detect_faces` when local detection is unavailable, returns no faces, or raises an error.
  - Added `requirements-face-detector.txt` with `opencv-python-headless==4.13.0.92`; local `.venv` was created and installed for immediate use.
  - OpenCV/YuNet detections intentionally output only `box`; empty `landmarks: {}` is omitted and `DetectFaces` no longer stores empty landmarks payloads.
- **Observed Seed Results**:
  - `db/seeds/files/3-people.png`: YuNet detected 3 faces.
  - `db/seeds/files/5-people.png`: YuNet detected 5 faces.
- **Rationale**:
  - YuNet gives deterministic local bbox detection, avoids Gemini JSON/coordinate drift, avoids API cost, and is lighter than integrating full YOLO immediately.
  - YOLO remains a future option if YuNet is not accurate enough on target user uploads.

### 13. Deterministic Sunglasses Rendering
- **Runtime/User Issue Observed**:
  - Setting a face record to `sunglasses` did not reliably show sunglasses.
- **Root Cause**:
  - `sunglasses` was routed through Gemini image editing/inpainting, which is nondeterministic and can return a patch with little or no visible glasses.
  - The masked write-back only copies target face pixels, so generated glasses near the upper eye area could also be partially clipped depending on patch content and mask shape.
- **Fixes**:
  - Moved `sunglasses` out of the AI inpainting path.
  - Added deterministic local sunglasses overlay in `CloakImage.apply_sunglasses`, drawing dark lenses and bridge directly inside the target bbox.
  - Kept `comic` and `mask` on the AI path.
  - Added regression coverage to ensure local sunglasses visibly modifies both lens regions.

### 14. Seed Alignment & API Payload Cleanup
- **Seed Update**:
  - Reworked `db/seeds/face_record_seeds.yml` so the two seed images match the current schema and the actual visible faces in `3-people.png` and `5-people.png`.
  - Fixed the duplicated `5-people.png` face entry so the image now has five distinct face records in left-to-right order.
  - Kept `responses_seed.yml` aligned with the same face ordering so assignment/response seeding stays stable after reruns.
- **API Payload Change**:
  - Removed `landmarks` from `FaceRecord#to_h` response bodies.
  - Retained `landmarks` in the database/model for internal detection and rendering helpers, but stopped exposing it in the public face-record JSON.
- **Validation**:
  - Confirmed `FaceRecord` unit specs still pass after the response shape change.
  - Confirmed `api_face_records` integration specs still pass.

### 15. CloakImage Temp PNG Fallback
- **Runtime Issue Observed**:
  - `GET /api/v1/images/:id` could raise `Errno::ENOENT` while `ChunkyPNG::Image.from_file` tried to read `db/local/storage/cache/ws_*.png`.
  - The temporary PNG path was assumed to exist after `sips`, but in some runs the file was not created in time or was not present at all.
- **Fix**:
  - Added a dedicated `prepare_working_png` step in `CloakImage`.
  - `sips` is still used first for PNG conversion, but the code now checks that the temp file exists before loading it.
  - If `sips` fails or does not produce the file, the code falls back to copying the original PNG directly into the cache path.
  - This keeps image rendering resilient and prevents GET image requests from failing just because the temp PNG was missing.
- **Validation**:
  - Verified the image model and image API specs still pass after the fallback change.

### 16. Immediate Respond Rebuild
- **Behavior Change**:
  - `RespondToFaceRecord` now rebuilds the cloaked image cache immediately after the face record is updated and the old cache files are cleared.
  - The respond request now succeeds only after the image can be regenerated; any rendering failure surfaces during the respond call instead of waiting for the next image GET.
- **Validation**:
  - Added a regression assertion to the face-record integration spec that checks a `full_*.png` cache file exists immediately after a successful respond.

### 17. DB Schema Documentation Sync
- **Documentation Issue Observed**:
  - The DB schema docs still referenced the old static `db-schema.png` diagram and did not explicitly call out the face-detection schema additions.
- **Fixes**:
  - Updated `docs/schema.md` with an inline Mermaid ER diagram so the schema renders in-place without relying on the old image file.
  - Kept the contributor README link pointing at the single canonical schema document, `docs/schema.md`.
  - Kept the schema docs aligned with migrations `005`, `007`, and `008`: normalized face bbox fields, optional internal `landmarks`, and assignee access grants.
- **Reason**:
  - Face detection and cloaking depend on persisted bbox data. The docs must show those columns clearly so assignment, response, and rendering bugs can be reasoned about from the schema.

## Current Architecture
- **Storage**: Original images are stored under the configured local image storage directory; generated full-image and patch caches are stored under `db/local/storage/cache/`.
- **Detection**: `UploadImage` creates the image record, then `DetectFaces` reads the stored image and first calls local OpenCV YuNet through `FaceDetector`.
- **Detection Fallback**: If local OpenCV detection is unavailable or fails, `DetectFaces` falls back to `GeminiApi.detect_faces` using the strict JSON prompt.
- **Detection Parsing**: Gemini response text is normalized through balanced JSON extraction, parsed with symbol keys, validated, and converted from 0-1000 integer coordinates into normalized face-record coordinates with padding.
- **Targeting**: Active rendering uses bbox-first targeting. Landmark-derived targeting helpers exist but are not enabled because user testing showed worse alignment.
- **API Response Shape**: `FaceRecord` responses expose bbox, assignment, cloak, and timestamps, while `landmarks` remain internal-only.
- **Local Processing**: `blur`/`pixelate`/`sunglasses` are processed locally with `chunky_png`; local filter boxes use small renderer-level bbox padding and a mostly opaque soft ellipse for blur.
- **AI Processing**: `comic`/`mask` are processed through `gemini-2.5-flash-image` using REST `generateContent`; generated patches are normalized to the context size and only copied back inside the bbox-derived target face mask.
- **Fallback Processing**: AI failures fall back to local blur for the target face area.
- **Temp PNG Handling**: `CloakImage` prepares a working PNG in cache before rendering; if `sips` does not create the temp file, it falls back to copying the original PNG into place.
- **Respond Flow**: Responding to a face record now refreshes the affected image cache immediately, so success or failure is observable in the respond request itself.
- **Schema Docs**: Face-detection schema changes are documented in `docs/schema.md` with an inline Mermaid ER diagram.
- **Integrity**: `db:drop` now clears the entire storage and cache.
- **Test Isolation**: The test environment does not initialize the real Gemini client by default, even if `GEMINI_API_KEY` exists. Set `USE_REAL_GEMINI_IN_TEST=true` only for explicit external integration testing.

## Tasks & Progress
- [x] **Schema**: Add coordinate fields to `face_records`.
- [x] **lib**: Robust `GeminiApi` with balanced JSON extraction, malformed detection retry, response validation, and graceful skip behavior.
- [x] **lib/service**: Local OpenCV YuNet `FaceDetector` primary backend with Gemini fallback.
- [x] **Prompt**: Detection prompt now uses valid strict JSON examples and documents the no-face `[]` response.
- [x] **Format Conversion**: Integrated `sips` (macOS internal) into `UploadImage` to ensure all uploads are converted to PNG.
- [x] **Performance**: Implemented cache pre-warming (refresh + early CloakImage call) during upload to ensure instant GET response.
- [x] **Service**: `DetectFaces` with 0-1000 integer range and 10% padding for precision.
- [x] **Service**: `CloakImage` using pure-Ruby `chunky_png` with bbox-first targeting, local blur/pixelate/sunglasses, AI patch normalization, masked AI write-back, and stronger opaque soft blur.
- [x] **Caching**: Snippet caching system in `db/storage/cache/`.
- [x] **Controller**: RESTful hierarchical routing (`/images/:id/face_records`).
- [x] **Security**: Unified `X-Actor-Id` header-based authentication/authorization.
- [x] **Seeding**: Realistic multi-person scenarios with coordinate-based alignment.
- [x] **Seeding**: Updated seed face boxes to match the current images and kept response seeding aligned to the same face order.
- [x] **API**: Removed `landmarks` from public face-record response bodies while keeping them available internally.
- [x] **Service**: Added a resilient temp PNG preparation step in `CloakImage` with fallback copy behavior when `sips` does not create the cache file.
- [x] **Service**: Responding to a face record now rebuilds the image cache immediately instead of waiting for the next GET.
- [x] **Docs**: Updated `docs/schema.md` with an inline Mermaid ER diagram and synced face-detection schema notes.
- [x] **Testing**: Added direct Gemini face-detection response specs for fenced JSON, truncated JSON retry, and malformed JSON fallback.
- [x] **Testing**: Added direct FaceDetector specs for normalization without empty landmarks, malformed detection filtering, and optional local seed-image detection when OpenCV runtime is available.
- [x] **Testing**: Added direct CloakImage specs for bbox-first targeting with landmarks present, inactive landmark helper derivation, oversized AI patch normalization, masked AI patch write-back, deterministic local sunglasses, local filter coordinate bounds, and soft mask opacity.
- [ ] **Future Improvement**: Add visual regression fixtures, calibrated landmark validation, rotated masks, and optional owner correction for cases where automatic detection is still wrong.
- [x] **Validation**: Full test suite passing via `rake spec` (67 runs, 161 assertions); style passing via RuboCop (61 files, no offenses).
