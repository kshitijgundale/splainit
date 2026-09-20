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

On 2026-09-20, all six target applications were installed on this macOS 14.3
development machine. The verified local release DMG was installed in
`/Applications`. Its first capture attempts returned `permission_required`
despite an enabled Accessibility toggle. macOS TCC logs showed that the stored
code requirement expected an older ad-hoc build hash (`b4c88fb5...`), while
the installed app's hash was `1dc3cbbe...`. Resetting **only** Splainit's stale
Accessibility entry with `tccutil reset Accessibility app.splainit.desktop`,
enabling the newly registered installed app, and restarting it resolved the
denial. This is development troubleshooting, not an install step or evidence
that permissions survive an update. System Events UI scripting separately
returned `osascript is not allowed assistive access (-25211)` despite its
enabled entry, so the trials used a native Accessibility harness.

The harness set an exact TextEdit selected range, dragged over the exact Preview
PDF line, attempted Safari page selection by both Command-A and dragging, and
selected a Safari textarea. For Chrome and VS Code it clicked the local fixture
window and sent Command-A; their selected text could not be independently
verified through AX. It then posted Control-Option-K and polled Splainit's panel
every 10 ms. Latencies below are elapsed time to the observed panel state,
including polling overhead; they are not internal capture timings. No API key
was configured, so verified text stopped at the settings prompt. No OCR result
or confirmation was observed. Initial Chrome/VS Code trials occurred after
Splainit had exited cleanly and were discarded; the recorded no-panel retries
were run while its process was confirmed alive.

A subsequent manual Control-Option-K attempt in VS Code displayed
`Capture blocked in Code: Cannot establish the focused source element`.
This confirms the shortcut reached Splainit, but no text was captured: the
native provider could not establish the focused editor element before its
secure-field and source-window checks. An isolated VS Code profile with
`editor.accessibilitySupport` set to `on` started without an AX-visible
window, so that setting's effect on capture remains unmeasured. The user's
normal VS Code settings were not changed.

| App and control | Exact expected / actual text | Empty selection and false positives | Method; verification / OCR confidence | Latency | Permissions and confirmation | Development result |
| --- | --- | --- | --- | --- | --- | --- |
| Safari page text | `Splainit matrix Safari selection 24B.` / no text returned after Command-A or drag | Blank-page click returned `unavailable` in 105 ms; no false text | No capture method; status `unavailable`; verification/confidence not applicable | 98–100 ms for drag-selected attempt | Accessibility granted; visual action was not exposed; no confirmation | Semantic page selection unavailable in this control |
| Safari textarea | `Splainit matrix Safari text field 24G.` / exact match | Source range was cleared through AX, but no subsequent panel appeared; empty outcome unmeasured | `ax_selected_text`; semantically verified; OCR confidence not applicable | 491 ms selected | Accessibility granted; no confirmation needed | Textarea direct AX passes; empty trial inconclusive |
| Chrome page text | `Splainit matrix Chrome selection 24C.` / no panel result; source selection not independently verified | Unavailable: no panel under automated shortcut; false positives unknown | Method/verification/confidence unavailable | Not measurable | Accessibility granted to Splainit; no permission result observed | Default Chrome AX tree did not expose the local page text; manual shortcut check pending |
| TextEdit document | `Splainit matrix TextEdit selection 24A.` / exact match | Zero-length AX range returned `no_selection` in 155 ms; no false text | `ax_selected_text`; semantically verified; OCR confidence not applicable | 171 ms selected | Accessibility granted; no confirmation needed | Direct AX selected and empty cases pass |
| Notes note body | `Splainit matrix Notes selection 24D.` / no fixture or app result | Unavailable: no Notes account exists on this profile | Method/verification/confidence unavailable | Not measurable | Account setup required; Accessibility path not exercised | Temporary note creation failed before writing; zero matching notes remained |
| Preview selectable-text PDF | `Splainit matrix Preview selection 24E.` / exact match | Blank-page click cleared source AX text; app returned `unavailable` in 100 ms, with no false text | `ax_selected_text`; semantically verified; OCR confidence not applicable | 133 ms selected | Accessibility granted; no confirmation needed | Selectable PDF direct AX passes; empty state is unavailable rather than `no_selection` |
| VS Code editor text | Fixture begins `Splainit matrix VS Code selection 24F.` / no text captured; source selection not independently verified | Empty selection untested; false positives unknown | No capture method; status `blocked`; verification/confidence not applicable | Not measured for manual attempt | Accessibility granted to Splainit; no visual action because focused source element was unavailable | Automated attempt showed no panel; manual shortcut displayed `Capture blocked in Code: Cannot establish the focused source element`. Editor AX tree exposed no text node |

AX-range fallback, AX-bounds OCR, and explicit-drag OCR were not produced by any
of these controls. Safari's `unavailable` result did not expose a Drag to explain
button, so its visual path was unavailable in this run. These paths require a
separate eligible control or a controlled provider fixture before claiming
development coverage. No selected-text OCR result may be inferred from the
local Vision fixture test above.

The final acceptance matrix must be one separate run on a **fresh macOS user
profile** after all clipboard-free paths are implemented and development issues
are resolved. The user confirmed on 2026-09-19 that such a profile is not yet
available. For that run, use the same columns and exact fixtures plus secure
fields, Accessibility and Screen Recording denial, long selections, selectable
PDFs, shortcut conflicts, and panel visibility/positioning. Note unsupported
controls and narrow public claims to measured behavior.
