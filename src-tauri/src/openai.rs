use crate::prompts::Prompt;
use serde_json::{json, Value};
use std::time::Duration;
use tokio::sync::watch;
use zeroize::Zeroizing;

pub fn default_model() -> &'static str { include_str!("../default-model.txt").trim() }

fn build_request(client: &reqwest::Client, key: &str, model: &str, prompt: &Prompt) -> reqwest::RequestBuilder {
    client.post("https://api.openai.com/v1/responses")
        .bearer_auth(key)
        .json(&json!({
            "model": model,
            "instructions": prompt.instruction,
            "input": prompt.input,
            "store": false,
            "tools": [],
            "max_output_tokens": 700,
        }))
}

pub async fn explain(
    key: String,
    model: &str,
    prompt: &Prompt,
    mut cancelled: watch::Receiver<u64>,
) -> Result<String, String> {
    let key = Zeroizing::new(key);
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|_| "Could not initialize network client".to_string())?;
    let request = build_request(&client, &key, model, prompt);
    drop(key);
    let sent = tokio::select! {
        _ = cancelled.changed() => return Err("Request cancelled".into()),
        result = request.send() => result.map_err(network_error)?,
    };
    let status = sent.status();
    let mut response = sent;
    let mut body = Vec::new();
    loop {
        let chunk = tokio::select! {
            _ = cancelled.changed() => return Err("Request cancelled".into()),
            result = response.chunk() => result.map_err(network_error)?,
        };
        let Some(chunk) = chunk else { break };
        if body.len() + chunk.len() > 256 * 1024 {
            return Err("Provider response exceeded the size limit".into());
        }
        body.extend_from_slice(&chunk);
    }
    if !status.is_success() {
        let code = serde_json::from_slice::<Value>(&body).ok()
            .and_then(|value| value.pointer("/error/code").and_then(Value::as_str).map(str::to_owned));
        return Err(match status.as_u16() {
            401 | 403 => "OpenAI rejected the API key or account access. Check settings.".into(),
            429 => "OpenAI rate limit or quota reached. Try again later.".into(),
            400 | 404 if code.as_deref() == Some("model_not_found") => "This OpenAI model is unavailable to your account. Choose another model in settings.".into(),
            400 | 404 => "OpenAI rejected the request. Check the configured model.".into(),
            500..=599 => "OpenAI is temporarily unavailable. Try again later.".into(),
            _ => "OpenAI could not complete the request.".into(),
        });
    }
    let value: Value = serde_json::from_slice(&body)
        .map_err(|_| "OpenAI returned an unreadable response".to_string())?;
    if value.get("status").and_then(Value::as_str) == Some("incomplete") {
        return Err("Explanation was cut off. Select a shorter passage and retry.".into());
    }
    let mut parts = Vec::new();
    if let Some(items) = value.get("output").and_then(Value::as_array) {
        for item in items {
            if item.get("type").and_then(Value::as_str) != Some("message") { continue; }
            if let Some(content) = item.get("content").and_then(Value::as_array) {
                for part in content {
                    if part.get("type").and_then(Value::as_str) == Some("output_text") {
                        if let Some(text) = part.get("text").and_then(Value::as_str) {
                            parts.push(text);
                        }
                    }
                }
            }
        }
    }
    if parts.is_empty() || parts.iter().all(|text| text.trim().is_empty()) {
        return Err("OpenAI returned no explanation text.".into());
    }
    Ok(parts.join("\n"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::{CaptureMethod, CaptureStatus, NativeCapture, Verification};
    use crate::prompts::{compose, PresetId};

    #[test]
    fn serialized_native_requests_contain_only_permitted_text_fields() {
        for method in [CaptureMethod::AxBoundsOcr, CaptureMethod::VisualDragOcr] {
            let snapshot = NativeCapture {
                status: CaptureStatus::Unverified, method: Some(method),
                verification: Verification::Unverified, text: "Harmless selected words".into(),
                // These extra native fields must be discarded, not sent as OCR context.
                context_before: "UNINTENDED_SURROUNDING_TEXT".into(),
                context_after: "UNINTENDED_SURROUNDING_TEXT".into(),
                ..NativeCapture::default()
            }.checked(true);
            let prompt = compose(PresetId::ExplainSimply, &snapshot.text,
                &snapshot.context_before, &snapshot.context_after).unwrap();
            let request = build_request(&reqwest::Client::new(), "mock-only-key", default_model(), &prompt)
                .build().unwrap();
            let bytes = request.body().unwrap().as_bytes().unwrap();
            let body: Value = serde_json::from_slice(bytes).unwrap();
            assert_eq!(body.as_object().unwrap().len(), 6);
            assert_eq!(body["store"], false);
            assert_eq!(body["tools"], json!([]));
            assert_eq!(body["model"], default_model());
            assert_eq!(body["max_output_tokens"], 700);
            let input: Value = serde_json::from_str(body["input"].as_str().unwrap()).unwrap();
            assert_eq!(input, json!({"selected_text": "Harmless selected words", "context_before": "", "context_after": ""}));
            let serialized = std::str::from_utf8(bytes).unwrap();
            for forbidden in ["UNINTENDED_SURROUNDING_TEXT", "mock-only-key", "input_image", "image_url", "data:image/", "file://", "screenshot"] {
                assert!(!serialized.contains(forbidden));
            }
        }
    }
}

fn network_error(error: reqwest::Error) -> String {
    if error.is_timeout() {
        "OpenAI request timed out. Try again.".into()
    } else {
        "Could not reach OpenAI. Check the network and retry.".into()
    }
}
