# Splainit

Splainit targets macOS 14+ on Apple Silicon and explains selected text in another application. Press Control-Option-K (or a shortcut you set) after selecting text. A verified Accessibility selection opens the floating panel and requests an Explain Simply response. When AX cannot read the text but can isolate the selected region, Splainit can run local OCR. If that region is unavailable, eligible text fields can offer **Drag to explain**. All OCR text is shown for review and needs explicit confirmation before an explanation request. Empty, blocked, and permission-required captures are not sent. Capture never accesses the general clipboard.

The app sends selected text and, only if enabled and available from the same semantic text element, up to 500 UTF-16 code units of context on each side to OpenAI through a native text-only request. OCR uses only the selected region and never sends screenshots or captures surrounding screen text. Screen Recording permission is requested only when visual capture needs it. Enter your own API key in Settings; macOS Keychain stores it. The key is never returned to the webview. Successful explanations can be saved to a local SQLite history, with search, individual deletion, clear-all, and an option to stop saving new entries.

## Develop

Requires macOS, Xcode Command Line Tools, Rust, and Node.js. Run `npm install`, then `npm run tauri dev`. In System Settings, grant Accessibility access to the development app when prompted. Development rebuilds may change its identity and require permission again. Set an API key in the first-run Settings window to make explanation requests; API usage may incur charges on your OpenAI account.

Run `npm run build` and `npm test` for local checks. `sh scripts/test-vision.sh` separately exercises Apple Vision on a generated text fixture; it may need to run outside a restricted sandbox. `npm run tauri build -- --debug --bundles app` creates an ad-hoc-signed development bundle. See [capture policy](docs/capture-policy.md) for bounds, deadlines, and the clipboard-free invariant. [Live provider smoke instructions](docs/live-provider-smoke.md) describe the optional, explicitly invoked test for the configured default model.

## Release validation

The release path uses ad-hoc signing without paid Apple Developer Program membership, Developer ID signing, or Apple notarization. macOS may require approval of Splainit in System Settings → Privacy & Security on first launch. See [installation instructions](docs/install.md) and [build and verification instructions](docs/releasing.md).

Public-release acceptance remains pending. The [release target](docs/release-target.md) and [app matrix](docs/app-matrix.md) track the live default-model request, minimum-platform evidence, app capture matrix, fresh-profile installation, and signed-update checks. The [feasibility record](docs/feasibility.md) documents the earlier TextEdit AX probe; it does not validate the revised resolver or OCR paths. A user saw the development Splainit window on 2026-09-20, but panel positioning after a capture remains unverified.
