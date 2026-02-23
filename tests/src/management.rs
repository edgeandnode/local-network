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
