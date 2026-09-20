# Install Splainit on macOS

The initial target is Apple Silicon and macOS 14.0 or later. Minimum-version
support and fresh-profile installation are still awaiting validation. No public
release download has been established yet; the steps below are the installation
procedure to validate before publication.

Splainit uses ad-hoc code signing and does not participate in the paid Apple
Developer Program for this release. It has no Developer ID signature or Apple
notarization. macOS may show an unidentified or unverified developer warning;
we do not promise a warning-free installation.

1. Download the DMG and its matching `.dmg.sha256` file from the same
   [Splainit GitHub release](https://github.com/kshitijgundale/splainit/releases).
   The [public source repository](https://github.com/kshitijgundale/splainit)
   is an additional trust aid. In Terminal, change to their download folder and run
   `shasum -a 256 -c Splainit_0.1.0_aarch64.dmg.sha256`, substituting the actual
   version in the filename. Continue only if it reports `OK`. A checksum detects
   changed bytes; it does not establish who published them.
2. Open the DMG and drag **Splainit** onto **Applications**. Eject the image.
3. Open Splainit from Applications. If macOS blocks it because the developer
   cannot be verified, open **System Settings → Privacy & Security**. If an
   **Open Anyway** option appears for **Splainit**, choose it, authenticate if
   requested, and confirm **Open**. This approval applies to Splainit.
4. Follow Splainit's Accessibility guidance. Enter your own OpenAI API key in
   Settings, choose a shortcut, and select some harmless text in another app.
   Screen Recording should be requested only when a visual/OCR capture needs it.
5. Quit and reopen Splainit to check that settings and shortcut persist.

The per-app approval procedure follows [Apple's installation guidance](https://support.apple.com/en-gb/102445).
If approval is unavailable on a managed Mac, contact its administrator.

Never disable Gatekeeper globally, use `spctl --master-disable`, manually remove
quarantine as an installation step, or run Splainit as root. A damaged, altered,
or malware warning is different from an unidentified-developer warning: stop,
verify the checksum, obtain a fresh download from the release source, and report
the exact warning if it persists. Do not bypass that warning.

## Installation evidence

| Platform and profile | Download / install / first launch | Exact warning and approval | Restart / onboarding |
| --- | --- | --- | --- |
| macOS 14.0, fresh Apple Silicon profile | Not run | Not observed | Not run |
| Current macOS, fresh Apple Silicon profile | Not run | Not observed | Not run |
| macOS 14.3 development profile | Local package validation only | Downloaded Gatekeeper behavior not tested | Not acceptance evidence |

For each fresh-profile run, record OS/build, app version, DMG SHA-256, download
URL, exact warning text, whether per-app approval was offered, and subsequent
launch. Then record Accessibility, delayed Screen Recording permission, API-key
entry, shortcut conflicts/remapping, persistence, and restart. These observations
complete tasks 6.2–6.4 and 6.9; documentation review alone does not.
