# macOS capture feasibility (2026-09-19)

## Result

On macOS 14.3, arm64, the unsigned Tauri 2 development app registered Control-Option-K. A controlled TextEdit document contained `Splainit feasibility selection probe`; after selecting all text and sending the shortcut, the native trace reported:

```
shortcut event: ALT | CONTROL + KeyK, Pressed
capture started: source=TextEdit
capture finished: status=verified chars=36
capture window dispatch running
capture window visible=Ok(true)
```

The source application was snapshotted synchronously in the shortcut handler. The AX selection was read on a worker, and only then was the Tauri window's `show` call dispatched to AppKit's main thread. This proves the ordering and the AX path for this one TextEdit control. It does not establish compatibility with the other planned applications or empty selections.

## Window observation to resolve

Tauri returned `is_visible = true` after `show`, but System Events reported zero windows for the raw development process. A local screenshot contained only the desktop wallpaper, which may reflect screen-capture permission or the automation session rather than the actual user-visible screen. A debug `.app` bundle was built and launched, but System Events then returned `osascript is not allowed assistive access (-25211)`, preventing an external window check. Before treating the panel as release-ready, verify the bundled app in an interactive user session and record whether its window visibly opens and receives focus after capture. If it does not, investigate Tauri window activation and a small AppKit adapter or revisit the native shell decision.

The test did not send selected text to a provider or write it to history. Development logs recorded status, source application name, and character count; they did not record the selected text.
