//! DIPs (Direct Indexer Payments) test helpers: inject indexing-requirement
//! signals into the dipper pipeline and query the indexing-payments subgraph
//! for agreement lifecycle state.
//!
//! Pipeline: `signal_indexing_requirement` produces to the Redpanda
//! `indexing-requirements` topic → dipper selects indexers (IISA) and submits
//! `RecurringCollector.offer()` on-chain → the indexing-payments subgraph
//! indexes the `Offer` / `IndexingAgreement` → the DIPs-enabled indexer-agent
//! accepts (and collects) on-chain. These helpers let a test drive and observe
//! that flow.

use anyhow::{Context, Result};
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;

use crate::TestNetwork;

impl TestNetwork {
    /// The indexing-payments subgraph GraphQL endpoint — same graph-node as the
    /// network subgraph, different subgraph name.
    pub fn indexing_payments_subgraph_url(&self) -> String {
        self.subgraph_url
            .replace("graph-network", "indexing-payments")
    }

    /// Query the indexing-payments subgraph.
    pub async fn indexing_payments_query(&self, query: &str) -> Result<Value> {
        let url = self.indexing_payments_subgraph_url();
        self.graphql_post(&url, query, None).await
    }

    /// Inject a DIPs indexing-requirement signal via the `indexing-requirements`
    /// Redpanda topic (plain JSON, no signing). Dipper consumes it and submits a
    /// `RecurringCollector.offer()` on-chain.
    pub fn signal_indexing_requirement(
        &self,
        deployment_ipfs: &str,
        redundancy_factor: u32,
        version: u64,
    ) -> Result<()> {
        let out = Command::new("bash")
            .current_dir(repo_root())
            .arg("scripts/dips-signal.sh")
            .arg(deployment_ipfs)
            .arg(redundancy_factor.to_string())
            .arg(version.to_string())
            .output()
            .context("running scripts/dips-signal.sh")?;
        if !out.status.success() {
            anyhow::bail!(
                "dips-signal.sh failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
        }
        Ok(())
    }

    /// DIPs agreements indexed by the indexing-payments subgraph.
    pub async fn dips_agreements(&self) -> Result<Vec<Value>> {
        let resp = self
            .indexing_payments_query(
                "{ indexingAgreements(first: 100) { id indexer state } }",
            )
            .await?;
        Ok(resp["data"]["indexingAgreements"]
            .as_array()
            .cloned()
            .unwrap_or_default())
    }
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."))
}

/// True when the DIPs stack is up (the `dipper` container is running). The DIPs
/// lifecycle test uses this to self-skip on recipes without DIPs (e.g. baseline
/// has no dipper) — defence-in-depth alongside recipe/profile selection.
pub fn dips_stack_running() -> bool {
    Command::new("docker")
        .args(["inspect", "-f", "{{.State.Running}}", "dipper"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "true")
        .unwrap_or(false)
}
