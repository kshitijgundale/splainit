import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import "./style.css";

import { canExplain, captureProvenance, permissionMessage, type Capture } from "./capture-ui";

type PresetId = "explain_simply" | "go_deeper" | "define_key_terms";
type Explanation = { invocation: number; preset_id: PresetId; preset_version: number; model: string; response: string; history_saved: boolean };
type HistoryRecord = {
  id: number; created_at_ms: number; source_app: string; bundle_id: string; capture_method: string;
  selected_text: string; context_before: string; context_after: string; preset_id: string;
  preset_version: number; prompt_text: string; model_id: string; reply: string;
};

const app = document.querySelector<HTMLElement>("#app")!;
const settingsView = new URLSearchParams(location.search).get("view") === "settings";
document.body.dataset.view = settingsView ? "settings" : "panel";
app.innerHTML = `
  <header><h1>${settingsView ? "Splainit Settings" : "Splainit"}</h1><button id="dismiss" type="button" aria-label="Close window">Close</button></header>
  <section id="onboarding">
    <p>Press Control-Option-K after selecting text in another app. Splainit needs macOS Accessibility access to read that selection.</p>
    <p id="accessibility-status">Checking Accessibility access…</p>
    <button id="request-accessibility" type="button">Open Accessibility permission prompt</button>
    <p>Verified selections are sent to OpenAI automatically for an explanation. Text recovered by local OCR requires your review and confirmation. Screen Recording is requested only if visual capture is needed; captured images stay in memory on this Mac. API usage is billed to your OpenAI account.</p>
  </section>
  <p class="hint">Select text in another app and press your global shortcut.</p>
  <p id="status">Waiting for a selection.</p>
  <p id="provenance"></p>
  <pre id="selection"></pre>
  <button id="permission-recovery" type="button" hidden>Review required permission</button>
  <p id="context-note"></p>
  <button id="drag" type="button" hidden>Drag to explain</button>
  <button id="confirm" type="button" hidden>Confirm text and explain</button>
  <div id="presets" hidden>
    <button type="button" data-preset="explain_simply">Explain Simply</button>
    <button type="button" data-preset="go_deeper">Go Deeper</button>
    <button type="button" data-preset="define_key_terms">Define Key Terms</button>
  </div>
  <p id="answer-status" aria-live="polite"></p>
  <button id="retry" type="button" hidden>Retry explanation</button>
  <pre id="answer"></pre>
  <button id="open-settings" type="button">Open settings</button>
  <details id="settings"><summary>Settings</summary>
  <p>Shortcut (initially <kbd>Control</kbd> + <kbd>Option</kbd> + <kbd>K</kbd>)</p>
  <p id="shortcut"></p>
  <form id="shortcut-form">
    <label for="shortcut-value">Shortcut</label>
    <input id="shortcut-value" name="shortcut" value="Ctrl+Alt+K" autocomplete="off" spellcheck="false" />
    <button type="submit">Set shortcut</button>
  </form>
  <form id="exclusions-form">
    <label for="excluded-apps">Excluded app bundle IDs (one per line)</label>
    <textarea id="excluded-apps" rows="2" spellcheck="false"></textarea>
    <button type="submit">Save exclusions</button>
  </form>
  <p id="exclusions-status"></p>
  <label class="context-setting"><input id="context-enabled" type="checkbox" /> Include semantic text before and after a selection (up to 500 UTF-16 units each; never surrounding-screen OCR)</label>
  <section aria-labelledby="key-heading">
    <h2 id="key-heading">OpenAI API key</h2>
    <p>Explanations use your OpenAI account and may incur provider charges. Selected text is sent to OpenAI when you request an explanation.</p>
    <p id="key-status">Checking Keychain…</p>
    <form id="key-form">
      <label for="api-key">API key</label>
      <input id="api-key" type="password" autocomplete="off" spellcheck="false" />
      <button type="submit">Save or replace</button>
      <button id="remove-key" type="button">Remove</button>
    </form>
  </section>
  <form id="model-form">
    <label for="model">OpenAI model ID</label>
    <input id="model" spellcheck="false" autocomplete="off" />
    <button type="submit">Save model</button>
  </form>
  <p id="model-status"></p>
  <section aria-labelledby="updates-heading">
    <h2 id="updates-heading">App updates</h2>
    <button id="check-updates" type="button">Check for updates</button>
    <button id="install-update" type="button" hidden>Install and restart</button>
    <p id="update-status" aria-live="polite"></p>
  </section>
  </details>
  <details id="history-view"><summary>Local history</summary>
    <label><input id="history-enabled" type="checkbox" /> Save new explanations</label>
    <div class="history-tools">
      <input id="history-search" type="search" placeholder="Search history" aria-label="Search history" />
      <button id="clear-history" type="button">Clear all</button>
    </div>
    <p id="history-status"></p>
    <ul id="history-list"></ul>
    <button id="history-more" type="button" hidden>Load more</button>
  </details>
`;
const status = document.querySelector<HTMLElement>("#status")!;
const selection = document.querySelector<HTMLElement>("#selection")!;
let currentInvocation = 0;
let currentCapture: Capture | null = null;
let confirmed = false;
let requestSerial = 0;
const answerStatus = document.querySelector<HTMLElement>("#answer-status")!;
const answer = document.querySelector<HTMLElement>("#answer")!;
const retry = document.querySelector<HTMLButtonElement>("#retry")!;
const confirmButton = document.querySelector<HTMLButtonElement>("#confirm")!;
const presets = document.querySelector<HTMLElement>("#presets")!;
let chosenPreset: PresetId = "explain_simply";

