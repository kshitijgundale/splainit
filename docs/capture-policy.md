# Selection capture and privacy policy

The capture resolver tries direct Accessibility selected text, selected range plus
string-for-range, isolated AX selection bounds plus local OCR, then an explicitly
requested “Drag to explain” region. Current capture source no longer reads or
modifies the general pasteboard or posts automated Copy. The first development
probe predates this change and is not evidence for the revised app matrix.

The Copy fallback was retired early for privacy and correctness. When semantic
attributes and safe visual recovery are unavailable, the app reports that state
or offers a user-drawn region; it does not recover stale clipboard content. This
removal changes unsupported-control behavior but does not migrate or delete old
history records. Focused resolver and OCR tests and a source-level no-pasteboard
check pass. The fresh-profile app matrix remains necessary before claiming broad
compatibility. Existing histories may still contain `automated_copy` as their
historical capture method; no new capture can produce that method.

Only unavailable providers may advance the resolver. A trustworthy empty range,
blocked source, missing permission, oversize result, timeout, cancellation, or
supersession ends the attempt. Empty selected text alone is not authoritative if
a nonempty range exists. Reads must remain bound to the original process, focused
window, and focused element; inactive-window selections are never substitutes.

Direct AX and range text are semantically verified only with consistent current
selection evidence. Both OCR methods always require review and explicit
confirmation, regardless of recognizer confidence. Confirmation preserves the
capture method and unverified evidence. Unknown confidence is `null`, not zero.

## Limits

These are conservative implementation budgets, not broad hardware or app
compatibility guarantees. A generated local Vision fixture on macOS 14.3/arm64
returned exact text in 219 ms. Application-specific latency and accuracy remain
unmeasured; record them in the development and final matrices.

| Operation | Limit |
| --- | --- |
| Individual AX message | 500 milliseconds, shortened to remaining deadline |
| Semantic capture and geometry processing | 2 seconds total |
| Image acquisition and local OCR | 3 seconds total |
| Automatic capture processing | 5 seconds total |
| Selected text | 12,000 UTF-16 code units, no truncation |
| Opted-in semantic context | 500 UTF-16 code units on each side |
| Image area before acquisition | 2,000,000 physical pixels total |
| Selection regions | At most 64 isolated line regions |

UTF-16 code units match NSString/AX ranges and JavaScript string lengths; a
supplementary Unicode character counts as two units. Rust uses `encode_utf16()`.
Context must not split surrogate pairs. Time spent drawing a region does not use
the processing budget; processing starts again after the explicit selection.
Cancellation and supersession are checked before each provider, before acquiring
pixels, after OCR, before publication, before transmission, and before history.

## Geometry and OCR

Use AX/Quartz global display points, with the main display's top-left origin and
positive y downward. Validate finite, positive bounds against the original source
window and visible display, applying that display's backing scale before enforcing
the pixel budget. Reject stale windows, overlapping unrelated windows, ambiguous
layouts, cross-display regions, and excessive areas before acquisition. Never
replace missing geometry with a whole-window or whole-display screenshot.

Automatic OCR uses isolated selected line regions, with selection endpoints
clipped to the selected range. If AX cannot establish those regions, offer the
explicit drag action rather than widening the capture. Explicit drags must stay
inside the validated source and pass the same exclusion/secure-field checks.
Unverifiable safety fails closed. No passive global mouse-drag monitoring exists.

Reconstruct OCR in top-to-bottom region order, then left-to-right order for equal
top coordinates. Within each region, sort recognized lines by their top edge,
then left edge; use original observation index for exact ties. Join lines with
newlines. This v1 rule targets horizontal text; columns, unusual writing direction,
and ambiguous layouts require review and are not claimed as verified selections.

Image buffers stay in native memory and are released on success, cancellation,
timeout, supersession, or failure. They must never enter files, logs, history,
webview IPC, or network payloads. The native explanation boundary accepts text
only. Screenshot upload requires an explicit future change to this policy.

## Permissions, context, and persistence

Accessibility supports semantic capture. First launch and successful AX-only use
must not request Screen Recording. Only an eligible visual path or the user's
explicit visual-enablement action may request it. Permission-required results name
Accessibility or Screen Recording; denial must leave otherwise permitted AX paths
usable. A permission grant never authorizes continuous capture or upload.

Semantic context is off by default. When opted in, it comes only from the same
semantic text provider and reliable selected range, within the limits above.
Selected-region OCR and Screen Recording consent do not authorize surrounding
screen OCR. Surrounding visual context is disabled in v1. Preset changes and
retries reuse the frozen text/context/provenance snapshot without recapture.

Only successful explanations may be saved, with exact transmitted text/context
and actual capture method. Existing settings and history must survive upgrades.
Credentials stay in Keychain for product use; screenshots and credentials never
enter history. Neither selected text nor model replies are logged.
