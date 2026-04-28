## Context

The current app streams camera frames through `CameraSessionController` and passes each frame to `HandPoseProcessor`, which uses `VNDetectHumanHandPoseRequest` to publish fingertip coordinates. `FingertipOverlay` maps those coordinates back onto the camera preview.

Point reading needs to combine two signals from the same frame: the index fingertip location and the surrounding visual text context. Local OCR was not reliable enough for angled books and title/body layout separation, so the feature now uses local hand tracking to trigger a cropped image request to a vision-capable AI model.

## Goals / Non-Goals

**Goals:**
- Detect when the index fingertip is stable over text.
- Crop the camera frame around the fingertip and mark the exact point with a green dot.
- Ask a vision-capable AI model to return the text indicated by the marked point.
- Publish a stable text string for SwiftUI to display.
- Keep the existing fingertip overlay behavior intact.

**Non-Goals:**
- Speaking the text aloud.
- Full-page OCR layout reconstruction.
- Persistent document scanning, history, or translation.
- Continuous per-frame AI calls.

## Decisions

1. Use `VNDetectHumanHandPoseRequest` locally and call a vision-capable AI model only after the index fingertip is stable.

   Rationale: local hand tracking is fast and cheap, while the AI model is better at understanding which visual line, title, or text block the marked point belongs to. Gating requests on finger stability controls cost and avoids jitter.

2. Crop and mark the image before sending it to the AI service.

   Rationale: sending only the local region around the fingertip reduces image token cost, latency, and irrelevant text. Drawing a green marker on the crop removes ambiguity about the intended point.

3. Keep the AI endpoint and API key configurable outside tracked source.

   Rationale: the app can test against an OpenAI-compatible endpoint without committing secrets. A missing key should produce a visible but non-crashing state.

## Risks / Trade-offs

- Network requests add latency and require connectivity -> Trigger only after a stable finger hold and show an "AI recognizing" state.
- Client-side API keys can be extracted from app bundles -> Use only for local testing; production should proxy through a backend.
- Cropping too tightly may hide the relevant line -> Include a generous square around the fingertip and draw the exact marker.