async function explain(presetId: PresetId) {
  if (!currentCapture || !canExplain(currentCapture, confirmed)) return;
  chosenPreset = presetId;
  const serial = ++requestSerial;
  retry.hidden = true;
  answerStatus.textContent = `Requesting ${presetId.replaceAll("_", " ")}…`;
  answer.textContent = "";
  try {
    const result = await invoke<Explanation>("explain_capture", {
      invocation: currentCapture.invocation,
      presetId,
      confirmed,
    });
    if (serial !== requestSerial || result.invocation !== currentInvocation) return;
    answerStatus.textContent = `${result.model} · ${presetId.replaceAll("_", " ")}`;
    answer.textContent = result.response;
    if (!result.history_saved) answerStatus.textContent += " · History not saved";
  } catch (error) {
    if (serial !== requestSerial) return;
    answerStatus.textContent = String(error);
    retry.hidden = false;
    if (String(error).includes("API key")) {
      void invoke<void>("show_settings");
    }
  }
}

function render(result: Capture) {
  if (result.invocation < currentInvocation || (result.invocation === currentInvocation && result.revision <= (currentCapture?.revision ?? -1))) return;
  currentInvocation = result.invocation;
  currentCapture = result;
  confirmed = false;
  requestSerial++;
  answerStatus.textContent = "";
  retry.hidden = true;
  answer.textContent = "";
  const appName = result.source_app || "the source app";
  const labels: Record<Capture["status"], string> = {
    verified: `Verified selection from ${appName}`,
    unverified: `Unverified text from ${appName}; review it before sending`,
    no_selection: `No selection in ${appName}`,
    permission_required: permissionMessage(result),
    blocked: `Capture blocked in ${appName}`,
    unavailable: `Selection unavailable in ${appName}`,
    oversized: "Selection is too long. Select at most 12,000 UTF-16 code units.",
    timed_out: `Selection timed out in ${appName}`,
    cancelled: "Capture cancelled",
    failed: "Capture failed",
  };
  status.textContent = `${labels[result.status]}${result.detail ? `: ${result.detail}` : ""}`;
  selection.textContent = result.text ?? "";
  document.querySelector<HTMLElement>("#provenance")!.textContent = captureProvenance(result);
  document.querySelector<HTMLButtonElement>("#permission-recovery")!.hidden = result.status !== "permission_required";
  document.querySelector<HTMLElement>("#context-note")!.textContent =
    result.context_before || result.context_after ? "Surrounding context will also be sent to OpenAI." : "";
  document.querySelector<HTMLButtonElement>("#drag")!.hidden = result.status !== "unavailable" || !result.visual_available;
  confirmButton.hidden = result.status !== "unverified";
  presets.hidden = result.status !== "verified" && result.status !== "unverified";
  if (canExplain(result, false)) void explain("explain_simply");
}

document.querySelector<HTMLButtonElement>("#drag")!.addEventListener("click", async event => {
  if (!currentCapture || currentCapture.status !== "unavailable" || !currentCapture.visual_available) return;
  const button = event.currentTarget as HTMLButtonElement;
  button.disabled = true;
  try { render(await invoke<Capture>("drag_capture", { invocation: currentCapture.invocation })); }
  catch (error) { answerStatus.textContent = String(error); }
  finally { button.disabled = false; }
});

