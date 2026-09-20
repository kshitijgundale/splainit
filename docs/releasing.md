# Build and verify a direct macOS package

Use macOS with the project development prerequisites. Install locked JavaScript
dependencies with `npm ci` and fetch locked Rust dependencies with
`cargo fetch --locked --manifest-path src-tauri/Cargo.toml`. On the release
maintainer's Mac, run `python3 scripts/setup-updater-key.py` once to establish the
key locations below. Then run:

```sh
npm test
npm run build:release
npm run verify:release
python3 scripts/test-release-integrity.py
```

The build uses the Rust release profile, an explicit `aarch64-apple-darwin`
target, and the lockfile with offline Cargo resolution. DMG creation and
verification need macOS disk-image services and may require running outside a
restricted development sandbox. They do not require running as root. The
configured signing identity is `-`, Tauri's [ad-hoc signing option](https://v2.tauri.app/distribute/sign/macos/#ad-hoc-signing).
No Apple certificate, paid membership, or notarization credential is required.
The launcher sets ad-hoc signing and removes Apple certificate and notarization
credentials from the build environment.

Output is under `src-tauri/target/aarch64-apple-darwin/release/bundle/`:

- `macos/Splainit.app`: the signed application.
- `dmg/Splainit_<version>_aarch64.dmg`: the direct-install image.
- `dmg/Splainit_<version>_aarch64.dmg.sha256`: written after verification succeeds.
- `macos/Splainit.app.tar.gz` and `.tar.gz.sig`: updater archive and signature.

The verifier checks the executable architecture, bundle ID
`app.splainit.desktop`, configured version, minimum OS target, ad-hoc signature,
and sealed resources. It verifies the DMG checksum, mounts it read-only without
opening Finder, checks the `/Applications` link and package contents, and compares
every app file, executable mode, and symlink with the verified build. It always
detaches a successfully mounted image. `npm run verify:release -- --app-only`
checks only the app; it does not establish that the DMG is valid.

For a downloaded release, use `shasum -a 256 -c <DMG filename>.sha256` in the
download directory. Package integrity is separate from Gatekeeper acceptance,
tested app compatibility, and updater signature verification. Preserve the
fresh-profile evidence in [install.md](install.md) and the product matrix in
[app-matrix.md](app-matrix.md) before claiming release readiness.

## Publication and updates

GitHub Releases is the selected hosting service. `.github/workflows/release.yml`
runs on `v*` tags in the `release` environment. It tests without credentials,
builds and verifies packages, checks invalid-signature rejection, uploads the
complete asset set to a draft release, then publishes it. Checkout and Node setup
actions are pinned to commits. There are no build caches or broad artifact
uploads. The signing key is available only to the build step; a job-scoped
GitHub token supplies publication rights. No OpenAI or paid Apple credential is
used. Never publish private keys in source, archives, logs, or release assets.

After a GitHub repository exists:

1. Set `plugins.updater.endpoints` in `src-tauri/tauri.conf.json` to
   `["https://github.com/OWNER/REPO/releases/latest/download/latest.json"]`.
   Keep the actual public key and rebuild after changing the endpoint.
2. Create the GitHub `release` environment with a required maintainer reviewer
   and deployment tag policy restricted to `v*`. Protect tag creation and
   workflow changes. Review the tagged workflow before approving secret access.
3. Set its `TAURI_SIGNING_PRIVATE_KEY` secret from the protected file over stdin
   with the command below. The generated key uses an empty password. If using
   a password-encrypted key, also set `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`.
4. Keep the app, Cargo, and npm versions aligned. Complete acceptance checks and
   update `docs/release-notes.md`, then push the matching version tag. Publication
   proceeds after environment approval.

```sh
gh secret set TAURI_SIGNING_PRIVATE_KEY --env release --repo OWNER/REPO < ~/.config/splainit-release/updater.key
python3 scripts/prepare-release.py --repository OWNER/REPO --tag v0.1.0
```

