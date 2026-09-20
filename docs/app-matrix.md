# Supported-app capture matrix

The 2026-09-19 TextEdit result below is a development probe of the old AX path.
It is not validation of the current resolver. On 2026-09-20 the current app
bundle built, and a user reported seeing its window. Automation still returned
zero TextEdit windows, and no current-app capture was recorded. A generated local
image passed a Vision OCR smoke test in 219 ms on macOS 14.3/arm64; that test
does not establish screenshot acquisition, AX geometry, or target-app accuracy.

Run the development matrix with the bundled current app on the local development
profile. Keep the API key absent for capture trials. Use known fixtures, record
exact expected and actual text, and repeat an empty-selection case in every
control. Record direct AX, range, bounds OCR, and explicit drag when the control
offers them; write `unavailable` where a path cannot be exercised. OCR must show
unverified provenance and require confirmation. A failed test is evidence, not a
reason to infer a different path works.

| App and control | Exact expected / actual text | Empty selection and false positives | Method; verification / OCR confidence | Latency | Permissions and confirmation | Development result |
| --- | --- | --- | --- | --- | --- | --- |
| Safari page text | Pending / pending | Pending | Pending | Pending | Pending | Not run |
| Chrome page text | Pending / pending | Pending | Pending | Pending | Pending | Not run |
| TextEdit document | `Splainit feasibility selection probe` / same in **old** 2026-09-19 probe | Pending | Old direct AX; verified / not applicable | Not recorded | Accessibility; no confirmation | New resolver not run |
| Notes note body | Pending / pending | Pending | Pending | Pending | Pending | Not run |
| Preview selectable-text PDF | Pending / pending | Pending | Pending | Pending | Pending | Not run |
| VS Code editor text | Pending / pending | Pending | Pending | Pending | Pending | Not run |

The final acceptance matrix must be one separate run on a **fresh macOS user
profile** after all clipboard-free paths are implemented and development issues
are resolved. The user confirmed on 2026-09-19 that such a profile is not yet
available. For that run, use the same columns and exact fixtures plus secure
fields, Accessibility and Screen Recording denial, long selections, selectable
PDFs, shortcut conflicts, and panel visibility/positioning. Note unsupported
controls and narrow public claims to measured behavior.
