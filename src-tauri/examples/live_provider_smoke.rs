use std::io::{self, BufRead, Read};
use zeroize::Zeroize;

fn main() {
    if std::env::args().skip(1).collect::<Vec<_>>() != ["--live"] {
        eprintln!("Explicit invocation required: use --live; supply the key on stdin.");
        std::process::exit(2);
    }
    let mut key = String::new();
    if io::stdin().lock().take(513).read_line(&mut key).is_err() ||
        key.trim().len() < 8 || key.trim().len() > 512 {
        key.zeroize();
        eprintln!("Supply a local OpenAI API key on stdin (not an argument).");
        std::process::exit(2);
    }
    let clean = key.trim().to_owned();
    key.zeroize();
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().expect("runtime");
    match runtime.block_on(splainit_lib::live_provider_smoke(clean)) {
        Ok(result) => println!("{result}"),
        Err(error) => { eprintln!("{error}"); std::process::exit(1); }
    }
}