confirmButton.addEventListener("click", () => {
  if (!currentCapture || currentCapture.status !== "unverified") return;
  confirmed = true;
  confirmButton.hidden = true;
  void explain("explain_simply");
});
presets.addEventListener("click", event => {
  const target = event.target as HTMLElement;
  const presetId = target.dataset.preset as PresetId | undefined;
  if (presetId) void explain(presetId);
});
document.querySelector<HTMLButtonElement>("#dismiss")!.addEventListener("click", () => {
  requestSerial++;
  void invoke<void>(settingsView ? "hide_current_window" : "dismiss_panel");
});
document.querySelector<HTMLButtonElement>("#open-settings")!.addEventListener("click", () => {
  void invoke<void>("show_settings");
});
document.querySelector<HTMLButtonElement>("#permission-recovery")!.addEventListener("click", () => {
  if (!currentCapture || currentCapture.status !== "permission_required") return;
  void invoke<boolean>("recover_capture_permission", { invocation: currentCapture.invocation }).then(
    granted => { answerStatus.textContent = granted
      ? "Permission granted. Return to the source, select text, and press the shortcut again."
      : "Enable Splainit in Privacy & Security, then return to the source and try the shortcut again. You may need to restart Splainit."; },
    error => { answerStatus.textContent = String(error); },
  );
});
retry.addEventListener("click", () => { void explain(chosenPreset); });

