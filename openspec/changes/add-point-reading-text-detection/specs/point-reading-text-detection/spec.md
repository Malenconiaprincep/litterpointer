## ADDED Requirements

### Requirement: Capture a point-reading image when the index fingertip is stable
The system SHALL use on-device hand tracking to detect a stable index fingertip and prepare a cropped image around the fingertip for AI recognition.

#### Scenario: Index fingertip remains stable
- **WHEN** the index fingertip remains within a small movement threshold for the configured number of frames
- **THEN** the system captures a cropped image around the fingertip
- **AND** the crop includes a visible marker at the exact point

#### Scenario: Index fingertip is moving
- **WHEN** the index fingertip moves beyond the stability threshold
- **THEN** the system does not start a new AI recognition request

### Requirement: Recognize pointed text with a vision-capable AI model
The system SHALL send the marked crop to a configured OpenAI-compatible vision model and request only the text indicated by the marker.

#### Scenario: AI configuration is available
- **WHEN** a stable fingertip crop is available and an API key is configured
- **THEN** the system sends one AI request using the configured endpoint and model
- **AND** the returned text becomes the selected point-reading text

#### Scenario: AI configuration is missing
- **WHEN** a stable fingertip crop is available but no API key is configured
- **THEN** the system exposes a non-crashing missing-configuration state

#### Scenario: A request is already in flight
- **WHEN** an AI recognition request is active
- **THEN** the system does not start another request until the active request finishes

### Requirement: Display selected point-reading text
The system SHALL display the currently selected point-reading text in the camera interface without requiring speech playback.

#### Scenario: Selected text is available
- **WHEN** point-reading text is selected
- **THEN** the interface shows the selected text prominently over the camera view

#### Scenario: Selected text is unavailable
- **WHEN** no point-reading text is selected
- **THEN** the interface shows an unobtrusive prompt to point the index finger at text
