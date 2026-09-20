## ADDED Requirements

### Requirement: Provide three built-in explanations
The system SHALL offer Explain Simply, Go Deeper, and Define Key Terms as fixed presets. The shortcut SHALL use Explain Simply by default. Changing presets in the reply panel SHALL reuse the frozen selected text, permitted context, source, and provenance rather than capture from the screen again.

#### Scenario: Default explanation
- **WHEN** a verified selection is captured using the shortcut
- **THEN** the system requests an Explain Simply response for that selection

#### Scenario: User switches presets
- **WHEN** the user chooses Go Deeper or Define Key Terms in the reply panel
- **THEN** the system requests a new explanation using the same captured selection and permitted context with the chosen preset, without another AX read, screenshot, or OCR pass

### Requirement: Bound optional context
The system SHALL leave surrounding context disabled by default. When enabled, it SHALL include only bounded neighboring text available from the semantic capture provider for the same source text element when a reliable selected range exists, and SHALL keep selected text distinct from context in the LLM request. OCR of the user's selected text SHALL NOT authorize screenshot acquisition or OCR of surrounding content. The semantic-context setting SHALL NOT enable surrounding visual context; v1 SHALL leave surrounding visual context disabled, and any future implementation MUST require separate explicit user enablement and bounded capture rules.

#### Scenario: Context is enabled and available
- **WHEN** the semantic provider exposes a reliable range and the user has enabled semantic context sharing
- **THEN** the request includes at most 500 characters before and 500 characters after the selection

#### Scenario: Context is unavailable
- **WHEN** the semantic provider does not expose a reliable surrounding range
- **THEN** the system proceeds using only the captured selection

#### Scenario: Selected text is recovered by OCR
- **WHEN** visual fallback recovers the selected text and no permitted semantic surrounding context is available
- **THEN** the request contains only the user-confirmed selected text, with no expanded screenshot or adjacent-content OCR even if semantic context sharing is enabled

#### Scenario: Visual context has not been explicitly enabled
- **WHEN** the user permits Screen Recording, confirms OCR text, or enables semantic context sharing
- **THEN** none of those actions authorizes capturing surrounding visual context or sending screenshots

### Requirement: Use the user's OpenAI API key
The system SHALL send product explanation requests directly to the OpenAI API using a user-supplied key retrieved by the native app from macOS Keychain. The system SHALL use the native Responses API client with response storage disabled, no tools, and finite request and output limits. Explanation content SHALL contain only the chosen preset, selected text, and permitted text context; screenshot bytes, encoded images, and screenshot paths/URLs SHALL NOT be transmitted. The system SHALL not send a request when the key is absent.

#### Scenario: Valid key and available model
- **WHEN** a verified or user-confirmed selection is ready and a working API key is configured
- **THEN** the system sends the chosen preset, selected text, and permitted context to OpenAI and displays the reply

#### Scenario: Key is missing
- **WHEN** a selection is captured but no API key is configured
- **THEN** the system guides the user to configure a key without discarding the captured selection

#### Scenario: Provider rejects the request
- **WHEN** OpenAI returns an authentication, model access, rate limit, or network error
- **THEN** the system shows a useful error and offers retry or settings access without saving a successful history entry

### Requirement: Prevent accidental transmission of ambiguous text
The system SHALL show visually recovered/unverified text with capture provenance and confidence/verification state for explicit confirmation before sending it to OpenAI. This SHALL apply to both AX-bounds OCR and explicit-drag OCR regardless of OCR confidence; selecting a region alone SHALL NOT count as confirmation of its recognized text. It SHALL never send content from secure fields, excluded applications, a reported empty selection, or unsuccessful capture states. A confirmed visual capture SHALL retain its visual provenance rather than become semantically verified.

#### Scenario: Unverified OCR result
- **WHEN** either visual fallback returns recognized text, including a high-confidence OCR result from AX bounds
- **THEN** the panel shows the text, method, and confidence/verification state and waits for explicit user confirmation before requesting an explanation

#### Scenario: User rejects the capture
- **WHEN** the user dismisses an unverified capture
- **THEN** no LLM request is made and no explanation is stored

#### Scenario: User confirms and changes presets
- **WHEN** the user confirms a visual capture and later selects a different preset for that same invocation
- **THEN** the system reuses the confirmed text and permitted context without recapturing pixels, expanding context, or relabeling the text as semantically verified

### Requirement: Verify the configured model through an opt-in live test
The development tooling SHALL provide a developer-only, explicitly invoked smoke test of the configured default model using the same real native Responses API client as the product. It SHALL accept locally supplied credentials without unnecessary persistence or credential logging, use a harmless text fixture, and record the exact model identifier and reviewed outcome. It SHALL remain outside normal mocked CI and SHALL document a manual/pre-release command and pass criteria. Mock success or a build SHALL NOT establish that the configured default model works.

#### Scenario: Developer supplies a local credential
- **WHEN** a developer explicitly runs the documented smoke test with a locally supplied key
- **THEN** the real native client exercises the configured default model and reports a useful success/failure result without requiring the test key to be saved in Keychain, preferences, history, or repository files

#### Scenario: Normal automated verification runs
- **WHEN** normal tests or mocked CI run without explicit live-test invocation
- **THEN** they require no live OpenAI credential and make no live provider request

#### Scenario: Configured default fails the live check
- **WHEN** the native smoke test encounters an invalid model, missing access/quota, transport failure, or unusable reply
- **THEN** the configured default remains unverified and the recorded result does not silently substitute another model or claim successful validation

### Requirement: Present a lightweight reply panel
The system SHALL display loading, answer, and error states in a floating UI associated with the captured invocation. It SHALL treat model output as untrusted text when rendering.

#### Scenario: Request is in progress
- **WHEN** an LLM request is pending
- **THEN** the panel displays a loading state and allows dismissal

#### Scenario: Request succeeds
- **WHEN** OpenAI returns a text reply for the current invocation
- **THEN** the panel displays it with the selected preset and source application
