"""Explicit local/CI artifact test: reject tampered bytes and forged signatures."""
import base64
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
bundle = root / "src-tauri/target/aarch64-apple-darwin/release/bundle"
archive = bundle / "macos/Splainit.app.tar.gz"
signature = archive.with_suffix(".gz.sig")
subprocess.run([
    "cargo", "build", "--locked", "--offline", "--manifest-path", "src-tauri/Cargo.toml",
    "--example", "verify_update",
], cwd=root, check=True)
verifier = root / "src-tauri/target/debug/examples/verify_update"


def verify(path, sig, expected):
    result = subprocess.run([str(verifier), str(path), str(sig)], capture_output=True)
    if (result.returncode == 0) != expected:
        raise SystemExit("Unexpected signature verification result")


verify(archive, signature, True)
with tempfile.TemporaryDirectory(prefix="splainit-integrity-") as temporary:
    directory = Path(temporary)
    tampered = directory / archive.name
    shutil.copyfile(archive, tampered)
    with tampered.open("r+b") as stream:
        first = stream.read(1)
        stream.seek(0)
        stream.write(bytes([first[0] ^ 1]))
    verify(tampered, signature, False)
    forged = directory / "forged.sig"
    lines = base64.b64decode(signature.read_text().strip(), validate=True).decode().splitlines()
    raw_signature = bytearray(base64.b64decode(lines[1], validate=True))
    raw_signature[-1] ^= 1
    lines[1] = base64.b64encode(raw_signature).decode()
    forged.write_text(base64.b64encode(("\n".join(lines) + "\n").encode()).decode())
    verify(archive, forged, False)
    # Exercise Apple's resource seal too, without touching the actual bundle.
    app_copy = directory / "Splainit.app"
    shutil.copytree(bundle / "macos/Splainit.app", app_copy, symlinks=True)
    with (app_copy / "Contents/Info.plist").open("ab") as stream:
        stream.write(b"\n<!-- tampered -->\n")
    result = subprocess.run([
        "python3", "scripts/verify-macos-package.py", "--app", str(app_copy), "--app-only",
    ], cwd=root, capture_output=True)
    if result.returncode == 0:
        raise SystemExit("Tampered app was incorrectly accepted")
print("Release integrity passed: valid signature accepted; altered archive, forged signature, and altered app rejected.")
