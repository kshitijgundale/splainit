//! Offline release tooling. Reads the same public key embedded in this build.
use base64::{engine::general_purpose::STANDARD, Engine};
use minisign_verify::{PublicKey, Signature};
use std::{fs, path::Path, process::ExitCode};

fn verify(artifact: &Path, signature_path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let config: serde_json::Value = serde_json::from_str(include_str!("../tauri.conf.json"))?;
    let public = config["plugins"]["updater"]["pubkey"].as_str().ok_or("Missing public key")?;
    let public = String::from_utf8(STANDARD.decode(public.trim())?)?;
    let public = PublicKey::decode(&public)?;
    let signature = String::from_utf8(STANDARD.decode(fs::read_to_string(signature_path)?.trim())?)?;
    let signature = Signature::decode(&signature)?;
    public.verify(&fs::read(artifact)?, &signature, true)?;
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 2 {
        eprintln!("Usage: verify_update <artifact> <artifact.sig>");
        return ExitCode::FAILURE;
    }
    match verify(Path::new(&args[0]), Path::new(&args[1])) {
        Ok(()) => { println!("Update signature verified against the embedded public key."); ExitCode::SUCCESS }
        Err(error) => { eprintln!("Update signature rejected: {error}"); ExitCode::FAILURE }
    }
}
