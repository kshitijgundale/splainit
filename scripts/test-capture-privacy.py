"""Verify capture has no general pasteboard or automated Copy dependency."""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
sources = [
    root / "src-tauri/src/lib.rs",
    root / "src-tauri/src/capture.rs",
    *sorted((root / "src-tauri/src/macos").glob("*.m")),
    *sorted((root / "src-tauri/src/macos").glob("*.h")),
]
forbidden = re.compile(
    r"NSPasteboard|generalPasteboard|pasteboardItems|changeCount|"
    r"CGEventPost|splainit_copy_capture|splainit_clipboard_changed|"
    r"splainit_clipboard_stable|automated_copy",
    re.IGNORECASE,
)
violations = [str(path.relative_to(root)) for path in sources if forbidden.search(path.read_text())]
if violations:
    raise SystemExit("Clipboard capture references remain in: " + ", ".join(violations))
print("Capture privacy check passed: no pasteboard access or automated Copy in shipped capture sources.")
