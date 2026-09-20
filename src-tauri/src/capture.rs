use serde::{Deserialize, Serialize};
use std::ops::Deref;

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum CaptureStatus {
    Verified,
    Unverified,
    NoSelection,
    PermissionRequired,
    Blocked,
    Unavailable,
    Oversized,
    TimedOut,
    Cancelled,
    #[default]
    Failed,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum CaptureMethod {
    AxSelectedText,
    AxRange,
    AxBoundsOcr,
    VisualDragOcr,
}

impl CaptureMethod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::AxSelectedText => "ax_selected_text",
            Self::AxRange => "ax_range",
            Self::AxBoundsOcr => "ax_bounds_ocr",
            Self::VisualDragOcr => "visual_drag_ocr",
        }
    }
    pub fn is_semantic(self) -> bool {
        matches!(self, Self::AxSelectedText | Self::AxRange)
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Verification {
    Semantic,
    Unverified,
    #[default]
    None,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum PermissionKind { Accessibility, ScreenRecording }

#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct PermissionRequired {
    pub kind: PermissionKind,
    // Preflight cannot distinguish never-requested from previously denied.
    pub state: PermissionState,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum PermissionState { NotGranted, Denied }

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
pub(crate) struct AxRange { pub location: u64, pub length: u64 }

#[derive(Clone, Copy, Debug, Deserialize, Serialize)]
pub(crate) struct Bounds {
    pub x: f64, pub y: f64, pub width: f64, pub height: f64,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub(crate) struct NativeCapture {
    pub status: CaptureStatus,
    #[serde(default)]
    pub visual_available: bool,
    pub detail: String,
    pub text: String,
    pub method: Option<CaptureMethod>,
    #[serde(default)]
    pub verification: Verification,
    pub confidence: Option<f64>,
    pub permission: Option<PermissionRequired>,
    pub ax_range: Option<AxRange>,
    #[serde(default)]
    pub bounds: Vec<Bounds>,
    #[serde(default)]
    pub context_before: String,
    #[serde(default)]
    pub context_after: String,
}

impl NativeCapture {
    pub fn failure(status: CaptureStatus, detail: impl Into<String>) -> Self {
        Self { status, detail: detail.into(), ..Self::default() }
    }

    // Treat the FFI as a typed boundary, not implicit permission to send text.
    pub fn checked(mut self, context_enabled: bool) -> Self {
        let semantic = self.method.is_some_and(CaptureMethod::is_semantic);
        let consistent = match self.status {
            CaptureStatus::Verified => semantic && self.verification == Verification::Semantic,
            CaptureStatus::Unverified => !semantic && self.method.is_some()
                && self.verification == Verification::Unverified,
            CaptureStatus::PermissionRequired => self.permission.is_some(),
            _ => true,
        };
        if !consistent || self.confidence.is_some_and(|v| !v.is_finite() || !(0.0..=1.0).contains(&v)) {
            return Self::failure(CaptureStatus::Failed, "Capture evidence was inconsistent");
        }
        if matches!(self.status, CaptureStatus::Verified | CaptureStatus::Unverified) {
            if self.text.trim().is_empty() {
                return Self::failure(CaptureStatus::NoSelection, "No readable selected text");
            }
            if self.text.encode_utf16().count() > 12_000 {
                return Self::failure(CaptureStatus::Oversized, "Select at most 12,000 UTF-16 code units");
            }
        } else {
            self.text.clear();
        }
        if !context_enabled || !semantic || self.status != CaptureStatus::Verified || self.ax_range.is_none() {
            self.context_before.clear();
            self.context_after.clear();
        }
        if self.context_before.encode_utf16().count() > 500 || self.context_after.encode_utf16().count() > 500 {
            return Self::failure(CaptureStatus::Failed, "Semantic context exceeded its limit");
        }
        self
    }

    pub fn can_explain(&self, confirmed: bool) -> bool {
        !self.text.trim().is_empty() && match self.status {
            CaptureStatus::Verified => self.verification == Verification::Semantic
                && self.method.is_some_and(CaptureMethod::is_semantic),
            CaptureStatus::Unverified => confirmed && self.verification == Verification::Unverified
                && self.method.is_some_and(|m| !m.is_semantic()),
            _ => false,
        }
    }
}

#[derive(Clone, Serialize)]
pub(crate) struct Capture {
    pub invocation: u64,
    pub timestamp_ms: u128,
    pub revision: u32,
    pub source_app: String,
    pub bundle_id: String,
    pub pid: i32,
    #[serde(flatten)]
    pub result: NativeCapture,
}

impl Deref for Capture {
    type Target = NativeCapture;
    fn deref(&self) -> &Self::Target { &self.result }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(method: CaptureMethod) -> NativeCapture {
        let semantic = method.is_semantic();
        NativeCapture {
            status: if semantic { CaptureStatus::Verified } else { CaptureStatus::Unverified },
            method: Some(method),
            verification: if semantic { Verification::Semantic } else { Verification::Unverified },
            confidence: if semantic { None } else { Some(0.99) },
            text: "selected text".into(),
            ax_range: Some(AxRange { location: 10, length: 13 }),
            context_before: "before".into(), context_after: "after".into(),
            // A misleading display message must never change provenance.
            detail: "misleading range detail".into(),
            ..NativeCapture::default()
        }
    }

    #[test]
    fn provider_provenance_round_trips_and_confirmation_preserves_visual_evidence() {
        for method in [CaptureMethod::AxSelectedText, CaptureMethod::AxRange,
                       CaptureMethod::AxBoundsOcr, CaptureMethod::VisualDragOcr] {
            let native: NativeCapture = serde_json::from_value(serde_json::to_value(fixture(method)).unwrap()).unwrap();
            let capture = native.checked(true);
            assert_eq!(capture.method, Some(method));
            assert_eq!(capture.can_explain(false), method.is_semantic());
            assert!(capture.can_explain(true));
            assert_eq!(capture.verification, if method.is_semantic() { Verification::Semantic } else { Verification::Unverified });
        }
    }

    #[test]
    fn no_context_from_visual_or_legacy_providers_even_with_opt_in() {
        for method in [CaptureMethod::AxBoundsOcr, CaptureMethod::VisualDragOcr] {
            let capture = fixture(method).checked(true);
            assert!(capture.context_before.is_empty());
            assert!(capture.context_after.is_empty());
        }
        let semantic = fixture(CaptureMethod::AxRange).checked(true);
        assert_eq!(semantic.context_before, "before");
        assert!(fixture(CaptureMethod::AxRange).checked(false).context_before.is_empty());
    }

    #[test]
    fn invalid_evidence_and_utf16_oversize_cannot_send() {
        let mut visual = fixture(CaptureMethod::AxBoundsOcr);
        visual.status = CaptureStatus::Verified;
        assert!(!visual.checked(true).can_explain(true));
        let mut direct = fixture(CaptureMethod::AxSelectedText);
        direct.method = None;
        assert!(!direct.checked(true).can_explain(true));
        let mut direct = fixture(CaptureMethod::AxSelectedText);
        direct.text = "😀".repeat(6001);
        assert_eq!(direct.checked(true).status, CaptureStatus::Oversized);
        let mut visual = fixture(CaptureMethod::VisualDragOcr);
        visual.confidence = Some(1.1);
        assert_eq!(visual.checked(false).status, CaptureStatus::Failed);
    }

    #[test]
    fn permissions_round_trip_without_text_or_confidence_fabrication() {
        for kind in [PermissionKind::Accessibility, PermissionKind::ScreenRecording] {
            for state in [PermissionState::NotGranted, PermissionState::Denied] {
                let value = NativeCapture { status: CaptureStatus::PermissionRequired,
                    permission: Some(PermissionRequired { kind, state }),
                    text: "must be removed".into(), ..NativeCapture::default() }.checked(false);
                let serialized = serde_json::to_value(&value).unwrap();
                assert!(serialized["confidence"].is_null());
                assert_eq!(serialized["text"], "");
                assert!(!value.can_explain(true));
                assert_eq!(value.permission.unwrap().kind, kind);
            }
        }
    }
}
