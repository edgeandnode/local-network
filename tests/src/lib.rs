//! Integration test helpers for the local network.
//!
//! Provides `TestNetwork` — a typed interface to the local network services
//! (chain RPC, subgraph, gateway, indexer management API, contract calls).

pub mod cast;
pub mod graphql;
pub mod management;
pub mod polling;
pub mod staking;

use anyhow::{Context, Result};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Typed interface to a running local network.
///
/// Created from environment variables (`.env` + `.env.local`).
/// All URLs default to devcontainer-friendly hostnames (service names on the
/// Docker network) with fallback to localhost for host-side execution.
#[derive(Debug, Clone)]
pub struct TestNetwork {
    pub rpc_url: String,
    pub subgraph_url: String,
    pub block_oracle_subgraph_url: String,
    pub tap_subgraph_url: String,
    pub gateway_url: String,
    pub management_url: String,
    pub gateway_api_key: String,
    pub subgraph_id: String,
    pub indexer_address: String,
    pub account0_secret: String,
    /// The indexer's private key (RECEIVER_SECRET). Needed for calling
    /// `collect()` on the SubgraphService (requires `onlyAuthorizedForProvision`).
    pub receiver_secret: String,
    pub chain_id: u64,
    /// Contract addresses loaded from config-local volume via `docker exec`.
    pub contracts: Contracts,
}

/// Contract addresses loaded from the config-local Docker volume.
#[derive(Debug, Clone, Default)]
pub struct Contracts {
    pub epoch_manager: String,
    pub rewards_manager: String,
    pub horizon_staking: String,
    pub subgraph_service: String,
    pub payments_escrow: String,
    pub grt_token: String,
    pub reo: Option<String>,
}

impl TestNetwork {
    /// Build a `TestNetwork` from `.env` (and `.env.local` if present).
    ///
    /// Expects to be called from the repo root, or with `repo_root` pointing there.
    pub fn from_env(repo_root: &Path) -> Result<Self> {
        let vars = load_env_files(repo_root)?;

        let chain_host = std::env::var("CHAIN_HOST").unwrap_or_else(|_| {
            vars.get("CHAIN_HOST")
                .cloned()
                .unwrap_or("localhost".into())
        });
        let chain_port = vars.get("CHAIN_RPC_PORT").cloned().unwrap_or("8545".into());
        let graph_host = std::env::var("GRAPH_NODE_HOST").unwrap_or_else(|_| {
            vars.get("GRAPH_NODE_HOST")
                .cloned()
                .unwrap_or("localhost".into())
        });
        let graph_port = vars
            .get("GRAPH_NODE_GRAPHQL_PORT")
            .cloned()
            .unwrap_or("8000".into());
        let gateway_host = std::env::var("GATEWAY_HOST").unwrap_or_else(|_| {
            vars.get("GATEWAY_HOST")
                .cloned()
                .unwrap_or("localhost".into())
        });
        let gateway_port = vars.get("GATEWAY_PORT").cloned().unwrap_or("7700".into());
        let mgmt_host = std::env::var("INDEXER_AGENT_HOST").unwrap_or_else(|_| {
            vars.get("INDEXER_AGENT_HOST")
                .cloned()
                .unwrap_or("localhost".into())
        });
        let mgmt_port = vars
            .get("INDEXER_MANAGEMENT_PORT")
            .cloned()
            .unwrap_or("7600".into());

        let rpc_url = format!("http://{chain_host}:{chain_port}");
        let subgraph_url = format!("http://{graph_host}:{graph_port}/subgraphs/name/graph-network");
        let block_oracle_subgraph_url =
            format!("http://{graph_host}:{graph_port}/subgraphs/name/block-oracle");
        let tap_subgraph_url =
            format!("http://{graph_host}:{graph_port}/subgraphs/name/semiotic/tap");
        let gateway_url = format!("http://{gateway_host}:{gateway_port}");
        let management_url = format!("http://{mgmt_host}:{mgmt_port}");

        let gateway_api_key = vars
            .get("GATEWAY_API_KEY")
            .cloned()
            .unwrap_or("deadbeefdeadbeefdeadbeefdeadbeef".into());
        let subgraph_id = vars
            .get("SUBGRAPH")
            .cloned()
            .context("SUBGRAPH not set in .env")?;
        let indexer_address = vars
            .get("RECEIVER_ADDRESS")
            .cloned()
            .context("RECEIVER_ADDRESS not set in .env")?;
        let account0_secret = vars
            .get("ACCOUNT0_SECRET")
            .cloned()
            .context("ACCOUNT0_SECRET not set in .env")?;
        let receiver_secret = vars
            .get("RECEIVER_SECRET")
            .cloned()
            .context("RECEIVER_SECRET not set in .env")?;
        let chain_id = vars
            .get("CHAIN_ID")
            .and_then(|v| v.parse().ok())
            .unwrap_or(1337);

        let contracts = load_contracts()?;

        Ok(Self {
            rpc_url,
            subgraph_url,
            block_oracle_subgraph_url,
            tap_subgraph_url,
            gateway_url,
            management_url,
            gateway_api_key,
            subgraph_id,
            indexer_address,
            account0_secret,
            receiver_secret,
            chain_id,
            contracts,
        })
    }

