//! Per-test indexer fixture.
//!
//! `IndexerHandle::new(test_id)` brings up a fresh per-test compose project
//! (postgres + graph-node + subgraph-deploy + indexer-agent) defined in
//! `compose/test-indexer.yaml`, with a fresh mnemonic and identity injected
//! via `TEST_INDEXER_*` env vars. The agent's management API is reachable
//! over the `cross-stack` Docker network by container name.
//!
//! Tests that mutate allocations should own their own `IndexerHandle` rather
//! than share `TestNetwork::indexer_address` (the production indexer that the
//! main agent auto-reconciles).

use anyhow::{bail, Context, Result};
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

use crate::TestNetwork;

const COMPOSE_FILE: &str = "compose/test-indexer.yaml";
const PROTOCOL_NETWORK: &str = "eip155:1337";

pub struct IndexerHandle {
    pub project_name: String,
    pub address: String,
    pub secret: String,
    pub mnemonic: String,
    pub management_url: String,
    pub subgraph_url: String,
    repo_root: PathBuf,
}

impl IndexerHandle {
    /// Bring up a fresh per-test indexer stack. Generates a random 12-word
    /// mnemonic, derives address+secret from index 0, and runs the test-indexer
    /// compose project with that identity injected via `TEST_INDEXER_*`.
    /// Returns once the agent is healthy AND has reported `registered=true` —
    /// the latter prevents tests from racing the agent's own registration tx.
    pub async fn new(test_id: &str) -> Result<Self> {
        let repo_root = repo_root()?;
        ensure_devcontainer_on_cross_stack()?;

        let (mnemonic, address, secret) = generate_wallet()?;
        let project_name = format!("local-network-test-{}", sanitize(test_id));
        let agent_container = format!("{project_name}-test-indexer-agent-1");
        let graph_node_container = format!("{project_name}-test-graph-node-1");
        let management_url = format!("http://{agent_container}:7600");
        let subgraph_url =
            format!("http://{graph_node_container}:8000/subgraphs/name/graph-network");

        eprintln!("[IndexerHandle {test_id}] project={project_name}");
        eprintln!("[IndexerHandle {test_id}] address={address}");
        eprintln!("[IndexerHandle {test_id}] mnemonic=\"{mnemonic}\"");

        // Tear down any orphan stack with this project name before bringing
        // up a fresh one. A prior run that died during `compose up` (or was
        // killed) never reaches our `Drop`, so containers can linger across
        // nextest invocations — the new run then reuses a now-degraded
        // graph-node and fails with "dependency failed to start: container
        // … is unhealthy". `down -v` is a fast no-op when nothing matches.
        let _ = Command::new("docker")
            .current_dir(&repo_root)
            .args([
                "compose",
                "-f",
                COMPOSE_FILE,
                "--project-name",
                &project_name,
                "--env-file",
                ".env",
                "down",
                "-v",
                "--remove-orphans",
            ])
            .status();

        let status = Command::new("docker")
            .current_dir(&repo_root)
            .args([
                "compose",
                "-f",
                COMPOSE_FILE,
                "--project-name",
                &project_name,
                "--env-file",
                ".env",
                "up",
                "-d",
            ])
            .env("TEST_INDEXER_ADDRESS", &address)
            .env("TEST_INDEXER_SECRET", &secret)
            .env("TEST_INDEXER_MNEMONIC", &mnemonic)
            .status()
            .context("spawning docker compose up")?;
        if !status.success() {
            bail!("docker compose up failed for {project_name}");
        }

        let handle = Self {
            project_name,
            address,
            secret,
            mnemonic,
            management_url,
            subgraph_url,
            repo_root,
        };

        handle.wait_for_agent_healthy(Duration::from_secs(300))?;
        // The agent fires its own startup/reconcile transactions in the background
        // after healthcheck. If a test calls create_allocation immediately, it
        // races those and gets "nonce has already been used". Wait for
        // registered=true plus a settle period for any reconciler-driven txns
        // (the per-test indexer has no allocations, but the agent may still
        // perform setup writes that share the indexer's signing key).
        handle.wait_for_registered(Duration::from_secs(120)).await?;
        tokio::time::sleep(Duration::from_secs(10)).await;
        Ok(handle)
    }

