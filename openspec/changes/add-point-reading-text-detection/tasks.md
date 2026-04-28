## 1. Specification

- [x] 1.1 Create OpenSpec proposal, design, and requirement delta for point-reading text detection
- [x] 1.2 Validate the OpenSpec change with strict validation

## 2. Core Implementation

- [x] 2.1 Add stable index-fingertip detection and request cooldown gating
- [x] 2.2 Crop the camera frame around the fingertip and mark the target point
- [x] 2.3 Publish the selected text to SwiftUI on the main thread
- [x] 2.4 Add an OpenAI-compatible vision model client with configurable endpoint, model, and API key

## 3. Interface

- [x] 3.1 Display selected point-reading text over the camera preview
- [x] 3.2 Display a quiet prompt or AI status when no text is selected

## 4. Verification

- [x] 4.1 Build or type-check the app target where the local environment permits
- [x] 4.2 Record any simulator or device limitations encountered during verification
