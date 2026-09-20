## ADDED Requirements

### Requirement: Invoke capture from another application
The system SHALL provide a global macOS shortcut, initially Control-Option-K, that starts a capture of the frontmost application without requiring the user to copy text manually. The system SHALL capture source identity before opening its own floating UI and bind each capture to its source and invocation.

#### Scenario: Selected text in a supported application
- **WHEN** the user highlights text in a supported application and presses the shortcut
- **THEN** the system captures the selection while the source application still owns focus and freezes the result before displaying the explanation panel

#### Scenario: Shortcut is unavailable
- **WHEN** the shortcut conflicts with an existing registration
- **THEN** the system reports the conflict and offers a way to choose another shortcut

### Requirement: Resolve semantic selection in a defined order
The system SHALL use a layered `SelectionResolver` that prefers direct AX selected text, then a valid AX selected range and string-for-range, then local OCR from trustworthy AX selection bounds, and finally an explicit user-driven visual-selection fallback if recovery remains unavailable. Existing AX primitives SHALL be reused where suitable. A provider-unavailable result SHALL be distinct from authoritative empty selection, blocked access, oversized capture, timeout, and missing permission; terminal outcomes SHALL NOT silently fall through to another provider.

#### Scenario: Accessibility reports selected text
- **WHEN** the focused text element reports a nonempty current selection
- **THEN** the resolver returns that text as verified with direct-AX provenance without invoking OCR or visual selection

#### Scenario: Accessibility exposes a range but not readable selected text
- **WHEN** direct selected text is unavailable or unreadable but the focused source exposes a valid nonempty selected range
- **THEN** the resolver requests string-for-range for exactly that range before attempting geometry/OCR and returns a successful semantic result as verified with AX-range provenance

#### Scenario: Empty text attribute has a nonempty range
- **WHEN** selected text is empty but the same focused element exposes a valid nonempty selected range
- **THEN** the resolver attempts string-for-range rather than treating the empty text attribute alone as proof of no selection

#### Scenario: Accessibility reports an authoritative empty selection
- **WHEN** the focused source reports a trustworthy zero-length selected range or otherwise establishes that no text is selected
- **THEN** the system returns empty/no-selection and does not infer text from a line, another window, or automatic OCR for that capture

#### Scenario: Stale selection exists in another window
- **WHEN** an inactive window contains a previous selection but the focused source has none
- **THEN** the system does not use the inactive selection

#### Scenario: A capture outcome is terminal
- **WHEN** a capture is blocked, oversized, timed out, superseded, or cannot proceed without a required permission
- **THEN** the resolver stops that attempt with its typed outcome and does not bypass it through another capture provider

### Requirement: Keep the general clipboard outside capture
The final system SHALL NOT read or modify the user's general clipboard/pasteboard or invoke automated Copy to capture text. Clipboard snapshotting, change-count inspection, reading, clearing, and restoration SHALL NOT be part of the target capture contract. Any existing Copy fallback is a deprecated transitional implementation gap, not an allowed final provider; retirement SHALL follow replacement validation or documented evidence that earlier removal is safe.

#### Scenario: Semantic selection is unavailable
- **WHEN** semantic providers cannot recover text
- **THEN** the final resolver uses eligible bounded visual recovery or reports a recoverable failure without accessing the general pasteboard or posting Copy

#### Scenario: Final capture paths are verified
- **WHEN** success, empty, denied, cancelled, superseded, and failed invocations are exercised after legacy fallback retirement
- **THEN** verification observes zero general-pasteboard reads/writes or automated Copy across all paths, without making clipboard race/restoration behavior a product acceptance criterion

### Requirement: Recover selection geometry safely
When semantic text cannot be read but AX exposes a trustworthy nonempty selected range or selection bounds, the system SHALL attempt to locate only that selection for local OCR. It SHALL validate source identity, visible bounds, coordinate/display scaling, and maximum area before acquiring images. It SHALL NOT substitute an entire source window or display when selection geometry cannot be isolated safely.

