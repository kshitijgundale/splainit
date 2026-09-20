"""Build signed release artifacts, using an existing key without printing it."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
environment = os.environ.copy()
key = Path.home() / ".config/splainit-release/updater.key"
if not environment.get("TAURI_SIGNING_PRIVATE_KEY"):
    if not key.is_file() or key.is_symlink() or key.stat().st_mode & 0o077:
        raise SystemExit("An owner-only updater key is required. Run scripts/setup-updater-key.py first.")
    environment["TAURI_SIGNING_PRIVATE_KEY"] = str(key)
environment.setdefault("TAURI_SIGNING_PRIVATE_KEY_PASSWORD", "")
environment["APPLE_SIGNING_IDENTITY"] = "-"
for name in ("APPLE_CERTIFICATE", "APPLE_CERTIFICATE_PASSWORD", "APPLE_ID",
             "APPLE_PASSWORD", "APPLE_TEAM_ID", "APPLE_API_KEY", "APPLE_API_ISSUER",
             "APPLE_API_KEY_PATH"):
    environment.pop(name, None)
result = subprocess.run([
    str(root / "node_modules/.bin/tauri"), "build", "--target", "aarch64-apple-darwin",
    "--bundles", "app,dmg", "--config", "src-tauri/tauri.release.conf.json",
    "--", "--locked", "--offline",
], cwd=root, env=environment)
sys.exit(result.returncode)
