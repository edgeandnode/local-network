//! Indexer management API helpers (indexer-agent GraphQL mutations).

use anyhow::{Context, Result};
use serde_json::Value;

use crate::TestNetwork;

/// Protocol network identifier for the local chain.
const PROTOCOL_NETWORK: &str = "eip155:1337";

impl TestNetwork {
    /// Create an allocation via the indexer management API.
    /// `deployment` is the IPFS hash (e.g., "QmXU9FEf...").
    /// `amount` is in GRT (e.g., "0.01").
    /// Returns the mutation result with `allocation` (ID), `deployment`, `allocatedTokens`.
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
        let resp = self.management_query(&query).await?;
        resp["data"]["createAllocation"]
            .as_object()
            .context("createAllocation returned null")?;
        Ok(resp["data"]["createAllocation"].clone())
    }

    /// Close an allocation via the indexer management API.
    ///
    /// Provides `blockNumber` explicitly because the indexer-agent's auto-resolution
    /// returns null when `force=true` is used without a block number.
    /// Uses the subgraph's latest indexed block (not the chain tip) to ensure
    /// graph-node has the block hash cached.
    /// Returns the mutation result with `allocation`, `allocatedTokens`, `indexingRewards`.
    pub async fn close_allocation(&self, allocation_id: &str) -> Result<Value> {
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
        let resp = self.management_query(&query).await?;
        resp["data"]["closeAllocation"]
            .as_object()
            .context("closeAllocation returned null")?;
        Ok(resp["data"]["closeAllocation"].clone())
    }

    /// Ensure at least one active allocation exists, creating one if a prior
    /// test panicked before restoring. Returns `(deployment_ipfs, allocation_id)`.
    pub async fn ensure_active_allocation(&self) -> Result<(String, String)> {
        let allocs = self.get_allocations().await?;
        let allocs = allocs.as_array().context("expected allocation array")?;

        if let Some(active) = allocs.iter().find(|a| a["closedAtEpoch"].is_null()) {
            let id = active["id"]
                .as_str()
                .context("allocation missing id")?
                .to_string();
            let dep = active["subgraphDeployment"]
                .as_str()
                .context("allocation missing deployment")?
                .to_string();
            return Ok((dep, id));
        }

        // No active allocation — recover from a closed allocation's deployment,
        // or from the network subgraph if the management API has no allocations at all.
        eprintln!("  WARNING: no active allocation — recovering from prior test failure");
        let deployment = if let Some(closed) = allocs.iter().rfind(|a| !a["closedAtEpoch"].is_null()) {
            closed["subgraphDeployment"]
                .as_str()
                .context("closed allocation missing deployment")?
                .to_string()
        } else {
            // No allocations at all — query the network subgraph for a signalled deployment
            eprintln!("  WARNING: no allocations at all — querying network subgraph for a deployment");
            let deployments = self.query_deployments_with_signal().await?;
            let deps = deployments.as_array().context("expected deployment array")?;
            let dep = deps.first().context("no signalled deployments found")?;
            dep["ipfsHash"]
                .as_str()
                .context("deployment missing ipfsHash")?
                .to_string()
        };

        let result = self.create_allocation(&deployment, "0.01").await?;
        let id = result["allocation"]
            .as_str()
            .context("expected allocation ID")?
            .to_string();
        eprintln!("  Recovered: created allocation {id} for {deployment}");

        Ok((deployment, id))
    }

    /// Get allocations from the indexer management API.
    pub async fn get_allocations(&self) -> Result<Value> {
        let query = format!(
            r#"{{ indexerAllocations(protocolNetwork: "{PROTOCOL_NETWORK}") {{
                id subgraphDeployment allocatedTokens createdAtEpoch closedAtEpoch status
            }} }}"#
        );
        let resp = self.management_query(&query).await?;
        Ok(resp["data"]["indexerAllocations"].clone())
    }
}
