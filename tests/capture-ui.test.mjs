import { test } from "node:test";
import assert from "node:assert/strict";
import { canExplain, captureProvenance, permissionMessage } from "../src/capture-ui.ts";

const fixture = {
  invocation: 5, revision: 0, visual_available: false, source_app: "Fixture", bundle_id: "test.fixture", pid: 42,
  timestamp_ms: 1, status: "unverified", verification: "unverified",
  method: "ax_bounds_ocr", confidence: 0.99, permission: null, ax_range: null,
  bounds: [], context_before: "", context_after: "", text: "Fixture text",
};

test("every visual method requires confirmation, even at 100% confidence", () => {
  for (const method of ["ax_bounds_ocr", "visual_drag_ocr"]) {
    const capture = { ...fixture, method, confidence: 1 };
    const snapshot = structuredClone(capture);
    assert.equal(canExplain(capture, false), false);
    assert.equal(canExplain(capture, true), true);
    assert.deepEqual(capture, snapshot);
    assert.match(captureProvenance(capture), /Unverified/);
    assert.equal(canExplain({ ...capture, status: "verified" }, false), false);
  }
});

test("only consistent semantic evidence can auto-send", () => {
  for (const method of ["ax_selected_text", "ax_range"]) {
    assert.equal(canExplain({ ...fixture, method, status: "verified", verification: "semantic" }, false), true);
    assert.equal(canExplain({ ...fixture, method, status: "verified" }, false), false);
  }
  for (const status of ["no_selection", "permission_required", "blocked", "unavailable", "oversized", "timed_out", "cancelled", "failed"]) {
    assert.equal(canExplain({ ...fixture, status }, true), false);
  }
  assert.equal(canExplain({ ...fixture, text: "😀".repeat(6001) }, true), false);
});

test("visual provenance and unknown confidence remain visible after confirmation", () => {
  const capture = { ...fixture, confidence: null };
  assert.equal(canExplain(capture, true), true);
  assert.match(captureProvenance(capture), /Local OCR of AX selection bounds/);
  assert.match(captureProvenance(capture), /confidence unknown/);
  assert.match(captureProvenance({ ...fixture, method: "visual_drag_ocr" }), /your drawn region/);
  assert.match(permissionMessage({ ...fixture, permission: { kind: "screen_recording", state: "denied" } }), /Accessibility capture remains available/);
});
