//! DIPs (Direct Indexer Payments) test helpers: drive a request through dipper's
//! admin RPC and observe the resulting on-chain agreement via the
//! indexing-payments subgraph.

use anyhow::{Context, Result};
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

use crate::TestNetwork;

impl TestNetwork {
    /// The indexing-payments subgraph endpoint (same graph-node, different name).
    pub fn indexing_payments_subgraph_url(&self) -> String {
        self.subgraph_url
            .replace("graph-network", "indexing-payments")
    }

    /// Query the indexing-payments subgraph.
    pub async fn indexing_payments_query(&self, query: &str) -> Result<Value> {
        let url = self.indexing_payments_subgraph_url();
        self.graphql_post(&url, query, None).await
    }

    /// DIPs agreements indexed by the indexing-payments subgraph. `tokensCollected`
    /// is the cumulative GRT paid out for an agreement — the DIPs payment signal.
    pub async fn dips_agreements(&self) -> Result<Vec<Value>> {
        let resp = self
            .indexing_payments_query(
                "{ indexingAgreements(first: 100) { id indexer state tokensCollected } }",
            )
            .await?;
        Ok(resp["data"]["indexingAgreements"]
            .as_array()
            .cloned()
            .unwrap_or_default())
    }

    /// Cumulative GRT collected for one agreement (0 if not found).
    pub async fn agreement_tokens_collected(&self, id: &str) -> Result<u128> {
        let agreements = self.dips_agreements().await?;
        let collected = agreements
            .iter()
            .find(|a| a["id"].as_str() == Some(id))
            .and_then(|a| a["tokensCollected"].as_str())
            .unwrap_or("0");
        collected
            .parse()
            .with_context(|| format!("parsing tokensCollected '{collected}'"))
    }

    /// The graph-network subgraph's own deployment hash (Qm...). Every indexer
    /// already serves it, so it's a safe DIPs indexing target.
    pub async fn network_deployment(&self) -> Result<String> {
        let resp = self.subgraph_query("{ _meta { deployment } }").await?;
        resp["data"]["_meta"]["deployment"]
            .as_str()
            .map(String::from)
            .context("graph-network _meta.deployment missing")
    }

    /// Ensure the indexer has an active allocation on `deployment` that the
    /// network subgraph can see — the serving precondition IISA selects on.
    /// Repairs state from aborted tests; fails fast instead of burning the wait.
    pub async fn ensure_serving_allocation(&self, deployment: &str) -> Result<()> {
        let allocs = self.get_allocations().await?;
        let has_active = allocs
            .as_array()
            .map(|list| {
                list.iter().any(|a| {
                    a["closedAtEpoch"].is_null()
                        && a["subgraphDeployment"].as_str() == Some(deployment)
                })
            })
            .unwrap_or(false);
        if !has_active {
            eprintln!("  WARNING: no active allocation on {deployment} — creating one");
            self.create_allocation(deployment, "0.01").await?;
        }
        self.ensure_always_rule(deployment).await?;

        // IISA and dipper read the network subgraph, not the agent, so wait
        // (bounded) until the allocation is indexed there.
        let deadline = Instant::now() + Duration::from_secs(90);
        loop {
            let visible = self
                .query_active_allocations(&self.indexer_address)
                .await?
                .as_array()
                .map(|list| {
                    list.iter()
                        .any(|a| a["subgraphDeployment"]["ipfsHash"].as_str() == Some(deployment))
                })
                .unwrap_or(false);
            if visible {
                return Ok(());
            }
            if Instant::now() > deadline {
                anyhow::bail!(
                    "no active allocation on {deployment} visible in the network subgraph \
                     after 90s; IISA selects no candidates without one, so the agreement \
                     wait would time out — check indexer-agent and graph-node logs"
                );
            }
            tokio::time::sleep(Duration::from_secs(3)).await;
        }
    }