if (!settingsView) {
  void listen<Capture>("capture", event => render(event.payload));
  void invoke<Capture | null>("latest_capture").then(value => { if (value) render(value); });
} else {
  document.querySelector<HTMLDetailsElement>("#settings")!.open = true;
  document.querySelector<HTMLDetailsElement>("#history-view")!.open = true;
}
if (settingsView) {
const checkUpdates = document.querySelector<HTMLButtonElement>("#check-updates")!;
const installUpdate = document.querySelector<HTMLButtonElement>("#install-update")!;
const updateStatus = document.querySelector<HTMLElement>("#update-status")!;
let availableVersion: string | null = null;
checkUpdates.addEventListener("click", async () => {
  checkUpdates.disabled = true;
  installUpdate.hidden = true;
  availableVersion = null;
  updateStatus.textContent = "Checking for updates…";
  try {
    const update = await invoke<{ version: string } | null>("check_for_updates");
    availableVersion = update?.version ?? null;
    updateStatus.textContent = update ? `Version ${update.version} is available.` : "You’re up to date.";
    installUpdate.hidden = !update;
    if (update) installUpdate.textContent = `Install ${update.version} and restart`;
  } catch (error) { updateStatus.textContent = String(error); }
  finally { checkUpdates.disabled = false; }
});
installUpdate.addEventListener("click", async () => {
  if (!availableVersion) return;
  checkUpdates.disabled = true;
  installUpdate.disabled = true;
  updateStatus.textContent = "Downloading and verifying update. Splainit will restart after installation…";
  try { await invoke<void>("install_update", { version: availableVersion }); }
  catch (error) {
    updateStatus.textContent = String(error);
    availableVersion = null;
    installUpdate.hidden = true;
  } finally {
    checkUpdates.disabled = false;
    installUpdate.disabled = false;
  }
});
void invoke<string>("shortcut_status").then(
  value => { document.querySelector<HTMLElement>("#shortcut")!.textContent = value; },
  error => { document.querySelector<HTMLElement>("#shortcut")!.textContent = String(error); },
);
void invoke<string>("current_shortcut").then(value => {
  document.querySelector<HTMLInputElement>("#shortcut-value")!.value = value;
});
document.querySelector<HTMLFormElement>("#shortcut-form")!.addEventListener("submit", event => {
  event.preventDefault();
  const input = document.querySelector<HTMLInputElement>("#shortcut-value")!;
  const message = document.querySelector<HTMLElement>("#shortcut")!;
  void invoke<string>("set_shortcut", { value: input.value.trim() }).then(
    value => { message.textContent = value; },
    error => { message.textContent = String(error); },
  );
});
void invoke<string[]>("get_excluded_apps").then(apps => {
  document.querySelector<HTMLTextAreaElement>("#excluded-apps")!.value = apps.join("\n");
});
document.querySelector<HTMLFormElement>("#exclusions-form")!.addEventListener("submit", event => {
  event.preventDefault();
  const input = document.querySelector<HTMLTextAreaElement>("#excluded-apps")!;
  const apps = input.value.split(/\r?\n/).map(value => value.trim()).filter(Boolean);
  const message = document.querySelector<HTMLElement>("#exclusions-status")!;
  void invoke<void>("set_excluded_apps", { apps }).then(
    () => { message.textContent = "Exclusions saved"; },
    error => { message.textContent = String(error); },
  );
});
const contextToggle = document.querySelector<HTMLInputElement>("#context-enabled")!;
void invoke<boolean>("context_enabled").then(enabled => { contextToggle.checked = enabled; });
contextToggle.addEventListener("change", () => {
  void invoke<void>("set_context_enabled", { enabled: contextToggle.checked });
});
const keyStatus = document.querySelector<HTMLElement>("#key-status")!;
const keyInput = document.querySelector<HTMLInputElement>("#api-key")!;
void invoke<boolean>("api_key_configured").then(configured => {
  keyStatus.textContent = configured ? "API key configured in Keychain" : "No API key configured";
});
const accessibilityStatus = document.querySelector<HTMLElement>("#accessibility-status")!;
function refreshAccessibility() {
  void invoke<boolean>("accessibility_granted").then(granted => {
    accessibilityStatus.textContent = granted ? "Accessibility access granted" : "Accessibility access needed: System Settings → Privacy & Security → Accessibility → enable Splainit.";
  });
}
refreshAccessibility();
document.querySelector<HTMLButtonElement>("#request-accessibility")!.addEventListener("click", () => {
  void invoke<boolean>("request_accessibility").then(refreshAccessibility);
});
document.querySelector<HTMLFormElement>("#key-form")!.addEventListener("submit", event => {
  event.preventDefault();
  void invoke<void>("save_api_key", { value: keyInput.value }).then(
    () => { keyInput.value = ""; keyStatus.textContent = "API key configured in Keychain"; },
    error => { keyStatus.textContent = String(error); },
  );
});
document.querySelector<HTMLButtonElement>("#remove-key")!.addEventListener("click", () => {
  void invoke<void>("remove_api_key").then(
    () => { keyInput.value = ""; keyStatus.textContent = "No API key configured"; },
    error => { keyStatus.textContent = String(error); },
  );
});
const modelInput = document.querySelector<HTMLInputElement>("#model")!;
void invoke<string>("get_model").then(model => { modelInput.value = model; });
document.querySelector<HTMLFormElement>("#model-form")!.addEventListener("submit", event => {
  event.preventDefault();
  const status = document.querySelector<HTMLElement>("#model-status")!;
  void invoke<void>("set_model", { value: modelInput.value.trim() }).then(
    () => { status.textContent = "Model saved"; },
    error => { status.textContent = String(error); },
  );
});

const historyEnabled = document.querySelector<HTMLInputElement>("#history-enabled")!;
const historySearch = document.querySelector<HTMLInputElement>("#history-search")!;
const historyList = document.querySelector<HTMLUListElement>("#history-list")!;
const historyStatus = document.querySelector<HTMLElement>("#history-status")!;
const historyMore = document.querySelector<HTMLButtonElement>("#history-more")!;
let historyOffset = 0;
let historyLoad = 0;

void invoke<boolean>("history_enabled").then(enabled => { historyEnabled.checked = enabled; });
historyEnabled.addEventListener("change", () => {
  void invoke<void>("set_history_enabled", { enabled: historyEnabled.checked });
});
async function loadHistory(reset: boolean) {
  if (reset) { historyOffset = 0; historyList.replaceChildren(); }
  const load = ++historyLoad;
  try {
    const records = await invoke<HistoryRecord[]>("list_history", { query: historySearch.value.trim(), offset: historyOffset });
    if (load !== historyLoad) return;
    for (const record of records) {
      const item = document.createElement("li");
      const details = document.createElement("details");
      const summary = document.createElement("summary");
      summary.textContent = `${record.source_app} · ${new Date(record.created_at_ms).toLocaleString()} · ${record.selected_text.slice(0, 90)}`;
      details.append(summary);
      for (const [label, value] of [
        ["Selected text", record.selected_text], ["Context before", record.context_before],
        ["Context after", record.context_after], ["Preset", `${record.preset_id} v${record.preset_version}`],
        ["Capture method", record.capture_method], ["Model", record.model_id], ["Reply", record.reply],
      ]) {
        if (!value) continue;
        const heading = document.createElement("strong");
        heading.textContent = label;
        const body = document.createElement("pre");
        body.textContent = value;
        details.append(heading, body);
      }
      const remove = document.createElement("button");
      remove.type = "button";
      remove.textContent = "Delete entry";
      remove.addEventListener("click", () => {
        void invoke<boolean>("delete_history_entry", { id: record.id }).then(() => { item.remove(); });
      });
      details.append(remove);
      item.append(details);
      historyList.append(item);
    }
    historyOffset += records.length;
    historyMore.hidden = records.length < 100;
    historyStatus.textContent = historyOffset ? `${historyOffset} entries shown` : "No matching history";
  } catch (error) {
    historyStatus.textContent = String(error);
  }
}
document.querySelector<HTMLDetailsElement>("#history-view")!.addEventListener("toggle", event => {
  if ((event.target as HTMLDetailsElement).open) void loadHistory(true);
});
historySearch.addEventListener("input", () => { void loadHistory(true); });
historyMore.addEventListener("click", () => { void loadHistory(false); });
document.querySelector<HTMLButtonElement>("#clear-history")!.addEventListener("click", () => {
  if (!window.confirm("Delete all local explanation history?")) return;
  void invoke<void>("clear_history").then(() => { void loadHistory(true); }, error => { historyStatus.textContent = String(error); });
});
}
