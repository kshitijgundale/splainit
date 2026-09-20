"""Explicit local smoke test; never invoked by normal tests or CI."""
import getpass
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
# Compile before asking for a credential, minimizing its lifetime in memory.
subprocess.run([
    "cargo", "build", "--offline", "--manifest-path", "src-tauri/Cargo.toml",
    "--example", "live_provider_smoke", "--features", "live-provider-smoke",
], cwd=root, check=True)
key = getpass.getpass("OpenAI key for one harmless live request (hidden): ")
try:
    result = subprocess.run([
        str(root / "src-tauri/target/debug/examples/live_provider_smoke"), "--live",
    ], input=key + "\n", text=True, cwd=root)
finally:
    # Python strings are immutable; drop the reference promptly, never persist it.
    del key
raise SystemExit(result.returncode)
