## Why

The app can already locate fingertips in the camera preview, but it does not yet connect a pointing gesture to readable content in the scene. Adding point-reading text detection turns the existing hand tracking into a useful reading aid by showing the text under the user's index finger.

## What Changes

- Add local camera-frame text recognition using Vision.
- Determine which recognized text region is being indicated by the index fingertip.
- Display the currently pointed text on screen as readable text.
- Keep speech playback out of scope for this change.

## Capabilities

### New Capabilities
- `point-reading-text-detection`: Detect text near the user's index fingertip and expose the selected text to the UI.

### Modified Capabilities

## Impact

- Affects `HandPoseProcessor` by adding text recognition and point-to-text selection.
- Affects `ContentView` by displaying the selected text.
- Uses existing Apple Vision and AVFoundation frameworks; no new external dependencies.