    async fn wait_for_registered(&self, timeout: Duration) -> Result<()> {
        let query = r#"{ indexerRegistration(protocolNetwork: "eip155:1337") {
            registered
        } }"#;
        let start = Instant::now();
        let client = reqwest::Client::new();
        loop {
            if start.elapsed() > timeout {
                bail!(
                    "indexer-agent in {} did not report registered=true within {:?}",
                    self.project_name,
                    timeout,
                );
            }
            let resp: Result<Value, _> = async {
                let r = client
                    .post(&self.management_url)
                    .header("content-type", "application/json")
                    .json(&serde_json::json!({ "query": query }))
                    .send()
                    .await?;
                r.json::<Value>().await
            }
            .await;
            if let Ok(json) = resp {
                if json["data"]["indexerRegistration"]
                    .as_array()
                    .and_then(|arr| arr.first())
                    .and_then(|reg| reg["registered"].as_bool())
                    == Some(true)
                {
                    return Ok(());
                }
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    }

    /// Poll the agent container's healthcheck until healthy or `timeout` elapses.
    fn wait_for_agent_healthy(&self, timeout: Duration) -> Result<()> {
        let container = format!("{}-test-indexer-agent-1", self.project_name);
        let start = Instant::now();
        let mut last_status = String::new();
        loop {
            if start.elapsed() > timeout {
                bail!(
                    "indexer-agent in {} did not become healthy within {:?} (last status: {last_status})",
                    self.project_name,
                    timeout,
                );
            }
            let out = Command::new("docker")
                .args([
                    "inspect",
                    "--format",
                    "{{.State.Health.Status}}",
                    &container,
                ])
                .output();
            if let Ok(o) = out {
                if o.status.success() {
                    last_status = String::from_utf8_lossy(&o.stdout).trim().to_string();
                    if last_status == "healthy" {
                        return Ok(());
                    }
                }
            }
            std::thread::sleep(Duration::from_secs(2));
        }
    }

    /// Tear down the compose project (`down -v`). Called automatically on
    /// `Drop` but exposed for explicit early teardown.
    pub fn down(&self) -> Result<()> {
        let status = Command::new("docker")
            .current_dir(&self.repo_root)
            .args([
                "compose",
                "-f",
                COMPOSE_FILE,
                "--project-name",
                &self.project_name,
                "--env-file",
                ".env",
                "down",
                "-v",
            ])
            .status()
            .context("spawning docker compose down")?;
        if !status.success() {
            bail!("docker compose down failed for {}", self.project_name);
        }
        Ok(())
    }

    // ----- management API helpers -----

    async fn management_query(&self, query: &str) -> Result<Value> {
        let client = reqwest::Client::new();
        let body = serde_json::json!({ "query": query });
        let resp = client
            .post(&self.management_url)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .context("sending management query")?;
        let status = resp.status();
        let json: Value = resp.json().await.context("parsing JSON response")?;
        if !status.is_success() {
            bail!("management API {status}: {json}");
        }
        if let Some(errors) = json.get("errors").and_then(|e| e.as_array()) {
            if !errors.is_empty() {
                bail!("management API GraphQL errors: {errors:?}");
            }
        }
        Ok(json)
    }

    /// Create an allocation for `deployment` (IPFS hash) with `amount` GRT.
    /// Retries the GraphQL mutation on transient agent-state errors that occur
    /// shortly after a close (the agent's nonce manager and active-allocation
    /// view can lag a few seconds behind chain confirmation).
    pub async fn create_allocation(&self, deployment: &str, amount: &str) -> Result<Value> {
        let query = format!(
            r#"mutation {{
                createAllocation(
                    deployment: "{deployment}",
                    amount: "{amount}",
                    protocolNetwork: "{PROTOCOL_NETWORK}"
                ) {{
                    allocation deployment allocatedTokens
                }}
            }}"#
        );
        // The agent's nonce/active-allocation state can take well over a minute
        // to settle after a close, especially on chains that have been
        // advanced by other tests. The wrapper keeps retrying transient
        // errors so callers don't have to special-case the agent's recovery.
        // Upstream agent's transactions.ts sleeps 30s internally on nonce
        // errors before returning IE058, so each effective retry costs ~30s.
        // 300s ≈ 9-10 attempts, enough to outwait the agent's tx pipeline.
        let deadline = Instant::now() + Duration::from_secs(300);
        loop {
            match self.management_query(&query).await {
                Ok(resp) => {
                    resp["data"]["createAllocation"]
                        .as_object()
                        .context("createAllocation returned null")?;
                    return Ok(resp["data"]["createAllocation"].clone());
                }
                Err(e) => {
                    let msg = format!("{e:#}");
                    let transient = msg.contains("nonce has already been used")
                        || msg.contains("Already allocating to the subgraph deployment");
                    if !transient || Instant::now() >= deadline {
                        return Err(e);
                    }
                    eprintln!("[create_allocation] transient error, retrying: {msg}");
                    tokio::time::sleep(Duration::from_secs(3)).await;
                }
            }
        }
    }

    /// Close an allocation. The `force=true` path needs an explicit block
    /// number from the indexer's own graph-node (otherwise auto-resolution
    /// returns null).
    ///
    /// Retries on transient agent-state errors: "No active allocation with
    /// provided id found" appears when the agent's allocation cache hasn't
    /// caught up to the chain yet (the per-test graph-node lags the chain
    /// after epoch advancement), and the chain-side nonce errors that the
    /// agent's tx pipeline can produce under load.
    pub async fn close_allocation(&self, allocation_id: &str) -> Result<Value> {
        // 300s budget — see comment on create_allocation; the agent's upstream
        // transactions.ts sleeps 30s on nonce errors so each retry is expensive.
        let deadline = Instant::now() + Duration::from_secs(300);
        loop {
            let block_number = self.subgraph_block_number().await?;
            let query = format!(
                r#"mutation {{
                    closeAllocation(
                        allocation: "{allocation_id}",
                        blockNumber: {block_number},
                        force: true,
                        protocolNetwork: "{PROTOCOL_NETWORK}"
                    ) {{
                        allocation allocatedTokens indexingRewards
                    }}
                }}"#
            );
            match self.management_query(&query).await {
                Ok(resp) => {
                    resp["data"]["closeAllocation"]
                        .as_object()
                        .context("closeAllocation returned null")?;
                    return Ok(resp["data"]["closeAllocation"].clone());
                }
                Err(e) => {
                    let msg = format!("{e:#}");
                    let transient = msg.contains("No active allocation with provided id found")
                        || msg.contains("nonce has already been used");
                    if !transient || Instant::now() >= deadline {
                        return Err(e);
                    }
                    eprintln!("[close_allocation] transient error, retrying: {msg}");
                    tokio::time::sleep(Duration::from_secs(3)).await;
                }
            }
        }
    }

    /// List allocations known to this indexer's management API.
    pub async fn get_allocations(&self) -> Result<Value> {
        let query = format!(
            r#"{{ indexerAllocations(protocolNetwork: "{PROTOCOL_NETWORK}") {{
                id subgraphDeployment allocatedTokens createdAtEpoch closedAtEpoch status
            }} }}"#
        );
        let resp = self.management_query(&query).await?;
        Ok(resp["data"]["indexerAllocations"].clone())
    }

    /// Query this indexer's total staked tokens from `HorizonStaking`. Read-only
    /// `cast call`, identical to `TestNetwork::staked_tokens` but for the
    /// per-test indexer's address.
    pub fn staked_tokens(&self, net: &TestNetwork) -> Result<u128> {
        let out = Command::new("cast")
            .args([
                "call",
                &format!("--rpc-url={}", net.rpc_url),
                &net.contracts.horizon_staking,
                "getStake(address)(uint256)",
                &self.address,
            ])
            .output()
            .context("running cast call getStake")?;
        if !out.status.success() {
            bail!(
                "cast call getStake failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
        }
        let stdout = String::from_utf8(out.stdout)?;
        // Output may include "[1e23]" suffix or other annotations — take the first token.
        let raw = stdout.split_whitespace().next().unwrap_or("");
        raw.parse().context("parsing staked tokens")
    }

    /// Self-toggle eligibility on `MockRewardsEligibilityOracle`. Signs with
    /// the per-test indexer's own key (the mock's `setEligible(bool)` keys
    /// off `msg.sender`). No-op error if mock REO isn't deployed/wired.
    pub fn set_eligible(&self, net: &TestNetwork, eligible: bool) -> Result<()> {
        let mock = net
            .contracts
            .reo_mock
            .as_deref()
            .context("MockRewardsEligibilityOracle not deployed (set REO_MOCK=1 in .env)")?;
        let out = Command::new("cast")
            .args([
                "send",
                &format!("--rpc-url={}", net.rpc_url),
                "--confirmations=0",
                &format!("--private-key={}", self.secret),
                mock,
                "setEligible(bool)",
                if eligible { "true" } else { "false" },
            ])
            .output()
            .context("running cast send setEligible")?;
        if !out.status.success() {
            bail!(
                "cast send setEligible failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
        }
        Ok(())
    }

    /// Call `SubgraphService.collect(indexer, IndexingRewards, data)` directly
    /// as the per-test indexer, bypassing the agent's close multicall.
    /// Mirrors `TestNetwork::collect_indexing_rewards` but signs with the
    /// per-test secret.
    pub fn collect_indexing_rewards(&self, net: &TestNetwork, allocation_id: &str) -> Result<()> {
        // Non-zero POI takes the CLAIMED reward path.
        let poi = "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658";
        let cmd = format!(
            "cast send --rpc-url={rpc} --confirmations=0 --private-key={key} \
             {ss} 'collect(address,uint8,bytes)' '{indexer}' 2 \
             $(cast abi-encode 'f(address,bytes32,bytes)' '{alloc}' '{poi}' '0x')",
            rpc = net.rpc_url,
            key = self.secret,
            ss = net.contracts.subgraph_service,
            indexer = self.address,
            alloc = allocation_id,
        );
        let out = Command::new("bash")
            .arg("-c")
            .arg(&cmd)
            .output()
            .context("running cast send collect")?;
        if !out.status.success() {
            bail!(
                "cast send collect failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
        }
        Ok(())
    }

    /// Latest indexed block from this indexer's network subgraph (per-test
    /// graph-node, not main).
    async fn subgraph_block_number(&self) -> Result<u64> {
        let client = reqwest::Client::new();
        let body = serde_json::json!({
            "query": "{ _meta { block { number } } }"
        });
        let resp: Value = client
            .post(&self.subgraph_url)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .context("querying network subgraph block")?
            .json()
            .await
            .context("parsing network subgraph block JSON")?;
        resp["data"]["_meta"]["block"]["number"]
            .as_u64()
            .context("missing _meta.block.number in subgraph response")
    }
}

impl Drop for IndexerHandle {
    fn drop(&mut self) {
        if let Err(e) = self.down() {
            eprintln!(
                "[IndexerHandle drop] tear-down failed for {}: {e:?}",
                self.project_name
            );
        }
    }
}

fn repo_root() -> Result<PathBuf> {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    Ok(manifest
        .parent()
        .context("expected tests/ inside repo root")?
        .to_path_buf())
}

/// `docker network connect cross-stack <devcontainer>` is a no-op if already
/// connected. Per-test agents are reachable via container name on this network.
fn ensure_devcontainer_on_cross_stack() -> Result<()> {
    let hostname = std::env::var("HOSTNAME").unwrap_or_default();
    if hostname.is_empty() {
        return Ok(());
    }
    let _ = Command::new("docker")
        .args(["network", "connect", "cross-stack", &hostname])
        .output();
    Ok(())
}

/// Generate a random 12-word mnemonic + index-0 wallet via `cast`.
fn generate_wallet() -> Result<(String, String, String)> {
    let out = Command::new("cast")
        .args(["wallet", "new-mnemonic", "--words", "12"])
        .output()
        .context("running cast wallet new-mnemonic")?;
    if !out.status.success() {
        bail!(
            "cast wallet new-mnemonic failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
    let stdout = String::from_utf8(out.stdout)?;
    let mut phrase = None;
    let mut address = None;
    let mut secret = None;
    let mut take_next_as_phrase = false;
    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed == "Phrase:" {
            take_next_as_phrase = true;
            continue;
        }
        if take_next_as_phrase && !trimmed.is_empty() {
            phrase = Some(trimmed.to_string());
            take_next_as_phrase = false;
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("Address:") {
            address = Some(rest.trim().to_string());
        } else if let Some(rest) = trimmed.strip_prefix("Private key:") {
            secret = Some(rest.trim().to_string());
        }
    }
    Ok((
        phrase.context("no Phrase: line in cast wallet output")?,
        address.context("no Address: line in cast wallet output")?,
        secret.context("no Private key: line in cast wallet output")?,
    ))
}

fn sanitize(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' {
                c
            } else {
                '-'
            }
        })
        .collect()
}
