## Context

The change has a Tauri 2/TypeScript app, a Rust command boundary, an Objective-C AX reader, a clipboard-free layered resolver with local OCR and explicit visual selection, Keychain credentials, a native Responses API client, a floating panel, settings, and SQLite history. Completed implementation tasks retain credit; development and fresh-profile acceptance evidence remains open. Direct distribution must work without paid Apple Developer Program membership.

The compatibility targets remain Safari, Google Chrome, TextEdit, Notes, Preview with selectable-text PDFs, and VS Code. They are test targets, not claims of uniform support across every control. A recorded TextEdit development probe establishes one direct AX path; it does not establish the full matrix or interactive panel behavior. Local OCR recovers visible selected regions; whole-document OCR and general scanned-PDF support remain outside v1.

The current scope decision is macOS 14.0 minimum and Apple Silicon (`arm64`) only. Configuration defaults to `gpt-4.1-mini`, with a user model override, but no successful live native request is recorded. Minimum-OS validation, tested-model evidence, and supported-app acceptance remain open under task 1.3; do not infer model availability from its configured identifier.

## Goals / Non-Goals

**Goals:**

- A configurable shortcut records the source application before Splainit takes focus and resolves the current selection without reading or modifying the general clipboard in the final architecture.
- Prefer semantic capture: direct AX selected text, then AX selected range plus string-for-range. Use bounded local OCR from trustworthy selection geometry next, then offer an explicit drag-to-explain fallback if recovery fails.
- Automatically explain verified nonempty semantic text; preview visually recovered/unverified text with its provenance and confidence and require confirmation before sending it. Prompt changes reuse the frozen capture.
- Keep capture/OCR work off the UI thread, enforce finite time/area/text limits, and preserve exclusion, secure-field, cancellation, and supersession checks across every path.
- Keep screenshots local and temporary, request Screen Recording permission only when needed, and distinguish selection OCR from permission to share surrounding context.
- Preserve Keychain isolation and local history controls, and verify product behavior separately from direct-install, updater, and release automation. Make public distribution independent of paid Apple credentials.

**Non-Goals:**

- Windows/Linux support, guaranteed coverage of arbitrary apps, browser extensions, cloud history sync, app accounts, billing, or custom prompts.
- Passive global mouse-drag inference (a possible future enhancement requiring separate design), continuous screen capture, secure/private-field capture, entire-document scraping, or automatic OCR of surrounding content.
- Sending screenshots to OpenAI or another network service. A future feature would need an explicit requirement and privacy review to change this contract; Screen Recording permission or selection confirmation alone does not authorize it.
- Surrounding visual context in v1. A future opt-in must be distinct from the existing semantic-context setting.
- Apple Developer Program membership, Developer ID signing, Apple notarization/stapling, and Mac App Store distribution for v1. These may be reconsidered later as optional enhancements, never as v1 blockers.

## Decisions

### Retain the Tauri shell and native capture core

Keep the existing Tauri global-shortcut integration, native AX bridge, Rust worker/command boundary, and TypeScript UI. Introduce a layered `SelectionResolver` over those components rather than reimplementing completed shortcut, AX primitives, Keychain, transport, or history work. AX calls, image acquisition/processing, and OCR run off the UI thread; only required window/overlay operations are dispatched to the main thread. Retain finite AX messaging timeouts and add an overall processing deadline and OCR budget. User time spent choosing a drag region is separate from the bounded capture/OCR processing time.

A Swift/AppKit-only rewrite is unnecessary unless the outstanding interactive panel feasibility check establishes a blocker. Any platform capture/OCR API choice must fit the recorded macOS minimum and be verified during implementation.

### Accessibility-first SelectionResolver