    /// Give IISA query history to score against, then run one scoring pass.
    /// Without scores dipper can't assign candidates and acceptance never happens.
    pub async fn warm_iisa(&self) -> Result<()> {
        let (ok, fail) = self.send_gateway_queries(20).await.unwrap_or((0, 0));
        eprintln!("  warm_iisa: gateway queries ok={ok} fail={fail}");
        let out = Command::new("docker")
            .current_dir(repo_root())
            .args([
                "compose",
                "--profile",
                "indexing-payments",
                "run",
                "--rm",
                "iisa-cronjob",
            ])
            .output()
            .context("running iisa-cronjob")?;
        let last = String::from_utf8_lossy(&out.stdout)
            .lines()
            .last()
            .unwrap_or("")
            .to_string();
        eprintln!("  warm_iisa: iisa-cronjob exit={} {last}", out.status);
        Ok(())
    }

    /// Request `num_candidates` indexers for `deployment_ipfs` via dipper's admin
    /// RPC. Runs the pinned dipper-cli image signed with the RECEIVER key — the
    /// only address on dipper's admin allowlist.
    pub fn request_indexing(&self, deployment_ipfs: &str, num_candidates: u32) -> Result<()> {
        let image = dipper_cli_image()?;
        let admin_port = std::env::var("DIPPER_ADMIN_RPC_PORT").unwrap_or_else(|_| "9000".into());
        let server_url = format!("http://localhost:{admin_port}/");
        let out = Command::new("docker")
            .args([
                "run",
                "--rm",
                "--network",
                "host",
                &image,
                "indexings",
                "set-target-candidates",
                "--server-url",
                &server_url,
                "--signing-key",
                &self.receiver_secret,
                deployment_ipfs,
                "1337",
                "--num-candidates",
                &num_candidates.to_string(),
            ])
            .output()
            .context("running dipper-cli set-target-candidates")?;
        if !out.status.success() {
            anyhow::bail!(
                "set-target-candidates failed (image {image}): {}",
                String::from_utf8_lossy(&out.stderr)
            );
        }
        eprintln!(
            "  request_indexing: {deployment_ipfs} -> {}",
            String::from_utf8_lossy(&out.stdout).trim()
        );
        Ok(())
    }
}

/// Prefer `DIPPER_CLI_IMAGE` (set by CI), else the first locally-present
/// `ghcr.io/edgeandnode/dipper-cli:*` tag.
fn dipper_cli_image() -> Result<String> {
    if let Ok(img) = std::env::var("DIPPER_CLI_IMAGE")
        && !img.is_empty()
    {
        return Ok(img);
    }
    let out = Command::new("sh")
        .arg("-c")
        .arg(
            "docker images --format '{{.Repository}}:{{.Tag}}' \
             | grep '^ghcr.io/edgeandnode/dipper-cli:' | head -1",
        )
        .output()
        .context("resolving dipper-cli image")?;
    let img = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if img.is_empty() {
        anyhow::bail!(
            "no dipper-cli image found; set DIPPER_CLI_IMAGE or \
             `docker pull ghcr.io/edgeandnode/dipper-cli:<DIPPER_VERSION>`"
        );
    }
    Ok(img)
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."))
}

/// Everything on dipper's agreement-events Redpanda topic from the beginning,
/// with non-printable protobuf bytes replaced by `.` so event-type strings can
/// be matched. Empty when the topic is missing or has no events yet.
pub fn dips_agreement_events_raw() -> Result<String> {
    let out = Command::new("docker")
        .args([
            "exec",
            "redpanda",
            "bash",
            "-c",
            "timeout 8 rpk topic consume dipper.subgraph.indexing.agreement.events \
             -o start -f '%v\\n' 2>/dev/null | tr -c '[:print:]\\n' '.'; true",
        ])
        .output()
        .context("consuming dipper events topic from redpanda")?;
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// True when the `dipper` container is running; DIPs tests self-skip otherwise.
pub fn dips_stack_running() -> bool {
    Command::new("docker")
        .args(["inspect", "-f", "{{.State.Running}}", "dipper"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "true")
        .unwrap_or(false)
}
