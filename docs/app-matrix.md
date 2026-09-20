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

On 2026-09-20, all six target applications were found installed on this macOS
14.3 development machine. After installing the verified local release DMG into
`/Applications`, a native Accessibility harness selected exactly the first line
of a harmless TextEdit fixture and posted the configured shortcut. Splainit's
panel appeared, but returned `permission_required` with detail `Accessibility
access is disabled`; no text or capture method was returned. The macOS
Accessibility page showed Splainit enabled, and TCC diagnostics listed the
installed bundle as allowed, but the running app still reported denied after a
restart. This contradiction remains unresolved. The harness observed the panel
after an intentional 2-second wait, so capture latency was not measured; the
panel was present within about 2.1 seconds. System Events separately returned
`osascript is not allowed assistive access (-25211)` despite its enabled entry.
The other five target apps and every empty-selection case remain untested.

| App and control | Exact expected / actual text | Empty selection and false positives | Method; verification / OCR confidence | Latency | Permissions and confirmation | Development result |
| --- | --- | --- | --- | --- | --- | --- |
| Safari page text | Pending / pending | Pending | Pending | Pending | Pending | Not run |
| Chrome page text | Pending / pending | Pending | Pending | Pending | Pending | Not run |
| TextEdit document | `Splainit matrix TextEdit selection 24A.` / no app text returned; harness confirmed exact source selection | Not run; false positives unknown | No method; `permission_required` / confidence not applicable. Old 2026-09-19 direct-AX probe passed before the current resolver. | Not measured; panel present within about 2.1 s including fixed wait | App reported Accessibility denied; no confirmation or network request | Current installed release build blocked on permission check |
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
