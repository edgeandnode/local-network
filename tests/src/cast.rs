//! Wrapper around the `cast` CLI (Foundry) for contract calls and transactions.

use anyhow::{Context, Result};
use std::process::Command;

use crate::TestNetwork;

impl TestNetwork {
    /// Read-only contract call via `cast call`.
    /// Returns the raw stdout (decoded return value).
    pub fn cast_call(&self, to: &str, sig: &str, args: &[&str]) -> Result<String> {
        let mut cmd = Command::new("cast");
        cmd.arg("call")
            .arg(format!("--rpc-url={}", self.rpc_url))
            .arg(to)
            .arg(sig);
        for arg in args {
            cmd.arg(arg);
        }
        run_command(&mut cmd)
    }

    /// State-changing transaction via `cast send`.
    /// Uses `account0_secret` as the signer. Returns stdout.
    pub fn cast_send(&self, to: &str, sig: &str, args: &[&str]) -> Result<String> {
        let mut cmd = Command::new("cast");
        cmd.arg("send")
            .arg(format!("--rpc-url={}", self.rpc_url))
            .arg("--confirmations=0")
            .arg(format!("--private-key={}", self.account0_secret))
            .arg(to)
            .arg(sig);
        for arg in args {
            cmd.arg(arg);
        }
        run_command(&mut cmd)
    }

