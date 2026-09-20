export type Capture = {
  invocation: number;
  revision: number;
  visual_available: boolean;
  status: "verified" | "unverified" | "no_selection" | "permission_required" | "blocked" | "unavailable" | "oversized" | "timed_out" | "cancelled" | "failed";
  source_app: string;
  bundle_id: string;
  timestamp_ms: number;
  pid: number;
  method?: "ax_selected_text" | "ax_range" | "ax_bounds_ocr" | "visual_drag_ocr" | null;
  verification: "semantic" | "unverified" | "none";
  confidence: number | null;
  permission: { kind: "accessibility" | "screen_recording"; state: "not_granted" | "denied" } | null;
  ax_range: { location: number; length: number } | null;
  bounds: { x: number; y: number; width: number; height: number }[];
  context_before: string;
  context_after: string;
  text?: string;
  detail?: string;
};

export function canExplain(capture: Capture, confirmed: boolean): boolean {
  if (!capture.text?.trim() || capture.text.length > 12_000) return false;
  const semantic = capture.method === "ax_selected_text" || capture.method === "ax_range";
  if (capture.status === "verified") return semantic && capture.verification === "semantic";
  return capture.status === "unverified" && capture.verification === "unverified"
    && !!capture.method && !semantic && confirmed;
}

export function captureProvenance(capture: Capture): string {
  const methods: Record<NonNullable<Capture["method"]>, string> = {
    ax_selected_text: "Accessibility selected text",
    ax_range: "Accessibility selected range",
    ax_bounds_ocr: "Local OCR of AX selection bounds",
    visual_drag_ocr: "Local OCR of your drawn region",
  };
  if (!capture.method) return "";
  const evidence = capture.verification === "semantic" ? "Semantically verified" : "Unverified — review required";
  const visual = capture.method === "ax_bounds_ocr" || capture.method === "visual_drag_ocr";
  const confidence = visual ? (capture.confidence === null
    ? " · OCR confidence unknown"
    : ` · OCR confidence ${Math.round(capture.confidence * 100)}%`) : "";
  return `${methods[capture.method]} · ${evidence}${confidence}`;
}

export function permissionMessage(capture: Capture): string {
  if (capture.permission?.kind === "screen_recording") {
    return "Screen Recording permission is required for local OCR of the selected region. Images stay on this Mac and are discarded after recognition. Review recognized text before sending it. Accessibility capture remains available.";
  }
  return "Accessibility permission is required. Enable Splainit in System Settings → Privacy & Security → Accessibility.";
}
