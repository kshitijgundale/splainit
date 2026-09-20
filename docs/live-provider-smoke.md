# Explicit native live-provider smoke test

Normal `npm test` / `cargo test` runs never require a key or contact OpenAI. The
separate developer example uses the same `openai::explain` transport as the app:
native Responses API, `store: false`, no tools, 700 output tokens, a 30-second
request deadline, and the configured default in `src-tauri/default-model.txt`.
It does not read a user's model override or silently try another model.

The exact default is **`gpt-4.1-mini`**. OpenAI lists Responses as a supported
endpoint in the [official model documentation](https://developers.openai.com/api/docs/models/gpt-4.1-mini).
That documentation does not establish this machine's account access or quota.

From the project root, in your local terminal:

```sh
python3 scripts/live-provider-smoke.py
```

The script builds the developer-only example, then reads one key with a hidden
terminal prompt and passes it over stdin. Never put a key in command arguments,
source, a shell history entry, or test output. It uses neither Keychain nor app
preferences/history. The native client clears its input key buffer after creating
the request; the HTTP authorization header necessarily holds it until the request
is dropped. The Python launcher drops its temporary immutable string references
after the child exits. No test credentials are persisted.

The fixed input is `A triangle is a shape with three straight sides.` with Explain
Simply and empty context. Successful transport prints the exact requested model,
elapsed milliseconds, and the harmless fixture reply for manual review. Record a
pass only if the response is nonempty, complete, relevant, and accurately explains
the triangle. Preserve the requested model, date, platform, latency, and reviewed
result in this document, without any credentials. Invalid-model, access, quota,
network, incomplete, and empty responses fail the command. A successful build or
mocked test does not satisfy this live check.

## Evidence

- 2026-09-19: live request **not run**. The user confirmed no locally supplied key
  has been established. Tasks 3.7 and 1.3 remain open.
- Current development platform: macOS 14.3 (`23D2057`), arm64. No macOS 14.0 runtime
  or fresh-profile acceptance evidence is available.

The example is behind `--features live-provider-smoke` and also requires `--live`.
Normal CI must not set this feature or invoke the script.