    /// Check if an address is eligible via the REO contract.
    pub fn reo_is_eligible(&self, address: &str) -> Result<bool> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(reo, "isEligible(address)(bool)", &[address])?;
        Ok(output.trim() == "true")
    }

    /// Check if eligibility validation is enabled on the REO contract.
    pub fn reo_validation_enabled(&self) -> Result<bool> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(reo, "getEligibilityValidation()(bool)", &[])?;
        Ok(output.trim() == "true")
    }

    /// Get the last oracle update time from the REO contract.
    pub fn reo_last_oracle_update(&self) -> Result<u64> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(reo, "getLastOracleUpdateTime()(uint256)", &[])?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing lastOracleUpdateTime")
    }

    /// Seed the REO lastOracleUpdateTime by calling renewIndexerEligibility with
    /// an empty array. Requires ORACLE_ROLE (account0).
    pub fn reo_seed_oracle_timestamp(&self) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        self.cast_send(
            &reo,
            "renewIndexerEligibility(address[],bytes)",
            &["[]", "0x"],
        )?;
        Ok(())
    }

    /// Renew eligibility for a specific indexer. Requires ORACLE_ROLE (account0).
    pub fn reo_renew_indexer(&self, address: &str) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        let array = format!("[{address}]");
        self.cast_send(
            &reo,
            "renewIndexerEligibility(address[],bytes)",
            &[&array, "0x"],
        )?;
        Ok(())
    }

    /// Get the eligibility period (seconds) from the REO contract.
    pub fn reo_eligibility_period(&self) -> Result<u64> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(reo, "getEligibilityPeriod()(uint256)", &[])?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing eligibilityPeriod")
    }

    /// State-changing transaction via `cast send`, signed by an arbitrary private key.
    pub fn cast_send_as(&self, key: &str, to: &str, sig: &str, args: &[&str]) -> Result<String> {
        let mut cmd = Command::new("cast");
        cmd.arg("send")
            .arg(format!("--rpc-url={}", self.rpc_url))
            .arg("--confirmations=0")
            .arg(format!("--private-key={key}"))
            .arg(to)
            .arg(sig);
        for arg in args {
            cmd.arg(arg);
        }
        run_command(&mut cmd)
    }

    /// Try a `cast send` and return Ok(true) if it succeeds, Ok(false) if it reverts.
    pub fn cast_send_may_revert(
        &self,
        key: &str,
        to: &str,
        sig: &str,
        args: &[&str],
    ) -> Result<bool> {
        match self.cast_send_as(key, to, sig, args) {
            Ok(_) => Ok(true),
            Err(e) => {
                let msg = format!("{e:#}");
                if msg.contains("revert") || msg.contains("execution reverted") {
                    Ok(false)
                } else {
                    Err(e)
                }
            }
        }
    }

    /// State-changing transaction via `cast send`, signed by `receiver_secret` (the indexer).
    /// Needed for operations that require `onlyAuthorizedForProvision`.
    pub fn cast_send_as_indexer(&self, to: &str, sig: &str, args: &[&str]) -> Result<String> {
        let mut cmd = Command::new("cast");
        cmd.arg("send")
            .arg(format!("--rpc-url={}", self.rpc_url))
            .arg("--confirmations=0")
            .arg(format!("--private-key={}", self.receiver_secret))
            .arg(to)
            .arg(sig);
        for arg in args {
            cmd.arg(arg);
        }
        run_command(&mut cmd)
    }

    /// Collect indexing rewards for an allocation via `SubgraphService.collect()`.
    ///
    /// `closeAllocation` does NOT collect rewards — it reclaims them.
    /// This function calls `collect(indexer, PaymentTypes.IndexingRewards, data)` directly,
    /// which calls `takeRewards()` and mints GRT to the indexer's stake.
    ///
    /// Must be called BEFORE closing the allocation.
    /// Requires calling as the indexer (RECEIVER_SECRET) due to `onlyAuthorizedForProvision`.
    pub fn collect_indexing_rewards(&self, allocation_id: &str) -> Result<String> {
        let ss = &self.contracts.subgraph_service;
        // PaymentTypes.IndexingRewards = 2
        // data = abi.encode(address allocationId, bytes32 poi, bytes poiMetadata)
        // Use a non-zero POI (keccak of "test") so it takes the CLAIMED path
        let poi = "0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658";
        // Build the full call: collect(address indexer, uint8 paymentType, bytes data)
        let mut cmd = Command::new("bash");
        cmd.arg("-c").arg(format!(
            "cast send --rpc-url={rpc} --confirmations=0 --private-key={key} \
             {ss} 'collect(address,uint8,bytes)' '{indexer}' 2 \
             $(cast abi-encode 'f(address,bytes32,bytes)' '{alloc}' '{poi}' '0x')",
            rpc = self.rpc_url,
            key = self.receiver_secret,
            ss = ss,
            indexer = self.indexer_address,
            alloc = allocation_id,
            poi = poi,
        ));
        run_command(&mut cmd)
    }

    /// Query the indexer's total staked tokens from the HorizonStaking contract.
    pub fn staked_tokens(&self) -> Result<u128> {
        let output = self.cast_call(
            &self.contracts.horizon_staking,
            "getStake(address)(uint256)",
            &[&self.indexer_address],
        )?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing staked tokens")
    }

    // --- REO Governance Operations (ReoTestPlan Cycles 3-5, 7) ---

    /// Set eligibility validation on/off. Requires OPERATOR_ROLE (account0).
    /// ReoTestPlan 4.1 (enable) / 7.2 (disable).
    pub fn reo_set_validation(&self, enabled: bool) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        self.cast_send(
            &reo,
            "setEligibilityValidation(bool)",
            &[if enabled { "true" } else { "false" }],
        )?;
        Ok(())
    }

    /// Set the eligibility period (seconds). Requires OPERATOR_ROLE (account0).
    /// ReoTestPlan 4.4.
    pub fn reo_set_eligibility_period(&self, seconds: u64) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        self.cast_send(
            &reo,
            "setEligibilityPeriod(uint256)",
            &[&seconds.to_string()],
        )?;
        Ok(())
    }

    /// Get the oracle update timeout (seconds). ReoTestPlan 1.3.
    pub fn reo_oracle_timeout(&self) -> Result<u64> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(reo, "getOracleUpdateTimeout()(uint256)", &[])?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing oracleUpdateTimeout")
    }

    /// Set the oracle update timeout (seconds). Requires OPERATOR_ROLE (account0).
    /// ReoTestPlan 5.1.
    pub fn reo_set_oracle_timeout(&self, seconds: u64) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        self.cast_send(
            &reo,
            "setOracleUpdateTimeout(uint256)",
            &[&seconds.to_string()],
        )?;
        Ok(())
    }

    /// Pause the REO contract. Requires PAUSE_ROLE (account0 on local network).
    /// ReoTestPlan 7.1.
    pub fn reo_pause(&self) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        self.cast_send(&reo, "pause()", &[])?;
        Ok(())
    }

    /// Unpause the REO contract. Requires PAUSE_ROLE.
    /// ReoTestPlan 7.1.
    pub fn reo_unpause(&self) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        self.cast_send(&reo, "unpause()", &[])?;
        Ok(())
    }

    /// Check if the REO contract is paused. ReoTestPlan 1.5 / 7.1.
    pub fn reo_is_paused(&self) -> Result<bool> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(reo, "paused()(bool)", &[])?;
        Ok(output.trim() == "true")
    }

    /// Renew eligibility for multiple indexers in a batch. ReoTestPlan 3.3.
    pub fn reo_renew_batch(&self, addresses: &[&str]) -> Result<()> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?
            .to_string();
        let array = format!("[{}]", addresses.join(","));
        self.cast_send(
            &reo,
            "renewIndexerEligibility(address[],bytes)",
            &[&array, "0x"],
        )?;
        Ok(())
    }

    /// Get the eligibility renewal time for an indexer. ReoTestPlan 3.2.
    pub fn reo_renewal_time(&self, address: &str) -> Result<u64> {
        let reo = self
            .contracts
            .reo
            .as_deref()
            .context("REO contract not deployed")?;
        let output = self.cast_call(
            reo,
            "getEligibilityRenewalTime(address)(uint256)",
            &[address],
        )?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing eligibilityRenewalTime")
    }

    /// Check the RewardsManager → REO integration. ReoTestPlan 1.4.
    pub fn rewards_manager_reo_address(&self) -> Result<String> {
        let output = self.cast_call(
            &self.contracts.rewards_manager,
            "getRewardsEligibilityOracle()(address)",
            &[],
        )?;
        Ok(output.trim().to_string())
    }

    /// Get the latest block timestamp from the chain.
    pub fn get_block_timestamp(&self) -> Result<u64> {
        let output = run_command(
            Command::new("cast")
                .arg("block")
                .arg("latest")
                .arg("--field=timestamp")
                .arg(format!("--rpc-url={}", self.rpc_url)),
        )?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing block timestamp")
    }

    // --- Rewards View Functions (ReoTestPlan Cycle 6) ---

    /// Query pending rewards for an allocation via RewardsManager.getRewards().
    /// ReoTestPlan 6.5: view functions should return 0 for ineligible indexers.
    pub fn rewards_pending(&self, allocation_id: &str) -> Result<u128> {
        let output = self.cast_call(
            &self.contracts.rewards_manager,
            "getRewards(address,address)(uint256)",
            &[&self.contracts.subgraph_service, allocation_id],
        )?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing pending rewards")
    }

    // --- Utility helpers ---

    /// Get the latest block number (sync, via cast).
    pub fn get_block_number_sync(&self) -> Result<u64> {
        let output = run_command(
            Command::new("cast")
                .arg("block-number")
                .arg(format!("--rpc-url={}", self.rpc_url)),
        )?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing block number")
    }

    /// Query event logs in a block range for a specific contract address.
    /// Returns parsed JSON log objects.
    pub fn cast_logs_json(
        &self,
        address: &str,
        from_block: u64,
        to_block: u64,
    ) -> Result<Vec<serde_json::Value>> {
        let mut cmd = Command::new("cast");
        cmd.arg("logs")
            .arg("--json")
            .arg(format!("--from-block={from_block}"))
            .arg(format!("--to-block={to_block}"))
            .arg(format!("--address={address}"))
            .arg(format!("--rpc-url={}", self.rpc_url));
        let output = run_command(&mut cmd)?;
        let logs: Vec<serde_json::Value> =
            serde_json::from_str(&output).context("parsing cast logs JSON")?;
        Ok(logs)
    }

    /// Compute keccak256 hash of a string via cast.
    pub fn cast_keccak(&self, input: &str) -> Result<String> {
        let output = run_command(Command::new("cast").arg("keccak").arg(input))?;
        Ok(output.trim().to_string())
    }
}

/// Run a command, returning trimmed stdout on success or an error with stderr.
fn run_command(cmd: &mut Command) -> Result<String> {
    let output = cmd.output().context("spawning command")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let program = cmd.get_program().to_string_lossy().to_string();
        anyhow::bail!("{program} failed: {stderr}");
    }
    Ok(String::from_utf8(output.stdout)?.trim().to_string())
}

/// Extract the numeric value from cast output.
///
/// Cast formats large numbers with a human-readable suffix:
///   `1771675624 [1.771e9]`
/// This returns just the first whitespace-delimited token (`1771675624`).
pub fn cast_parse_uint(raw: &str) -> &str {
    raw.split_whitespace().next().unwrap_or(raw)
}