The preparation command verifies endpoint, version, identity, DMG, and updater
signature before staging the DMG, checksum, archive, signature, `latest.json`,
and `SHA256SUMS` under `src-tauri/target/release-assets/<tag>/`. Metadata embeds
the signature contents and a version-specific archive URL for `darwin-aarch64`.
It refuses an unconfigured or mismatched endpoint. After publication, download
the assets from that release, run `shasum -a 256 -c SHA256SUMS`, and verify the
updater archive against the embedded key:

```sh
cargo run --locked --offline --manifest-path src-tauri/Cargo.toml \
  --example verify_update -- /path/to/Splainit.app.tar.gz /path/to/Splainit.app.tar.gz.sig
```

The verifier uses the same Minisign verification library and public key as the
app. Settings offers **Check for updates** followed by **Install and restart**.
The capture panel has no update IPC permissions. An unconfigured build reports
that state without making an update request. See the [Tauri updater guide](https://v2.tauri.app/plugin/updater/)
for the signature and metadata contract.

The repository is [kshitijgundale/splainit](https://github.com/kshitijgundale/splainit).
Its static update endpoint is embedded in the app. On 2026-09-20, the `release`
environment was configured with `kshitijgundale` as required reviewer, admin
bypass disabled, and a `v*` tag policy. Its encrypted `TAURI_SIGNING_PRIVATE_KEY`
secret exists; release-tag deletion/replacement is prohibited by an active rule.
Local metadata and all staged signatures were verified. The endpoint will serve
`latest.json` only after the first approved publication; no public release or
successful real upgrade is claimed yet. Public source provides an additional
trust aid alongside the package checks.

## Updater key custody and recovery

The independent key is at `~/.config/splainit-release/updater.key`. Its
byte-verified local backup is at
`~/.local/share/splainit-release-backup/updater.key`. Directories have mode `0700`
and files `0600`. These are unencrypted files protected by filesystem
permissions. Both copies are on this Mac; an additional access-controlled
off-device backup protects against machine loss.

The setup script creates the key once, suppresses private CLI output, checks
the backup, and embeds only the public key. It refuses to replace a different
backup or embedded public key. Keep private copies out of this project, caches,
support bundles, and public artifacts. The embedded public value is safe to
commit.

- **Working copy lost:** restore the exact backup with owner-only permissions.
  Restore its `.pub` file from the embedded public value if necessary. Sign a
  harmless fixture and verify it before changing CI secrets. Do not generate
  a replacement key to repair a missing file.
- **Planned rotation:** while the old key is available, ship a bridge release
  signed by that key that embeds the new public key and a new endpoint. Pin the
  old endpoint to the bridge for older clients; serve new-key releases at the
  new endpoint. Test both upgrade hops before retiring old-key access.
- **All copies lost:** existing clients cannot trust an update signed by a
  different key. Publish an explicit manual-install migration through the
  established channel, retaining the app/state identity. Never disable signature
  verification.
- **Key compromised:** stop publication, revoke access, and investigate affected
  artifacts. The compromised key cannot establish a trusted recovery bridge;
  use a separately authenticated manual migration.

## Upgrade and rollback acceptance

The app identity and preferences domain remain `app.splainit.desktop`. History
stays in `history.sqlite3` in the app-data directory, with SQLite schema 1. The
OpenAI Keychain item keeps service `app.splainit.desktop.openai` and account
`api-key`. This updater change adds no migration or state deletion. Ad-hoc code
changes can affect macOS permissions and Keychain approval; observe that behavior
rather than assuming it is preserved.

Install a real prior release, save harmless history, configure a test credential,
shortcut and preferences, and record permissions. Upgrade through Settings and
verify history search, credential usability without exposing it, shortcut,
preferences, and Accessibility/Screen Recording behavior. Test an invalid update
signature and confirm the installed version and user state remain intact. Record
both versions, OS/build, hashes, and any renewed permission prompts. Local
signature rejection alone does not complete task 6.8; no previous public release
is available yet.

For rollback, quit the app and preserve preferences and app data before replacing
it with a known-good verified DMG. Do not delete history or the Keychain item.
The older app must support the existing database schema; this version refuses
schemas newer than 1. Prefer a forward fix if a future migration prevents
rollback. Do not force downgrades through update metadata or rewrite database
versions to bypass compatibility checks.
