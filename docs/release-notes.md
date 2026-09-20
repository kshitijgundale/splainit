Splainit explains selected text with a configurable shortcut, local selection
OCR, and a user-supplied OpenAI API key.

This release targets Apple Silicon and macOS 14.0 or later. Read the repository's
`docs/release-target.md` and `docs/app-matrix.md` for measured compatibility and
limitations. These documents must contain the completed release acceptance
evidence before the first public release tag is pushed.

Download the DMG and matching `.dmg.sha256` file. Verify the checksum, mount the
image, and drag Splainit into Applications. This app is ad-hoc-signed without
Developer ID signing, Apple notarization, or paid Apple Developer Program
membership. On first launch, macOS may require approval of Splainit through
System Settings → Privacy & Security → Open Anyway, then Open. Never disable
Gatekeeper globally, remove quarantine manually, or run the app as root. A
damaged or malware warning requires investigation; it is not the expected
unidentified-developer approval. See `docs/install.md` for details and observed
installation behavior.

The `.app.tar.gz` file and `.sig` are for the signed updater. `latest.json` points
to that archive; `SHA256SUMS` covers all published assets. An updater signature
is independent of Apple's first-install trust checks.