```text
Shortcut (freeze source identity and invocation)
   ↓
SelectionResolver (permission, exclusion, secure-field, deadline checks)
   ↓
AX selected text
   ↓ unavailable/unreadable
AX selected range + string-for-range
   ↓ text unavailable, trustworthy nonempty selection geometry exists
AX selected range/bounds + local OCR
   ↓ unavailable/unsuitable recovery
Explicit user-driven drag-to-explain + local OCR
```

This is an ordered recovery strategy, not permission to continue after every failure. A trustworthy empty selection is terminal for that capture and never causes automatic OCR. An empty selected-text attribute is not by itself authoritative when a valid nonempty range can still be resolved. Secure fields, excluded apps, unresolved required permissions, oversized results, expired deadlines, and superseded invocations cannot silently fall through to a weaker path. Unsupported semantic attributes or unavailable geometry may offer the explicit visual action; a failed/timed-out attempt needs a deliberate retry, not an automatic wider screenshot.

At shortcut time snapshot the frontmost app/process and invocation. Bind semantic reads to its focused element/window, and reject source changes or stale selections from inactive windows. Try direct selected text first; if unavailable, obtain a valid nonempty selected range and request exactly that range's string. Reuse existing native AX primitives while correcting the current range-first orchestration. Return typed provenance from the provider instead of deriving it from human-readable detail strings. A successful semantic result is verified only when tied to the current source selection; inconsistent evidence must not be auto-sent.

Before displaying the explanation panel, freeze the selected text, source identity, method, verification/confidence, any AX range/bounds, and permitted context. If semantic capture cannot recover text, try selection geometry before asking the user to draw a region. The visual overlay is an explicit recovery UI; it must not obscure pixels used for OCR or replace the recorded source with Splainit itself.

### AX geometry and bounded local OCR

Recover selection bounds from a trustworthy selected range or equivalent AX selection geometry even when string-for-range is unavailable. Validate the geometry against the captured source window, visible display coordinates, display scale, and a documented maximum pixel area before acquiring images. Use the minimum necessary region(s), preserving per-line regions or masks when a broad bounding box would include unrelated text. Full-window/display screenshots followed by broad OCR are not an acceptable fallback. If the selection cannot be isolated safely, ask for explicit visual selection or return a useful failure.

Run OCR locally using a native on-device recognizer. Both geometry-derived and user-drawn regions share the same area/text limits, OCR timeout, cancellation, and supersession controls. Define concrete processing deadlines and pixel-area limits under the capture/privacy policy before enabling these paths. Reject excessive regions before acquisition and excessive recognized text before explanation; never silently truncate. Reconstruct reading order deterministically from recognized lines/regions with documented coordinate ordering and tie-breaks; ambiguous layouts require review and cannot be promoted to semantic verification.

Keep image buffers in native memory only, release them after completion, timeout, failure, cancellation, or supersession, and do not persist screenshots, send them through webview IPC, put them in history/logs, or transmit them to any network destination. The LLM request boundary accepts text only. Add tests that exercise actual serialized outbound payloads and prove image bytes, encoded images, paths/URLs, and extra surrounding OCR content cannot enter the request.

### Explicit visual selection and progressive permission

When semantic recovery fails and automatic geometry/OCR cannot recover usable text, offer “Drag to explain.” Enter an overlay only after the user chooses it, let the user draw over visible text in the recorded source, and OCR only that region. Do not monitor ordinary mouse drags globally. Cancel or reject a region that crosses into an excluded source, a secure field, or unrelated windows; a visual path must not bypass the existing safety checks. If required source/safety checks cannot be established, return a blocked or permission-required result rather than bypass them.

Accessibility guidance supports normal semantic capture. Screen Recording permission is requested only when a visual/OCR path is actually needed or the user explicitly enables visual capture. First launch and successful AX-only use must not prompt for it automatically. Missing/denied permission produces a typed state identifying Accessibility or Screen Recording and a recovery action. Denial leaves permitted semantic paths usable and does not trigger clipboard access, wider capture, or a network request. Granting Screen Recording does not authorize continuous capture, visual context, or screenshot uploads.

