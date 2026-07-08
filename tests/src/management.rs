//! Indexer management API helpers (indexer-agent GraphQL mutations).

use anyhow::{Context, Result};
use serde_json::Value;

use crate::TestNetwork;

/// Protocol network identifier for the local chain.
const PROTOCOL_NETWORK: &str = "eip155:1337";

/// Allocation amount stamped on repaired rules: 0.01 GRT in wei, the same
/// amount every test allocation uses.
const REPAIR_ALLOCATION_AMOUNT_WEI: &str = "10000000000000000";

/// Run a test body and, on failure, restore an active allocation and an
/// `always` rule so later tests inherit a working stack. Best-effort: a
/// repair error is logged but never masks the test's own error.
pub async fn restore_allocation_on_failure<F>(net: &TestNetwork, body: F) -> Result<()>
where
    F: std::future::Future<Output = Result<()>>,
{
    let result = body.await;
    if result.is_err() {
        match net.ensure_active_allocation().await {
            Ok((deployment, id)) => {
                eprintln!("  [restore] active allocation {id} on {deployment}")
            }
            Err(err) => eprintln!("  [restore] could not restore allocation state: {err}"),
        }
    }
    result
}

impl TestNetwork {
    /// Create an allocation via the indexer management API. `deployment` is the
    /// IPFS hash (e.g., "QmXU9FEf..."); `amount` is in GRT (e.g., "0.01").
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

    /// Close an allocation via the indexer management API. Passes `blockNumber`
    /// explicitly (agent auto-resolution returns null with `force=true`), using the
    /// subgraph's latest indexed block so graph-node has the block hash cached.
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
            // An active allocation can coexist with a stale opt-out rule (a test
            // aborting between the rule stamp and the on-chain close), so repair
            // the rule even when no allocation needs recreating.
            self.ensure_always_rule(&dep).await?;
            return Ok((dep, id));
        }

        // No active allocation — recover from a closed allocation's deployment,
        // or from the network subgraph if the management API has no allocations at all.
        eprintln!("  WARNING: no active allocation — recovering from prior test failure");
        let deployment =
            if let Some(closed) = allocs.iter().rfind(|a| !a["closedAtEpoch"].is_null()) {
                closed["subgraphDeployment"]
                    .as_str()
                    .context("closed allocation missing deployment")?
                    .to_string()
            } else {
                // No allocations at all — query the network subgraph for a signalled deployment
                eprintln!(
                    "  WARNING: no allocations at all — querying network subgraph for a deployment"
                );
                let deployments = self.query_deployments_with_signal().await?;
                let deps = deployments
                    .as_array()
                    .context("expected deployment array")?;
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

    /// Decision basis of the deployment's indexing rule, if one exists.
    pub async fn indexing_rule_decision(&self, deployment: &str) -> Result<Option<String>> {
        let query = format!(
            r#"{{ indexingRule(
                identifier: {{ identifier: "{deployment}", protocolNetwork: "{PROTOCOL_NETWORK}" }},
                merged: false
            ) {{ decisionBasis }} }}"#
        );
        let resp = self.management_query(&query).await?;
        Ok(resp["data"]["indexingRule"]["decisionBasis"]
            .as_str()
            .map(String::from))
    }

    /// Restore the deployment's indexing rule to `always` if it isn't already.
    /// closeAllocation stamps `offchain` before the on-chain close, so a test
    /// aborting in between strands a rule that also blocklists DIPs proposals.
    pub async fn ensure_always_rule(&self, deployment: &str) -> Result<()> {
        let basis = self.indexing_rule_decision(deployment).await?;
        if basis.as_deref() == Some("always") {
            return Ok(());
        }
        eprintln!(
            "  WARNING: indexing rule for {deployment} was {} — restoring always",
            basis.as_deref().unwrap_or("absent")
        );
        let query = format!(
            r#"mutation {{
                setIndexingRule(
                    identifier: "{deployment}",
                    rule: {{
                        identifier: "{deployment}",
                        identifierType: deployment,
                        allocationAmount: "{REPAIR_ALLOCATION_AMOUNT_WEI}",
                        decisionBasis: always,
                        protocolNetwork: "{PROTOCOL_NETWORK}"
                    }}
                ) {{ identifier decisionBasis }}
            }}"#
        );
        let resp = self.management_query(&query).await?;
        resp["data"]["setIndexingRule"]
            .as_object()
            .context("setIndexingRule returned null")?;
        Ok(())
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
