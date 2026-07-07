//! Snapshot the running stack when a test fails, before teardown.

use std::future::Future;
use std::path::PathBuf;
use std::process::Command;

use anyhow::Result;

/// Run `body`; on `Err`, capture stack state and log where, then propagate the
/// error unchanged.
pub async fn dump_on_failure<F>(label: &str, body: F) -> Result<()>
where
    F: Future<Output = Result<()>>,
{
    let result = body.await;
    if result.is_err() {
        dump_state(label);
    }
    result
}

/// Invoke `scripts/dump-state.sh` into `_dumps/fail-<label>/`. Best-effort: a
/// dump failure is logged but never masks the test error.
pub fn dump_state(label: &str) {
    let out = format!("_dumps/fail-{}", sanitize(label));
    let result = Command::new("bash")
        .current_dir(repo_root())
        .arg("scripts/dump-state.sh")
        .arg(&out)
        .output();
    match result {
        Ok(o) if o.status.success() => {
            let dir = String::from_utf8_lossy(&o.stdout)
                .lines()
                .last()
                .map(str::to_string)
                .unwrap_or(out);
            eprintln!("\n[state dump] {label} failed — captured to {dir}\n");
        }
        Ok(o) => eprintln!(
            "\n[state dump] {label} failed; dump-state.sh exited {}: {}\n",
            o.status,
            String::from_utf8_lossy(&o.stderr),
        ),
        Err(e) => eprintln!("\n[state dump] {label} failed; could not run dump-state.sh: {e}\n"),
    }
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."))
}

fn sanitize(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect()
}
