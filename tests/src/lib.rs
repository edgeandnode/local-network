//! Integration test helpers for the local network.
//!
//! Provides `TestNetwork` — a typed interface to the local network services
//! (chain RPC, subgraph, gateway, indexer management API, contract calls).

pub mod cast;
pub mod graphql;
pub mod indexer;
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
    pub gateway_url: String,
    pub management_url: String,
    pub gateway_api_key: String,
    pub subgraph_id: String,
    pub indexer_address: String,
    /// The deployer's private key (DEPLOYER_SECRET). Holds DEFAULT_ADMIN_ROLE
    /// on most contracts because it deployed them; also gateway PaymentsEscrow
    /// payer. Not signed against at test runtime — admin operations use the
    /// role-specific keys below.
    pub deployer_secret: String,
    /// The governor's private key (GOVERNOR_SECRET). Needed for RewardsManager
    /// governance operations (setReclaimAddress, setMinimumSubgraphSignal, etc.)
    /// and is admin of REO PAUSE_ROLE / OPERATOR_ROLE.
    pub governor_secret: String,
    /// REO OPERATOR_ROLE signer (OPERATOR_SECRET). Used for setEligibilityPeriod,
    /// setEligibilityValidation, setOracleUpdateTimeout, and the permissionless
    /// rewards_on_subgraph_*_update calls.
    pub operator_secret: String,
    /// REO ORACLE_ROLE signer (ORACLE_SECRET). Used for renewIndexerEligibility.
    pub oracle_secret: String,
    /// The subgraph availability oracle's private key
    /// (SUBGRAPH_AVAILABILITY_ORACLE_SECRET). Needed for setDenied() on the
    /// RewardsManager. Derived from the deployment mnemonic (index 4).
    pub subgraph_availability_oracle_secret: String,
    /// REO PAUSE_ROLE signer (PAUSE_ADMIN_SECRET). Used for pause()/unpause().
    pub pause_admin_secret: String,
    /// The indexer's private key (INDEXER_SECRET). Needed for calling
    /// `collect()` on the SubgraphService (requires `onlyAuthorizedForProvision`).
    pub indexer_secret: String,
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
    /// Real RewardsEligibilityOracleA address (REO-A, with full
    /// renewal/period/operator-role mechanics).
    pub reo: Option<String>,
    /// MockRewardsEligibilityOracle address. The contract is always deployed
    /// by the GIP-0088 upgrade phase; whether it's actually wired as
    /// RewardsManager's providerEligibilityOracle is decided by the REO_MOCK
    /// flag in `.env` (default 1). Use `TestNetwork::is_mock_reo_live` to
    /// check the live wiring at runtime.
    pub reo_mock: Option<String>,
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
            .get("INDEXER_ADDRESS")
            .cloned()
            .context("INDEXER_ADDRESS not set in .env")?;
        let deployer_secret = vars
            .get("DEPLOYER_SECRET")
            .cloned()
            .context("DEPLOYER_SECRET not set in .env")?;
        let governor_secret = vars
            .get("GOVERNOR_SECRET")
            .cloned()
            .context("GOVERNOR_SECRET not set in .env")?;
        let operator_secret = vars
            .get("OPERATOR_SECRET")
            .cloned()
            .context("OPERATOR_SECRET not set in .env")?;
        let oracle_secret = vars
            .get("ORACLE_SECRET")
            .cloned()
            .context("ORACLE_SECRET not set in .env")?;
        let subgraph_availability_oracle_secret = vars
            .get("SUBGRAPH_AVAILABILITY_ORACLE_SECRET")
            .cloned()
            .context("SUBGRAPH_AVAILABILITY_ORACLE_SECRET not set in .env")?;
        let pause_admin_secret = vars
            .get("PAUSE_ADMIN_SECRET")
            .cloned()
            .context("PAUSE_ADMIN_SECRET not set in .env")?;
        let indexer_secret = vars
            .get("INDEXER_SECRET")
            .cloned()
            .context("INDEXER_SECRET not set in .env")?;
        let chain_id = vars
            .get("CHAIN_ID")
            .and_then(|v| v.parse().ok())
            .unwrap_or(1337);

        let contracts = load_contracts()?;

        Ok(Self {
            rpc_url,
            subgraph_url,
            block_oracle_subgraph_url,
            gateway_url,
            management_url,
            gateway_api_key,
            subgraph_id,
            indexer_address,
            deployer_secret,
            governor_secret,
            operator_secret,
            oracle_secret,
            subgraph_availability_oracle_secret,
            pause_admin_secret,
            indexer_secret,
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

/// Load `.env` (generated by `scripts/resolve-recipe.sh`) and optionally
/// `.env.local`, with `.env.local` values taking precedence. `.env` is
/// the active recipe's composed env; tests assume it exists (run `just up` or
/// `just resolve` to generate it).
fn load_env_files(repo_root: &Path) -> Result<HashMap<String, String>> {
    let resolved_path = repo_root.join(".env");
    let mut vars = if resolved_path.exists() {
        parse_env_file(&resolved_path)?
    } else {
        anyhow::bail!(
            ".env missing — run `just resolve` (or `just up`) first to \
             generate it from the active recipe"
        );
    };
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

    // REO addresses are in issuance.json (optional — may not be deployed)
    let issuance: Option<serde_json::Value> = docker_cat("graph-node", "/opt/config/issuance.json")
        .ok()
        .and_then(|json| serde_json::from_str::<serde_json::Value>(&json).ok());
    let reo = issuance.as_ref().and_then(|v| {
        v["1337"]["RewardsEligibilityOracleA"]["address"]
            .as_str()
            .map(String::from)
    });
    let reo_mock = issuance.as_ref().and_then(|v| {
        v["1337"]["RewardsEligibilityOracleMock"]["address"]
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
        reo_mock,
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
