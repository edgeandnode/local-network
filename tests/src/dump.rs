//! Capture live stack state when a test fails, before teardown.
//!
//! Wraps a test body so an unexpected `Err` snapshots the running stack via
//! the existing `scripts/dump-state.sh` (containers, logs, chain state,
//! indexer-agent API, and any per-test `IndexerHandle` compose projects) into
//! `_dumps/fail-<label>/`, then re-raises the error. Because the dump runs
//! while the test body's `IndexerHandle` is still in scope, the per-test
//! stack is still up and gets captured before `Drop` tears it down.
//!
//! Adoption pattern:
//!
//! ```ignore
//! #[tokio::test]
//! async fn my_test() -> Result<()> {
//!     let net = TestNetwork::from_default_env();
//!     let indexer = IndexerHandle::new("my-test").await?;
//!     dump_on_failure("my_test", async {
//!         // ... body using `net` and `indexer`, ending in Ok(()) ...
//!         Ok(())
//!     })
//!     .await
//! }
//! ```
//!
//! Only the `Err` path is captured. Expected reverts that tests consume via
//! `match` / `is_err()` never propagate, so they don't trigger a dump. Panics
//! from `assert!` are reported by libtest with the assertion message plus the
//! test's `eprintln!` progress and don't reach here.

use std::future::Future;
use std::path::PathBuf;
use std::process::Command;

use anyhow::Result;

/// Run `body`; on `Err`, capture stack state and log where, then propagate the
/// error unchanged. On `Ok`, a no-op.
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

/// Invoke `scripts/dump-state.sh` into `_dumps/fail-<label>/`. Best-effort:
/// a dump failure is logged but never masks the original test error.
pub fn dump_state(label: &str) {
    let repo_root = repo_root();
    let out = format!("_dumps/fail-{}", sanitize(label));
    let result = Command::new("bash")
        .current_dir(&repo_root)
        .arg("scripts/dump-state.sh")
        .arg(&out)
        .output();
    match result {
        Ok(o) if o.status.success() => {
            // The script echoes the resolved output dir as its last stdout line.
            let dir = String::from_utf8_lossy(&o.stdout)
                .lines()
                .last()
                .map(str::to_string)
                .unwrap_or(out);
            eprintln!("\n[state dump] {label} failed — captured stack state to {dir}\n");
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
