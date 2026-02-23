//! Polling, retry, block mining, and epoch advancement helpers.

use anyhow::{Context, Result};
use std::future::Future;
use std::time::{Duration, Instant};

use crate::TestNetwork;
use crate::cast::cast_parse_uint;

/// Result of a `poll_until` call.
#[derive(Debug)]
pub enum PollResult<T> {
    /// Condition was met, with the final value.
    Ready(T),
    /// Timed out before the condition was met.
    TimedOut,
}

impl<T> PollResult<T> {
    pub fn unwrap(self) -> T {
        match self {
            PollResult::Ready(v) => v,
            PollResult::TimedOut => panic!("poll_until timed out"),
        }
    }

    pub fn is_ready(&self) -> bool {
        matches!(self, PollResult::Ready(_))
    }
}

impl TestNetwork {
    /// Poll a condition until it returns `Some(T)` or the timeout expires.
    pub async fn poll_until<T, F, Fut>(
        &self,
        timeout: Duration,
        interval: Duration,
        mut check: F,
    ) -> PollResult<T>
    where
        F: FnMut() -> Fut,
        Fut: Future<Output = Result<Option<T>>>,
    {
        let start = Instant::now();
        loop {
            match check().await {
                Ok(Some(value)) => return PollResult::Ready(value),
                Ok(None) => {}
                Err(e) => {
                    eprintln!("poll_until check error (continuing): {e:#}");
                }
            }
            if start.elapsed() >= timeout {
                return PollResult::TimedOut;
            }
            tokio::time::sleep(interval).await;
        }
    }

    /// Mine `count` blocks, advancing chain time by 12s per block (mimics Ethereum).
    pub async fn mine_blocks(&self, count: u32) -> Result<()> {
        let client = reqwest::Client::new();
        for _ in 0..count {
            // Advance time by 12 seconds
            client
                .post(&self.rpc_url)
                .json(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "evm_increaseTime",
                    "params": [12],
                    "id": 1
                }))
                .send()
                .await
                .context("evm_increaseTime")?;

