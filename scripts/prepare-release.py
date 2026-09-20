"""Verify and stage only public release assets; require a configured GitHub host."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="GitHub owner/repository")
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", args.repository):
        raise SystemExit("Expected a GitHub owner/repository")
    config = json.loads((ROOT / "src-tauri/tauri.conf.json").read_text())
    version = config["version"]
    if args.tag != f"v{version}" or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Stable release tag must match the configured app version")
    endpoint = f"https://github.com/{args.repository}/releases/latest/download/latest.json"
    if config["plugins"]["updater"]["endpoints"] != [endpoint]:
        raise SystemExit("Embedded endpoint does not match the release repository; configure and rebuild first")
    bundle = ROOT / "src-tauri/target/aarch64-apple-darwin/release/bundle"
    dmg = bundle / f"dmg/Splainit_{version}_aarch64.dmg"
    archive = bundle / "macos/Splainit.app.tar.gz"
    signature = archive.with_suffix(".gz.sig")
    subprocess.run(["python3", "scripts/verify-macos-package.py"], cwd=ROOT, check=True)
    subprocess.run([
        "cargo", "run", "--locked", "--offline", "--manifest-path", "src-tauri/Cargo.toml",
        "--example", "verify_update", "--", str(archive), str(signature),
    ], cwd=ROOT, check=True)
    with tarfile.open(archive, "r:gz") as tar:
        candidates = [entry for entry in tar.getmembers()
                      if entry.name.lstrip("./") == "Splainit.app/Contents/Info.plist"]
        if len(candidates) != 1 or not candidates[0].isfile():
            raise SystemExit("Updater archive must contain exactly one app Info.plist")
        with tar.extractfile(candidates[0]) as stream:
            info = plistlib.load(stream)
        if (info.get("CFBundleIdentifier") != config["identifier"]
                or info.get("CFBundleShortVersionString") != version):
            raise SystemExit("Updater artifact identity/version does not match this release")
    destination = ROOT / "src-tauri/target/release-assets" / args.tag
    destination.mkdir(parents=True, exist_ok=True)
    assets = [dmg, dmg.with_suffix(".dmg.sha256"), archive, signature]
    expected = {path.name for path in assets} | {"latest.json", "SHA256SUMS"}
    if any(path.name not in expected or path.is_symlink() for path in destination.iterdir()):
        raise SystemExit("Unexpected existing release assets; use a clean staging directory")
    for source in assets:
        shutil.copyfile(source, destination / source.name)
    metadata = {
        "version": version,
        "notes": f"Splainit {version}. See the release notes and installation instructions.",
        "pub_date": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "platforms": {"darwin-aarch64": {
            "url": f"https://github.com/{args.repository}/releases/download/{args.tag}/{archive.name}",
            "signature": signature.read_text().strip(),
        }},
    }
    (destination / "latest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    checksums = [f"{digest(path)}  {path.name}\n" for path in sorted(destination.iterdir())
                 if path.name != "SHA256SUMS"]
    (destination / "SHA256SUMS").write_text("".join(checksums))
    print(f"Verified release assets staged in {destination}")


if __name__ == "__main__":
    main()