#### Scenario: Range bounds are available but range text is not
- **WHEN** string-for-range cannot return text but AX can locate the nonempty selection
- **THEN** the resolver derives the necessary selection region(s), validates them, and attempts local OCR with AX-bounds provenance

#### Scenario: Geometry is missing or includes unrelated content
- **WHEN** AX geometry is unavailable, stale, or cannot isolate the selected text from unrelated content
- **THEN** the system acquires no broad substitute screenshot and offers an eligible explicit visual-selection action or reports the failure

### Requirement: Bound local OCR and preserve screenshot privacy
The system SHALL acquire only the necessary selection region(s) and run OCR locally, with documented finite processing deadlines, a maximum pixel area enforced before image acquisition, and text-size limits. It SHALL reconstruct reading order deterministically using documented layout ordering and tie-breaks. Screenshots SHALL remain temporary native-memory data, SHALL be discarded on completion or termination, and SHALL NOT be persisted, exposed through webview IPC/history/logs, or transmitted to OpenAI or any other network service. Any future screenshot-transmission feature MUST explicitly revise this requirement; v1 authorizes only text requests.

#### Scenario: OCR recovers visible text
- **WHEN** an allowed selection region produces OCR text within the time, area, and text limits
- **THEN** the system returns deterministically ordered text with visual provenance, confidence when available, and visually recovered/unverified status rather than semantic verification

#### Scenario: OCR exceeds its timeout
- **WHEN** local OCR does not finish within its documented deadline
- **THEN** the system returns timed out, discards image buffers, keeps the UI responsive, and prevents late results from reaching explanation or history

#### Scenario: Requested region exceeds maximum area
- **WHEN** AX bounds or a user-drawn region exceed the documented maximum pixel area
- **THEN** the system returns oversized before acquiring the image and asks for a smaller region rather than capturing or silently truncating it

#### Scenario: Captured image could reach the request boundary
- **WHEN** OCR text is passed to explanation after user confirmation
- **THEN** the outbound request contains only permitted text and no screenshot bytes, encoded images, image paths/URLs, or unintended surrounding-screen content

#### Scenario: Visual capture is terminated
- **WHEN** visual capture completes, fails, times out, is cancelled, or is superseded
- **THEN** its temporary image buffers are released and no screenshots remain in history, files, logs, or frontend payloads

### Requirement: Offer explicit drag-to-explain recovery
The system SHALL offer an explicit visual-selection fallback only after semantic selection recovery fails and automatic AX-geometry/OCR recovery is unavailable or unusable. It SHALL enter visual-selection mode only on user action, allow the user to drag over visible text in the recorded source, and OCR only the chosen region locally using the shared limits and safety checks. V1 SHALL NOT infer selections by passively monitoring global mouse drags.

#### Scenario: User chooses visual recovery
- **WHEN** semantic recovery has failed, automatic visual recovery cannot produce usable text, and the user chooses “Drag to explain”
- **THEN** the system lets the user select a bounded visible text region and returns OCR text with explicit-drag provenance, confidence, and visually recovered/unverified status for review

#### Scenario: User cancels visual selection
- **WHEN** the user dismisses the visual-selection overlay before completing a region
- **THEN** no OCR text is transmitted and no explanation history entry is created

#### Scenario: User drags normally in another application
- **WHEN** the user makes a mouse drag without entering the explicit fallback
- **THEN** the system performs no visual inference, screenshot acquisition, or OCR in response to that drag

### Requirement: Return typed capture evidence and outcomes
The system SHALL return a typed capture result containing captured text when present, source application identity, invocation/timestamp, capture method/provenance, confidence/verification state, and optional AX range/bounds with a documented coordinate convention. It SHALL distinguish verified, visually recovered/unverified, empty, blocked, oversized, timed out, permission required (including permission kind/denial), and failed results. Provenance SHALL originate from the provider, not parsing of a display message. Unknown OCR confidence SHALL be represented explicitly; OCR confidence or user confirmation SHALL NOT promote a visual result to semantically verified.