All OCR text is visually recovered/unverified even when AX geometry identifies the region or the recognizer reports high confidence. Show the text, method, and confidence to the user before any explanation. Confirmation authorizes sending that text and separately permitted context; it does not change the evidence to verified or authorize more pixels.

### Typed result and context snapshot

Extend the existing capture result with explicit fields for text; source app name, bundle ID, and process identity; invocation/timestamp; method/provenance (`ax_selected_text`, `ax_range`, `ax_bounds_ocr`, or `visual_drag_ocr`); verification state; OCR confidence when available (unknown must be explicit); and optional AX range and selection bounds with their coordinate convention. Keep outcome states distinct: verified, visually recovered/unverified, empty, blocked, oversized, timed out, permission required (including permission kind and denial), and failed. An internal unavailable-provider result may advance the resolver, but must not masquerade as empty or verified. Failure results carry a useful reason without screenshot payloads. Existing names such as `no_selection` or `unverified` may be retained if these distinctions remain typed end to end.

Retain the 12,000-character selection limit and document its counting convention consistently across native, Rust, and frontend boundaries. Semantic surrounding context is off by default; when enabled and a reliable range is available from the semantic provider, include at most 500 characters before and after from that same text element. If only selected-text OCR is available, send only that text unless bounded semantic context is independently available and opted into. Neither semantic-context opt-in nor OCR of the selected region permits OCR of adjacent screen content. Surrounding visual context stays disabled in v1; any future implementation requires a separate explicit user setting and bounded policy. Store only exact text context sent, not a larger extract.

### Explanation transport and live-provider verification

Preserve Explain Simply, Go Deeper, and Define Key Terms, the native Responses client with `store: false`, no tools, finite limits, cancellation, and provider error mapping. Treat selection/context as untrusted text, reuse the frozen snapshot when changing prompts, and render model output as untrusted text. Keep user keys in Keychain after settings entry and never return saved keys to the webview or record them in history/logs. Response-storage disabling is not a zero-provider-retention claim.

Add an explicitly invoked developer-only smoke-test path that calls the real native `openai::explain` transport with a harmless fixed text fixture and the configured default model, recording the exact model identifier and reviewed result. It accepts a locally supplied credential in memory (for example via a local environment variable or secure prompt), does not require writing a temporary test key to Keychain, preferences, history, or files, and does not log it. Do not silently substitute another model on failure. Normal automated tests/CI remain mocked and require no OpenAI key; document a separate manual/pre-release command and pass criteria. The live run is required evidence for task 1.3, not something a build or mock response can establish.

### Preserve UI, history, and preferences

Reuse the floating panel, its verified auto-send and unverified preview behavior, settings, SQLite history/migrations, history deletion, and narrow IPC capabilities. Extend the panel's copied-text wording to explain OCR provenance/confidence and permission recovery; this extension is new work. History continues to store the actual selected text, permitted context, capture method, preset/version, prompt, response, model, source, and timestamp, with no image or credential storage. Keep exclusion, shortcut-conflict, and history settings. Validate panel visibility and positioning in the final matrix; the development feasibility trace alone is insufficient.

### Separate product verification from direct distribution

Product verification consists of focused automated tests, the explicit live-provider smoke test, development path measurements, and one final supported-app acceptance matrix on a fresh macOS user profile. Record exact expected/actual text, latency, method, verification/confidence, permission requirements, false positives, and empty-selection behavior for every target app/control. Exercise direct AX, AX range, and visual recovery where applicable; mark unsupported or unavailable paths honestly. The final matrix also covers secure fields, permission denial, long selections, selectable PDFs, shortcut conflicts, and floating-panel positioning. Narrow public documentation to reliable measured paths.

