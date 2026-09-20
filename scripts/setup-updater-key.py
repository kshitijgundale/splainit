"""Create a protected local Tauri updater key and backup; never print the secret."""

import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
KEY_DIR = Path.home() / ".config/splainit-release"
BACKUP_DIR = Path.home() / ".local/share/splainit-release-backup"


def main():
    os.umask(0o077)
    config_path = ROOT / "src-tauri/tauri.conf.json"
    config = json.loads(config_path.read_text())
    configured = config.get("plugins", {}).get("updater", {}).get("pubkey")
    key = KEY_DIR / "updater.key"
    public = KEY_DIR / "updater.key.pub"
    backup = BACKUP_DIR / key.name
    if any(path.is_symlink() for path in (key, public, backup)):
        raise ValueError("Refusing a symlink as a key file")
    for directory in (KEY_DIR, BACKUP_DIR):
        if directory.is_symlink():
            raise ValueError("Refusing a symlink as a key directory")
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        directory.chmod(0o700)
    if not key.exists():
        if configured or public.exists() or backup.exists():
            raise ValueError("A prior key exists. Restore it; do not silently rotate keys.")
        # A file destination suppresses private-key output. Capture all CLI output
        # anyway so a CLI behavior change cannot expose it in tool/CI logs.
        result = subprocess.run(
            [str(ROOT / "node_modules/.bin/tauri"), "signer", "generate",
             "--ci", "--write-keys", str(key)], cwd=ROOT,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if result.returncode:
            raise ValueError("Tauri key generation failed (output suppressed)")
    for path in (key, public):
        if path.is_symlink() or not path.is_file():
            raise ValueError("Expected regular key files")
        path.chmod(0o600)
    pubkey = public.read_text().strip()
    decoded = base64.b64decode(pubkey, validate=True).decode()
    if not decoded.startswith("untrusted comment: ") or len(decoded.splitlines()) != 2:
        raise ValueError("Unexpected Tauri public key format")
    if configured and configured != pubkey:
        raise ValueError("Existing embedded key differs. Explicit migration is required.")
    if backup.exists() or backup.is_symlink():
        if backup.is_symlink() or backup.read_bytes() != key.read_bytes():
            raise ValueError("Existing backup differs; refusing to overwrite it")
    else:
        with backup.open("xb") as target, key.open("rb") as source:
            shutil.copyfileobj(source, target)
    backup.chmod(0o600)
    if backup.read_bytes() != key.read_bytes():
        raise ValueError("Backup verification failed")
    updater = config.setdefault("plugins", {}).setdefault("updater", {})
    updater["pubkey"] = pubkey
    updater.setdefault("endpoints", [])
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"Public key embedded. Private key: {key}; protected local backup: {backup}")
    print("Both copies are on this Mac. Store an additional copy in an access-controlled off-device backup before publication.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError):
        print("Updater key setup failed; existing keys were not intentionally replaced. Inspect local paths; do not regenerate an established key.", file=sys.stderr)
        raise SystemExit(1)