            // Mine the block
            client
                .post(&self.rpc_url)
                .json(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "evm_mine",
                    "params": [],
                    "id": 2
                }))
                .send()
                .await
                .context("evm_mine")?;
        }
        Ok(())
    }

    /// Advance N epochs by mining blocks one epoch at a time.
    ///
    /// Advances one epoch per iteration, waiting for the block-oracle to process
    /// each transition. This avoids gaps in the block-oracle subgraph which would
    /// cause the indexer-agent to fail when closing allocations (it needs block
    /// hashes for every epoch boundary).
    ///
    /// Returns the new epoch number.
    pub async fn advance_epochs(&self, n: u32) -> Result<u64> {
        let em = &self.contracts.epoch_manager;
        let raw = self.cast_call(em, "epochLength()(uint256)", &[])?;
        let epoch_length: u64 = cast_parse_uint(&raw)
            .parse()
            .context("parsing epochLength")?;

        let mut new_epoch = 0u64;
        for i in 0..n {
            let raw = self.cast_call(em, "currentEpoch()(uint256)", &[])?;
            let current_epoch: u64 = cast_parse_uint(&raw)
                .parse()
                .context("parsing currentEpoch")?;
            let current_block: u64 = self.get_block_number().await?;
            let raw = self.cast_call(em, "currentEpochBlock()(uint256)", &[])?;
            let epoch_block: u64 = cast_parse_uint(&raw)
                .parse()
                .context("parsing currentEpochBlock")?;

            let blocks_in_epoch = current_block.saturating_sub(epoch_block);
            let blocks_to_mine = epoch_length - blocks_in_epoch;

            eprintln!(
                "advance_epochs: step {}/{n}, epoch={current_epoch}, \
                 mining {blocks_to_mine} blocks",
                i + 1
            );

            self.mine_blocks(blocks_to_mine as u32).await?;

            // Emit the EpochRun event so the network subgraph updates.
            self.cast_send(em, "runEpoch()", &[])?;

            let raw = self.cast_call(em, "currentEpoch()(uint256)", &[])?;
            new_epoch = cast_parse_uint(&raw)
                .parse()
                .context("parsing new currentEpoch")?;

            // Wait for both subgraphs to index this epoch before advancing further.
            // The block-oracle needs to process each epoch individually to avoid gaps.
            self.wait_for_epoch_sync(new_epoch).await?;
        }

        Ok(new_epoch)
    }

    /// Wait until both the network subgraph and block-oracle subgraph reflect
    /// `target_epoch`. Mines a block each iteration to provide confirmations
    /// for the block-oracle's DataEdge transactions on the automine chain.
    async fn wait_for_epoch_sync(&self, target_epoch: u64) -> Result<()> {
        let timeout = Duration::from_secs(120);
        let interval = Duration::from_secs(2);
        let start = Instant::now();

        let mut network_ready = false;
        let mut oracle_ready = false;
        let mut resumed = false;

        loop {
            if !network_ready {
                let network = self.query_network().await?;
                let subgraph_epoch = network["currentEpoch"]
                    .as_u64()
                    .or_else(|| {
                        network["currentEpoch"]
                            .as_str()
                            .and_then(|s| s.parse().ok())
                    })
                    .unwrap_or(0);
                if subgraph_epoch >= target_epoch {
                    network_ready = true;
                }
            }

            if !oracle_ready {
                match self.block_oracle_has_epoch(target_epoch).await {
                    Ok(true) => oracle_ready = true,
                    Ok(false) => {}
                    Err(e) => {
                        eprintln!("  block-oracle check error (continuing): {e:#}");
                    }
                }
            }

            if network_ready && oracle_ready {
                return Ok(());
            }

            if start.elapsed() >= timeout {
                anyhow::bail!(
                    "Epoch sync to {target_epoch} timed out after {timeout:?} \
                     (network_subgraph={network_ready}, block_oracle={oracle_ready})"
                );
            }

            // The indexer-agent may pause subgraphs during testing. If the
            // network subgraph hasn't caught up after 15s, resume all subgraphs.
            if !network_ready && !resumed && start.elapsed() >= Duration::from_secs(15) {
                eprintln!("  Subgraph slow to sync — resuming subgraphs...");
                self.resume_subgraphs().await;
                resumed = true;
            }

            // Mine a block to provide confirmations for block-oracle DataEdge txs
            self.mine_blocks(1).await?;
            tokio::time::sleep(interval).await;
        }
    }

    /// Resume all known subgraphs via graph-node admin API.
    /// The indexer-agent may pause subgraphs during test runs; this ensures
    /// they keep indexing.
    async fn resume_subgraphs(&self) {
        let admin_url = self
            .subgraph_url
            .replace(":8000/subgraphs/name/graph-network", ":8020/");
        let client = reqwest::Client::new();
        for name in ["graph-network", "block-oracle", "semiotic/tap"] {
            // Get the deployment ID for this subgraph
            let meta_url = self.subgraph_url.replace("graph-network", name);
            let meta_resp = client
                .post(&meta_url)
                .header("content-type", "application/json")
                .json(&serde_json::json!({"query": "{ _meta { deployment } }"}))
                .send()
                .await;
            let deployment = match meta_resp {
                Ok(resp) => {
                    let json: serde_json::Value = match resp.json().await {
                        Ok(j) => j,
                        Err(_) => continue,
                    };
                    match json["data"]["_meta"]["deployment"].as_str() {
                        Some(d) => d.to_string(),
                        None => continue,
                    }
                }
                Err(_) => continue,
            };
            let _ = client
                .post(&admin_url)
                .header("content-type", "application/json")
                .json(&serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "subgraph_resume",
                    "params": {"deployment": deployment},
                    "id": 1
                }))
                .send()
                .await;
        }
    }

    /// Advance chain time by `seconds` and mine one block.
    /// Useful for expiring eligibility periods without mining many blocks.
    pub async fn advance_time(&self, seconds: u64) -> Result<()> {
        let client = reqwest::Client::new();
        client
            .post(&self.rpc_url)
            .json(&serde_json::json!({
                "jsonrpc": "2.0",
                "method": "evm_increaseTime",
                "params": [seconds],
                "id": 1
            }))
            .send()
            .await
            .context("evm_increaseTime")?;
        client
            .post(&self.rpc_url)
            .json(&serde_json::json!({
                "jsonrpc": "2.0",
                "method": "evm_mine",
                "params": [],
                "id": 2
            }))
            .send()
            .await
            .context("evm_mine")?;
        Ok(())
    }

    /// Get the latest block number from the chain.
    pub async fn get_block_number(&self) -> Result<u64> {
        let client = reqwest::Client::new();
        let resp: serde_json::Value = client
            .post(&self.rpc_url)
            .json(&serde_json::json!({
                "jsonrpc": "2.0",
                "method": "eth_blockNumber",
                "params": [],
                "id": 1
            }))
            .send()
            .await
            .context("eth_blockNumber")?
            .json()
            .await
            .context("parsing eth_blockNumber response")?;

        let hex = resp["result"]
            .as_str()
            .context("eth_blockNumber result not a string")?;
        let num = u64::from_str_radix(hex.trim_start_matches("0x"), 16)
            .context("parsing hex block number")?;
        Ok(num)
    }
}