    /// Convenience: build from the default repo root (two levels up from this crate).
    pub fn from_default_env() -> Result<Self> {
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest
            .parent()
            .context("tests/ crate must be inside the repo root")?;
        Self::from_env(repo_root)
    }
}

/// Parse a simple `.env` file (KEY=VALUE, ignoring comments and blank lines).
/// Does NOT handle shell expansion like `${VAR}`.
fn parse_env_file(path: &Path) -> Result<HashMap<String, String>> {
    let content =
        std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
    let mut map = HashMap::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = trimmed.split_once('=') {
            let key = key.trim();
            let value = value.trim().trim_matches('"');
            // Skip lines that use shell variable expansion (e.g. ${FOO})
            if !value.contains("${") {
                map.insert(key.to_string(), value.to_string());
            }
        }
    }
    Ok(map)
}

/// Load `.env` and optionally `.env.local`, with `.env.local` values taking precedence.
fn load_env_files(repo_root: &Path) -> Result<HashMap<String, String>> {
    let mut vars = parse_env_file(&repo_root.join(".env"))?;
    let local_path = repo_root.join(".env.local");
    if local_path.exists() {
        let local_vars = parse_env_file(&local_path)?;
        vars.extend(local_vars);
    }
    Ok(vars)
}

/// Load contract addresses from the config-local Docker volume via `docker exec`.
fn load_contracts() -> Result<Contracts> {
    let horizon_json = docker_cat("graph-node", "/opt/config/horizon.json")
        .context("reading horizon.json from graph-node container")?;
    let horizon: serde_json::Value =
        serde_json::from_str(&horizon_json).context("parsing horizon.json")?;

    let epoch_manager = horizon["1337"]["EpochManager"]["address"]
        .as_str()
        .context("EpochManager address not found in horizon.json")?
        .to_string();

    let rewards_manager = horizon["1337"]["RewardsManager"]["address"]
        .as_str()
        .context("RewardsManager address not found in horizon.json")?
        .to_string();

    let horizon_staking = horizon["1337"]["HorizonStaking"]["address"]
        .as_str()
        .context("HorizonStaking address not found in horizon.json")?
        .to_string();

    let payments_escrow = horizon["1337"]["PaymentsEscrow"]["address"]
        .as_str()
        .context("PaymentsEscrow address not found in horizon.json")?
        .to_string();

    let grt_token = horizon["1337"]["L2GraphToken"]["address"]
        .as_str()
        .context("L2GraphToken address not found in horizon.json")?
        .to_string();

    // SubgraphService is in a separate address book
    let ss_json = docker_cat("graph-node", "/opt/config/subgraph-service.json")
        .context("reading subgraph-service.json from graph-node container")?;
    let ss: serde_json::Value =
        serde_json::from_str(&ss_json).context("parsing subgraph-service.json")?;
    let subgraph_service = ss["1337"]["SubgraphService"]["address"]
        .as_str()
        .context("SubgraphService address not found in subgraph-service.json")?
        .to_string();

    // REO address is in issuance.json (optional — may not be deployed)
    let reo = docker_cat("graph-node", "/opt/config/issuance.json")
        .ok()
        .and_then(|json| serde_json::from_str::<serde_json::Value>(&json).ok())
        .and_then(|v| {
            v["1337"]["RewardsEligibilityOracle"]["address"]
                .as_str()
                .map(String::from)
        });

    Ok(Contracts {
        epoch_manager,
        rewards_manager,
        horizon_staking,
        subgraph_service,
        payments_escrow,
        grt_token,
        reo,
    })
}

/// Read a file from a running Docker container.
fn docker_cat(container: &str, path: &str) -> Result<String> {
    let output = std::process::Command::new("docker")
        .args(["exec", container, "cat", path])
        .output()
        .context("running docker exec")?;
    if !output.status.success() {
        anyhow::bail!(
            "docker exec {} cat {} failed: {}",
            container,
            path,
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(String::from_utf8(output.stdout)?)
}
