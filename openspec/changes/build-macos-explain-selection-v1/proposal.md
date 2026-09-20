## Why

People frequently encounter unfamiliar text while reading or working in desktop applications. Requiring them to copy, switch apps, paste, and formulate a question interrupts that work. A macOS-first desktop app can turn a selected passage into an explanation with one shortcut while keeping past explanations on the user's machine.

## What Changes

- Create a directly installed macOS Tauri app with a global shortcut and an Accessibility-first `SelectionResolver`: direct AX selected text, AX selected range plus string-for-range, selection bounds plus local OCR, then an explicit user-driven drag-to-explain OCR fallback.
- Make no access to the user's general clipboard a final product invariant. Existing automated Copy fallback is deprecated transitional code; retain its safeguards until replacement paths are implemented and validated or earlier removal is demonstrably safe.
- Support a defined first-release set of common applications, distinguish verified semantic selections from visually recovered/unverified text, and report empty, blocked, oversized, timed-out, permission-required, and failed captures honestly. OCR text requires review before transmission.
- Keep screenshot capture limited to the necessary selection region and OCR local, with bounded area/time and no screenshot transmission to the LLM or other network destination. Passive global mouse-drag inference is outside v1.
- Offer three built-in explanation prompts, optional bounded semantic surrounding context when available from the semantic provider, and a lightweight floating reply panel. Selection OCR and semantic context opt-in do not authorize surrounding-screen OCR; visual context requires separate explicit enablement and remains outside this change. In v1, users supply their own OpenAI API key; there is no app account or hosted LLM service.
- Keep a local, searchable history of successful explanations, including source application, capture method, prompt, selected text, reply, and timestamp; let users delete entries or clear history.
- Provide first-run Accessibility and API key guidance and basic controls for the shortcut, context sharing, app exclusions, and history. Request Screen Recording permission progressively, only when visual capture is needed or explicitly enabled.
- Verify the product through focused tests, a developer-only live test of the configured default model, and one final supported-app matrix on a fresh macOS profile.
- Distribute directly outside the Mac App Store without paid Apple Developer Program membership: ad-hoc-sign the public app/DMG, document and test macOS per-app Gatekeeper approval on first install, publish independently signed Tauri updates and SHA-256 checksums through GitHub Releases, and protect the updater signing key in release CI. Developer ID signing and Apple notarization are intentionally outside v1.

## Capabilities

### New Capabilities

- `selection-capture`: Invoke clipboard-free, layered semantic and local visual capture with a global shortcut and report provenance, confidence, permissions, and bounded failure states.
- `text-explanations`: Choose a built-in prompt, optionally include permitted semantic context, confirm visually recovered text, request a text-only LLM explanation, and present the result in a floating UI.
- `local-history`: Store, browse, search, and delete explanation records on the user's machine.
- `app-preferences`: Guide Accessibility, progressive Screen Recording permission, and API key setup, and configure shortcut, context sharing, app exclusions, and history behavior.

### Modified Capabilities

None. These remain new capabilities in this unarchived change; implementation already exists for part of their scope, but there are no main product specs to modify.

## Impact

This revises the plan around the existing Tauri/TypeScript shell, native Rust/Objective-C selection integration, local persistence, and OpenAI Responses client. The clipboard-free resolver, AX geometry, local OCR, visual UI, typed provenance/confidence, and progressive permissions have been implemented; their remaining development and fresh-profile validation tasks retain separate completion criteria. The user's API key stays in macOS Keychain; no LLM credential is embedded in the distributed app or stored in history. Release work now requires direct-install evidence, an independent Tauri updater signing key, and protected publication credentials, but no Apple paid signing or notarization credentials.