Distribution is a direct download outside the Mac App Store. Produce an ad-hoc-signed `.app` and DMG for Apple Silicon; an earlier development DMG readability check is useful evidence but does not establish public-install readiness. Apple does not identify or notarize this build. A downloaded copy may be stopped on first launch; after attempting to open it, the user can approve only Splainit through System Settings → Privacy & Security → Open Anyway and confirm Open. The release instructions must never direct users to disable Gatekeeper globally, use `spctl --master-disable`, manually remove quarantine as the normal path, run the app as root, or weaken system-wide security. An integrity or malware warning is not automatically the expected unidentified-developer warning; investigate a damaged or altered artifact rather than instructing users to bypass it. Record actual warning and approval behavior on both the supported minimum and current macOS versions, without claiming warning-free installation. [Apple's per-app approval guidance](https://support.apple.com/en-gb/102445) is the reference for installation copy.

Run a fresh-profile release test using the downloaded DMG: mount, drag into `/Applications`, attempt first launch, record Gatekeeper behavior, approve the app through the supported per-app flow if offered, launch, grant Accessibility, configure the API key and shortcut, then exercise restart and settings persistence. Screen Recording is requested only when visual/OCR fallback needs it. This release test is separate from the final supported-app product matrix.

macOS first-install trust and Tauri updater trust solve different problems. Ad-hoc signing provides no Developer ID identity or Apple notarization for initial distribution, so the user explicitly approves the app. Subsequent update packages must pass cryptographic verification against the Tauri updater public key embedded in the app; the independently generated private key is release-critical, stored and backed up securely, and available to release CI only as a protected secret. Document recovery and a deliberate migration path before loss or rotation; never rotate silently or embed the private key in the app, metadata, source, logs, caches, or artifacts. Reject invalid update signatures. Preserve the app identity and state locations so upgrades retain settings, Keychain credentials, SQLite history, shortcut configuration, and applicable Accessibility/Screen Recording permission behavior. Verify these properties with a previous-version upgrade and document rollback compatibility.

Use GitHub Releases as the static public release channel unless a suitable host is already specified. A tag/release trigger builds Splainit, ad-hoc-signs the app, builds the DMG and updater artifact, signs the updater artifact with the independent key, generates SHA-256 DMG checksums and update metadata such as `latest.json`, then publishes the DMG, updater artifact, signature, metadata, and checksums together. Document the build process and artifact verification. Protect the updater private key and GitHub publication token; CI requires no Developer ID certificate, `.p12`, App Store Connect notarization key, Apple ID notarization credential, or live OpenAI key. If source is public, release documentation may link artifacts to source as an additional trust aid, without imposing an open-source requirement. [Tauri's macOS signing](https://v2.tauri.app/distribute/sign/macos/), [GitHub release](https://v2.tauri.app/distribute/pipelines/github/), and [updater](https://v2.tauri.app/plugin/updater/) guides inform this release path.

## Risks / Trade-offs

- [AX coverage differs by app/control] → Measure all target paths and empty selections; retain explicit unsupported states and narrow support claims.
- [OCR can misread text or include unrelated pixels] → Restrict acquisition to validated selection regions, use deterministic reading order, report confidence/provenance, and require review for every OCR result.
- [Extra permission can disrupt onboarding] → Request Screen Recording only when visual capture is needed or enabled; keep AX-only use independent.
- [Focus, window movement, and display scaling can invalidate geometry] → Bind geometry to the invocation/source and revalidate before pixel acquisition; fail safely when stale.
- [Cancellation leaves native work running briefly] → Bound worker operations and recheck supersession before image acquisition, publishing, transmission, or history writes; dispose of buffers on every exit.
- [A future capture fallback could reintroduce clipboard access] → Keep the completed no-general-pasteboard invariant and its regression coverage across all capture outcomes.
- [Selected text/history can be sensitive] → Capture only on explicit invocation, retain exclusions and secure-field checks, keep history local with deletion controls, and never log payloads or keys. SQLite is not independently encrypted in v1.
- [The configured model may lack account access or quota] → Keep model override and provider errors and require the explicit native live test before claiming a tested default.
- [Ad-hoc distribution triggers macOS trust warnings] → Document the exact per-app approval path and verify it on the minimum and current macOS versions; never claim Apple verification or ask users to weaken Gatekeeper globally.
- [A compromised or lost updater key undermines update trust] → Protect and back up the private key, pin the public key in the app, test invalid-signature rejection, and plan explicit key rotation/recovery before changing keys.
- [An update changes app identity or state locations] → Test a previous-version upgrade for retained settings, Keychain access, history, shortcut, and permission behavior; plan forward migration and rollback compatibility.

## Migration Plan

Reuse the completed app; no rewrite is authorized by this planning change. The typed model, resolver ordering, geometry/OCR providers, explicit visual UI, permission/context policy, and Copy retirement are recorded as implemented in tasks 2.6–2.13. Complete the development matrix, live-provider check, and final fresh-profile product matrix before claiming measured support. Separately build and validate the ad-hoc direct download, per-app first-launch approval, signed updater, and release publication path before claiming public distribution readiness.

Implementation record and remaining evidence (completed tasks are authoritative for implementation progress):

| Area | Inspected implementation/evidence | Remaining work |
| --- | --- | --- |
| AX and resolver | Tasks 2.6–2.11 and 2.13 record the typed clipboard-free resolver, AX geometry, bounded local OCR, explicit drag selection, and Copy retirement as implemented. | Run the development and final supported-app matrices (2.12 and 5.7); do not infer cross-app support from focused tests. |
| Context and UI | Tasks 3.6, 3.8, and 4.5 record semantic-only visual-context policy, OCR review, and progressive Screen Recording guidance as implemented. | Verify first-run and permission behavior after direct installation (6.4) and in the supported-app matrix (5.7). |
| Tests | Tasks 5.1–5.6 record focused resolver/OCR/privacy/permission and clipboard-free regression coverage as implemented. | Complete real-provider and fresh-profile evidence (3.7 and 5.7). |
| Live model | `gpt-4.1-mini` is configured; native transport exists, but no dedicated live smoke-test path or successful live default-model evidence is recorded. | Add the opt-in native test and document/run it with locally supplied credentials; leave the tested-default decision open. |
| Compatibility | `docs/feasibility.md` records one TextEdit AX probe and an unresolved interactive-window observation; `docs/app-matrix.md` is mostly pending. | Extend development matrix fields and run the final fresh-profile matrix, including visible panel positioning. |
| Documentation | Public installation and compatibility claims need review against the revised direct-distribution and measured app behavior. | Complete tasks 5.7 and 6.9–6.10 before making release claims. This planning update changes only OpenSpec artifacts. |
| Distribution | A development DMG build/readability check is recorded; no fresh-profile direct-install evidence or configured updater/release CI is recorded. | Complete the ad-hoc app/DMG, per-app Gatekeeper flow, signed updater, checksums, and GitHub publication tasks independently; a local build alone is insufficient. Paid Apple credentials are out of scope. |

Retain existing history and preferences. Any necessary schema changes require forward migrations that preserve records; plan upgrade and rollback compatibility before publishing. An updater downgrade must not expose existing history to an incompatible schema. Deployment and rollback procedures are completed with the distribution tasks, independently of product acceptance.

## Open Questions

- What concrete OCR pixel-area limit, processing deadlines, and supported reading-order/layout rules pass representative hardware measurements? Document these before enabling visual capture.
- Which macOS 14.0/app/control combinations pass each semantic or visual path, including multi-display geometry and empty selections? Keep claims scoped to recorded evidence.
- Does the configured default model succeed through the real native client with a locally supplied key? Task 1.3 remains open until that evidence and platform acceptance are recorded.
- Which GitHub release repository, protected updater-key storage/backup, and previous-version fixture will be used? These are release implementation inputs; no Apple Developer ID or notarization credential is required.
