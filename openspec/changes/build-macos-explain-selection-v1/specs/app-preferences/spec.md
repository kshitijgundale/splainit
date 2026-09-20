## ADDED Requirements

### Requirement: Guide first-run setup
The system SHALL explain the global shortcut, macOS Accessibility access for semantic capture, the user-supplied OpenAI API key, and the fact that verified or user-confirmed selected text will be sent to OpenAI on explanation. It SHALL make missing or denied permission a visible recoverable state. First launch and AX-only use SHALL NOT request Screen Recording permission unless the user explicitly enables visual capture or invokes a visual fallback that needs it.

#### Scenario: Accessibility access has not been granted
- **WHEN** the user attempts capture without required macOS Accessibility access
- **THEN** the app identifies Accessibility as the missing permission and shows steps to enable it without accessing the general clipboard or bypassing capture safety checks

#### Scenario: First API request
- **WHEN** the user configures an API key before the first explanation
- **THEN** the app explains that requests use the user's OpenAI account and may incur provider charges

### Requirement: Request visual-capture permission progressively
The system SHALL request Screen Recording permission only when a visual/OCR fallback is actually needed or the user explicitly enables visual capture. It SHALL explain that only the necessary selected region is captured, OCR runs locally, screenshot data is temporary and never transmitted, and recognized text requires review before being sent to OpenAI. Screen Recording consent SHALL NOT authorize surrounding visual context, continuous capture, or screenshot transmission. Permission denial SHALL leave otherwise permitted semantic capture usable.

#### Scenario: First launch uses only semantic capture
- **WHEN** a new user completes Accessibility onboarding and uses successful AX capture
- **THEN** the app does not request Screen Recording permission

#### Scenario: Visual fallback first needs screen access
- **WHEN** semantic recovery fails and an eligible visual fallback needs Screen Recording access that has not been granted
- **THEN** the app explains that permission at the point of need and presents a permission-required recovery action before acquiring images

#### Scenario: User explicitly enables visual capture
- **WHEN** the user chooses to enable visual capture before first use
- **THEN** the app can request Screen Recording permission after explaining its limited purpose without enabling surrounding visual context

#### Scenario: Screen Recording permission is denied
- **WHEN** the user denies or revokes Screen Recording permission
- **THEN** the app reports that visual fallback needs permission, performs no image acquisition or clipboard fallback, and continues to allow otherwise permitted AX capture

### Requirement: Protect and manage the API key
The system SHALL save the user-supplied key in macOS Keychain, SHALL clear it from the settings input after saving, SHALL never return the saved key to the webview or logs, and SHALL allow the user to replace or remove it.

#### Scenario: User saves a key
- **WHEN** the user enters a key in settings
- **THEN** the native app stores it in Keychain and the UI subsequently shows only a configured state or masked hint

#### Scenario: User removes a key
- **WHEN** the user removes the saved key
- **THEN** subsequent explanation requests require a newly configured key

### Requirement: Configure capture behavior
The system SHALL let the user change the global shortcut with conflict feedback, enable or disable bounded semantic surrounding context, exclude applications by bundle ID, and enable or disable local history. The context control SHALL describe semantic neighboring text and SHALL NOT imply permission to OCR surrounding screen content. Surrounding visual context SHALL remain disabled in v1; a future feature MUST require separate explicit enablement.

#### Scenario: Excluded application
- **WHEN** the shortcut is invoked while an excluded application is frontmost
- **THEN** no selection, context, or screenshot is acquired and no LLM request is sent

#### Scenario: Context sharing turned off
- **WHEN** the user disables context sharing
- **THEN** subsequent requests contain no surrounding context even if the source exposes it

#### Scenario: Semantic context is enabled during visual recovery
- **WHEN** semantic context sharing is enabled but the selected text requires OCR
- **THEN** the app includes context only if it is independently available from the semantic provider and does not expand the screenshot or OCR neighboring content

#### Scenario: Shortcut is changed
- **WHEN** the user selects an available replacement shortcut
- **THEN** the old shortcut stops invoking capture and the new one invokes it

### Requirement: Support direct installation without paid Apple credentials
The public macOS app and DMG SHALL be suitable for direct download outside the Mac App Store with ad-hoc app signing and without Developer ID signing, Apple notarization, or paid Apple Developer Program membership. Installation guidance SHALL explain that macOS may show an unidentified or unverified developer warning, SHALL describe the supported per-app approval flow in System Settings → Privacy & Security after a first launch attempt, and SHALL NOT ask users to disable Gatekeeper globally, remove quarantine manually as the normal path, run the app as root, or otherwise weaken system-wide security. The release SHALL record actual first-install behavior on the supported minimum and current macOS versions rather than claim a warning-free experience.

#### Scenario: Downloaded app is blocked on first launch
- **WHEN** a user downloads the DMG, installs Splainit into `/Applications`, and macOS presents an unidentified or unverified developer warning
- **THEN** the instructions guide approval of only Splainit through System Settings → Privacy & Security and a successful subsequent launch, without a system-wide Gatekeeper change

#### Scenario: Downloaded artifact appears damaged or altered
- **WHEN** macOS reports that the downloaded app is damaged or an integrity check fails
- **THEN** release guidance directs the user to stop and verify or obtain a fresh artifact rather than treat the alert as the expected per-app approval warning

### Requirement: Verify independently signed updates and preserve user state
The app SHALL verify subsequent Tauri update artifacts against its embedded updater public key before installation and SHALL reject invalid signatures. The updater keypair SHALL be independent of Apple code signing; its private key SHALL remain outside the app and public artifacts. A valid update SHALL preserve settings, Keychain-stored OpenAI credential access, shortcut configuration, and applicable Accessibility and Screen Recording permission behavior. Key loss or rotation SHALL require a documented explicit migration strategy.

#### Scenario: Valid update is installed
- **WHEN** a user upgrades from a previous Splainit version through an update with a valid Tauri signature
- **THEN** the new version launches with the prior settings, usable Keychain credential, shortcut, and applicable permission behavior intact

#### Scenario: Update signature is invalid
- **WHEN** an update artifact does not verify against the app's embedded updater public key
- **THEN** the app rejects the update and leaves the installed version and user state intact

### Requirement: Publish verifiable direct releases
The release process SHALL publish an ad-hoc-signed app in a downloadable DMG, Tauri update artifacts and signatures, update metadata, and SHA-256 DMG checksums through GitHub Releases or another documented static release host. Release CI SHALL protect the updater private key as a secret, SHALL document the build and verification process, and SHALL NOT require Apple Developer ID or notarization credentials. Normal CI SHALL NOT require a live OpenAI key.

#### Scenario: A release tag is published
- **WHEN** release CI processes a release tag
- **THEN** the public release contains the DMG, updater artifact, updater signature, update metadata, and DMG checksum needed to verify and install that version

#### Scenario: Release secrets are reviewed
- **WHEN** the release pipeline and public artifacts are inspected
- **THEN** the updater private key and publication credentials are absent from source, logs, caches, and published files, and no paid Apple signing or notarization credential is required
