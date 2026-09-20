"""Verify the local ad-hoc arm64 package; does not launch or install the app."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest(app):
    """Compare sealed files, executable bits, directories, and symlink targets."""
    entries = {}
    for path in sorted(app.rglob("*")):
        relative = str(path.relative_to(app))
        if path.is_symlink():
            entries[relative] = ["symlink", os.readlink(path)]
        elif path.is_file():
            entries[relative] = ["file", path.stat().st_mode & 0o777, sha256(path)]
        elif path.is_dir():
            entries[relative] = ["directory"]
        else:
            raise ValueError(f"Unexpected package entry: {relative}")
    return entries


def verify_app(app, config):
    require(app.is_dir() and not app.is_symlink(), "Expected an app directory")
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info.get("CFBundleIdentifier") == config["identifier"], "Wrong app identity")
    require(info.get("CFBundleShortVersionString") == config["version"], "Wrong app version")
    require(info.get("CFBundlePackageType") == "APPL", "Wrong bundle type")
    require(info.get("LSMinimumSystemVersion") == "14.0", "Wrong minimum macOS target")
    executable = info.get("CFBundleExecutable", "")
    require(executable and Path(executable).name == executable, "Invalid executable name")
    binary = app / "Contents/MacOS" / executable
    require(binary.is_file() and os.access(binary, os.X_OK), "Missing app executable")
    require(run("lipo", "-archs", str(binary)).decode().strip() == "arm64", "Expected arm64 only")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    signature = subprocess.run(
        ["codesign", "--display", "--verbose=4", str(app)],
        check=True, capture_output=True, text=True,
    ).stderr.splitlines()
    require("Signature=adhoc" in signature, "Expected an ad-hoc signature")
    require(f"Identifier={config['identifier']}" in signature, "Wrong signing identity")
    require((app / "Contents/_CodeSignature/CodeResources").is_file(), "Missing resource seal")
    return {
        "identifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "architecture": "arm64",
        "minimum_macos_target": info["LSMinimumSystemVersion"],
        "signature": "adhoc",
        "executable_sha256": sha256(binary),
    }


def verify_dmg(dmg, app, config):
    require(dmg.is_file(), "Missing DMG")
    run("hdiutil", "verify", str(dmg))
    with tempfile.TemporaryDirectory(prefix="splainit-package-") as directory:
        mount = Path(directory) / "volume"
        attached = False
        try:
            run("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen",
                "-mountpoint", str(mount), str(dmg))
            attached = True
            applications = mount / "Applications"
            require(applications.is_symlink() and os.readlink(applications) == "/Applications",
                    "DMG must contain the /Applications installation link")
            bundled = mount / app.name
            verify_app(bundled, config)
            require(manifest(app) == manifest(bundled), "DMG app differs from the verified build")
            allowed = {app.name, "Applications", ".background", ".DS_Store",
                       ".VolumeIcon.icns", ".fseventsd", ".Trashes"}
            contents = sorted(path.name for path in mount.iterdir())
            require(set(contents) <= allowed, f"Unexpected DMG contents: {contents}")
        finally:
            if attached:
                run("hdiutil", "detach", str(mount))
    return {"file": dmg.name, "sha256": sha256(dmg), "contents": contents}


def main():
    config = json.loads((ROOT / "src-tauri/tauri.conf.json").read_text())
    bundle = ROOT / "src-tauri/target/aarch64-apple-darwin/release/bundle"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=bundle / "macos/Splainit.app")
    parser.add_argument("--dmg", type=Path,
                        default=bundle / f"dmg/Splainit_{config['version']}_aarch64.dmg")
    parser.add_argument("--app-only", action="store_true", help="Skip DMG checks")
    args = parser.parse_args()
    report = {"app": verify_app(args.app, config)}
    if not args.app_only:
        report["dmg"] = verify_dmg(args.dmg, args.app, config)
        checksum = args.dmg.with_suffix(".dmg.sha256")
        checksum.write_text(f"{report['dmg']['sha256']}  {args.dmg.name}\n")
        report["checksum_file"] = str(checksum)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Package verification failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode() if isinstance(error.stderr, bytes) else error.stderr,
                  file=sys.stderr)
        raise SystemExit(1)
