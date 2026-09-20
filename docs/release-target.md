# First release target and acceptance criteria

These are scope decisions for the first direct installer, subject to the clean-machine matrix and signing checks.

- Minimum OS: macOS 14.0. The current development machine is macOS 14.3; the minimum has not yet been tested on a separate 14.0 installation.
- CPU: Apple Silicon (`arm64`) only for the first installer. `x86_64` would require a separate build and compatibility run before claiming support.
- Candidate OpenAI default: `gpt-4.1-mini`, configured in `src-tauri/default-model.txt`. [OpenAI documents its Responses API support](https://developers.openai.com/api/docs/models/gpt-4.1-mini). **This is not yet a tested default.** No locally supplied OpenAI key was confirmed on 2026-09-19. The explicit native smoke test is documented in [live-provider-smoke.md](live-provider-smoke.md). Keep the model override for account/model errors.

The supported-app claim requires a matrix run on a fresh macOS 14 Apple Silicon profile for Safari, Google Chrome, TextEdit, Notes, Preview with selectable-text PDFs, and VS Code. For each app/control, record exact expected/captured text, method, verification/confidence, elapsed time, permissions, confirmation, and false captures for selected and empty cases. Test AX text, AX range, and visual paths where eligible, a long selection above 12,000 UTF-16 code units, denied Accessibility and Screen Recording, shortcut conflicts, and actual panel visibility/position. OCR results always require confirmation; unsupported controls must show a clear failure. Do not infer app-wide support from one passing control. No general-pasteboard access is allowed in any path.

An unsigned arm64 development DMG built successfully with `npm run tauri build -- --debug --bundles dmg`, and `hdiutil imageinfo` recognized it as a readable compressed image. This is partial packaging evidence. The current distribution decision is ad-hoc signing (`signingIdentity: "-"`), without paid Apple credentials or notarization. Zero Developer ID identities is therefore not a blocker. Fresh-profile first-run approval and signed-update tests are still needed.

On 2026-09-20 the revised clipboard-free app built another arm64 development
DMG at `src-tauri/target/debug/bundle/dmg/Splainit_0.1.0_aarch64.dmg`.
`hdiutil imageinfo` outside the restricted sandbox identified a read-only UDZO
image with a valid checksum. SHA-256:
`20a93b3371c28e167e13a61b3a752c7fce5908175360c74ef141a9405d98e852`.
The earlier sandboxed bundling and imageinfo attempts failed because disk-image
operations were unavailable there; the outside-sandbox build succeeded. The
image has not been installed, launched, or restarted on a fresh user profile,
so that development build alone does not complete task 6.1. The development
image is not production-ready. Follow [releasing.md](releasing.md) for the
ad-hoc release build and package verification; follow [install.md](install.md)
for the per-app approval flow and outstanding installation evidence.

On 2026-09-20, task 6.1 passed for a release-profile ad-hoc-signed package built
with `npm run build:release` on macOS 14.3 (`23D2057`), arm64. The package verifier
confirmed version `0.1.0`, bundle/signing identifier `app.splainit.desktop`, arm64
only, minimum target `14.0`, a valid strict ad-hoc signature and sealed resources,
and a readable DMG containing `Splainit.app`, the `/Applications` link, and
`.DS_Store`. Every app file matched the built bundle after read-only mounting.
The verified DMG SHA-256 was
`d25745f24fe2956552c7fc34e7a293c5fbd7ea9f667a782e6b34e6f90d62e81a`.
This completes package production/verification only; publication, fresh-profile
Gatekeeper/onboarding, minimum-platform support, and updater acceptance remain
open. Rebuilds have new checksums; verify each candidate independently.

The later 2026-09-20 build embeds the updater public key and the
`kshitijgundale/splainit` release endpoint. Its verified DMG SHA-256 is
`51f1b601e497e79460c9998b558aae483e59f976f824ccf7b3e652f4c325a3b9`.
The signed updater archive verified against the embedded key; an altered archive,
a forged signature, and a modified app resource were all rejected. Metadata and
SHA-256 checksums are staged in `src-tauri/target/release-assets/v0.1.0/`.
The normal native, UI, privacy, and Rust tests passed after updater integration.
These are local package/cryptographic checks, not a real prior-release upgrade.