#### Scenario: Semantic and visual captures are compared
- **WHEN** direct AX, AX-range, AX-bounds OCR, and explicit-drag OCR each produce text
- **THEN** the results identify distinct methods, the first two carry semantic verification, and both OCR methods remain visually recovered/unverified with confidence metadata

#### Scenario: Screen Recording permission is missing
- **WHEN** an otherwise eligible visual capture needs Screen Recording permission that is missing or denied
- **THEN** the result identifies Screen Recording as the required permission with a recovery action and sends no text or screenshot to the network

#### Scenario: Accessibility permission is missing
- **WHEN** semantic capture needs Accessibility access that is missing or denied
- **THEN** the result identifies Accessibility as the required permission without substituting clipboard text or bypassing safety checks

### Requirement: Preserve capture safety across providers
The system SHALL check secure fields and user-excluded applications before selection, context, or image acquisition on every path. It SHALL revalidate the source/region before visual acquisition and SHALL NOT let an explicit drag, permission grant, or fallback bypass a blocked source. If required source/safety checks cannot be established, the system SHALL fail closed with a blocked or permission-required state.

#### Scenario: Secure field or excluded application
- **WHEN** capture targets a secure field or a user-excluded application
- **THEN** the system returns blocked without acquiring selected text, surrounding context, or a screenshot and makes no LLM request

#### Scenario: Visual region crosses source boundaries
- **WHEN** a drawn region includes a secure field, an excluded application, or an unrelated window, or source geometry is no longer valid
- **THEN** the system rejects that region before screenshot acquisition rather than broadening its capture scope

### Requirement: Bound and cancel capture
The system SHALL enforce finite capture/OCR processing time and text-size limits, keep capture and OCR work off the UI thread, and prevent an older capture from publishing or sending text or writing history after a newer invocation supersedes it. The selected-text limit SHALL remain 12,000 characters with a documented consistent counting convention. User time choosing an explicit region SHALL be separate from processing deadlines.

#### Scenario: Source application does not respond
- **WHEN** a source application does not answer an Accessibility request before its deadline
- **THEN** the system reports a timeout and keeps the UI responsive

#### Scenario: Selection exceeds the text limit
- **WHEN** a semantic or OCR selection exceeds the documented text limit
- **THEN** the system asks the user to select a smaller passage and does not silently truncate it

#### Scenario: Shortcut is pressed twice
- **WHEN** a second invocation begins while the first is reading AX text, waiting for a drag, or running OCR
- **THEN** only the current invocation may publish a capture, proceed to explanation, or save a successful result, and stale visual buffers are discarded

### Requirement: Common-app development and acceptance matrices
Development verification SHALL record Safari, Google Chrome, TextEdit, Notes, Preview selectable PDFs, and VS Code with exact expected/actual selected text, latency, capture method, confidence/verification state, permission requirements, false positives, and empty-selection behavior. Product acceptance SHALL include one final matrix on a fresh macOS user profile after clipboard retirement, covering direct AX, AX range fallback, and visual fallback where applicable, plus empty selections, secure fields, permission denial, long selections, selectable PDFs, shortcut conflicts, and floating-panel visibility/positioning. Documentation SHALL narrow claims for unreliable or unsupported app/control/path combinations rather than infer support from a single success. This product matrix SHALL be separate from distribution smoke tests.

#### Scenario: Selected-text development matrix run
- **WHEN** a target app's representative control and capture paths are tested during development
- **THEN** the record includes exact expected/actual text, latency, method, confidence/verification state, required permissions, confirmation behavior, and unsupported or unreliable paths

#### Scenario: Empty-selection matrix run
- **WHEN** a target app is tested with no selected text
- **THEN** the record identifies any false positive and verifies that the system does not automatically explain unrelated text or run automatic OCR

#### Scenario: Final supported-app acceptance run
- **WHEN** the clipboard-free implementation is evaluated on a fresh macOS user profile
- **THEN** one final matrix records all required app/path and edge-case results, distinguishes unsupported paths from passes, and limits documentation claims to reliable measured behavior
