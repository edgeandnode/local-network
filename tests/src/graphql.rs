//! GraphQL query helpers for the network subgraph and indexer management API.

use anyhow::{Context, Result};
use serde_json::Value;

use crate::TestNetwork;

impl TestNetwork {
    /// Execute a GraphQL query against the network subgraph (graph-node).
    pub async fn subgraph_query(&self, query: &str) -> Result<Value> {
        self.graphql_post(&self.subgraph_url, query, None).await
    }

    /// Execute a GraphQL query/mutation against the indexer management API.
    pub async fn management_query(&self, query: &str) -> Result<Value> {
        self.graphql_post(&self.management_url, query, None).await
    }

    /// Send a query through the gateway for a specific subgraph.
    pub async fn gateway_query(&self, query: &str) -> Result<reqwest::Response> {
        let url = format!("{}/api/subgraphs/id/{}", self.gateway_url, self.subgraph_id);
        let client = reqwest::Client::new();
        let body = serde_json::json!({ "query": query });
        let resp = client
            .post(&url)
            .header("content-type", "application/json")
            .header("Authorization", format!("Bearer {}", self.gateway_api_key))
            .json(&body)
            .send()
            .await
            .context("sending gateway query")?;
        Ok(resp)
    }

    /// Send N queries through the gateway. Returns (success_count, fail_count).
    pub async fn send_gateway_queries(&self, count: usize) -> Result<(usize, usize)> {
        let query = r#"{ _meta { block { number } } }"#;
        let mut success = 0;
        let mut fail = 0;
        for _ in 0..count {
            match self.gateway_query(query).await {
                Ok(resp) if resp.status().is_success() => success += 1,
                _ => fail += 1,
            }
        }
        Ok((success, fail))
    }

    /// Query the indexer entity from the network subgraph.
    /// Address must be lowercase (subgraph convention).
    /// Includes fields needed for BaselineTestPlan 6.1 (indexer health).
    pub async fn query_indexer(&self, address: &str) -> Result<Value> {
        let addr = address.to_lowercase();
        let query = format!(
            r#"{{ indexer(id: "{addr}") {{
                id stakedTokens allocatedTokens availableStake url geoHash
                delegatedTokens queryFeesCollected rewardsEarned
                allocations(where: {{ status: Active }}) {{
                    id subgraphDeployment {{ ipfsHash }}
                }}
            }} }}"#
        );
        let resp = self.subgraph_query(&query).await?;
        Ok(resp["data"]["indexer"].clone())
    }

    /// Query provisions for an indexer from the network subgraph.
    pub async fn query_provisions(&self, indexer: &str) -> Result<Value> {
        let addr = indexer.to_lowercase();
        let query = format!(
            r#"{{ provisions(where: {{ indexer: "{addr}" }}) {{
                id tokensProvisioned tokensAllocated tokensThawing thawingPeriod
                dataService {{ id }}
            }} }}"#
        );
        let resp = self.subgraph_query(&query).await?;
        Ok(resp["data"]["provisions"].clone())
    }

    /// Query active allocations for an indexer from the network subgraph.
    pub async fn query_active_allocations(&self, indexer: &str) -> Result<Value> {
        let addr = indexer.to_lowercase();
        let query = format!(
            r#"{{ allocations(where: {{ indexer: "{addr}", status: Active }}) {{
                id allocatedTokens createdAtEpoch
                subgraphDeployment {{ ipfsHash }}
            }} }}"#
        );
        let resp = self.subgraph_query(&query).await?;
        Ok(resp["data"]["allocations"].clone())
    }

    /// Query a single allocation by ID from the network subgraph.
    pub async fn query_allocation(&self, id: &str) -> Result<Value> {
        let alloc_id = id.to_lowercase();
        let query = format!(
            r#"{{ allocation(id: "{alloc_id}") {{
                id status allocatedTokens indexingRewards
                createdAtEpoch closedAtEpoch
                subgraphDeployment {{ ipfsHash }}
            }} }}"#
        );
        let resp = self.subgraph_query(&query).await?;
        Ok(resp["data"]["allocation"].clone())
    }

    /// Query network-level metrics from the network subgraph.
    /// Includes fields needed for BaselineTestPlan 6.2 (network health).
    pub async fn query_network(&self) -> Result<Value> {
        let query = r#"{ graphNetworks(first: 1) {
            currentEpoch totalTokensStaked totalTokensAllocated
            totalQueryFees totalIndexingRewards
        } }"#;
        let resp = self.subgraph_query(query).await?;
        Ok(resp["data"]["graphNetworks"][0].clone())
    }

    /// Get the latest block number indexed by graph-node (from the network subgraph).
    /// This is safer than `get_block_number()` for use with the indexer-agent,
    /// which needs graph-node to have the block hash cached.
    pub async fn subgraph_block_number(&self) -> Result<u64> {
        let query = r#"{ _meta { block { number } } }"#;
        let resp = self.subgraph_query(query).await?;
        resp["data"]["_meta"]["block"]["number"]
            .as_u64()
            .context("subgraph _meta block number not found")
    }

    /// Query the block-oracle subgraph for epoch block number data.
    /// Returns true if the block-oracle has processed the given epoch.
    pub async fn block_oracle_has_epoch(&self, epoch: u64) -> Result<bool> {
        let epoch_id = format!("{epoch}-eip155:1337");
        let query = format!(r#"{{ networkEpochBlockNumber(id: "{epoch_id}") {{ epochNumber }} }}"#);
        let resp = self
            .graphql_post(&self.block_oracle_subgraph_url, &query, None)
            .await?;
        Ok(!resp["data"]["networkEpochBlockNumber"].is_null())
    }

    /// Query the TAP subgraph for escrow accounts.
    pub async fn query_tap_escrow_accounts(&self) -> Result<Value> {
        let query = r#"{ escrowAccounts(first: 10) {
            balance
            sender { id }
            receiver { id }
        } }"#;
        // TAP subgraph may be empty — treat GraphQL errors as empty result
        let resp = self.graphql_post(&self.tap_subgraph_url, query, None).await;
        match resp {
            Ok(v) => Ok(v["data"]["escrowAccounts"].clone()),
            Err(_) => Ok(Value::Array(vec![])),
        }
    }

    /// Low-level GraphQL POST. Returns the parsed JSON response.
    async fn graphql_post(
        &self,
        url: &str,
        query: &str,
        variables: Option<&Value>,
    ) -> Result<Value> {
        let client = reqwest::Client::new();
        let mut body = serde_json::json!({ "query": query });
        if let Some(vars) = variables {
            body["variables"] = vars.clone();
        }
        let resp = client
            .post(url)
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .with_context(|| format!("POST {url}"))?;
        let status = resp.status();
        let text = resp.text().await.context("reading response body")?;
        if !status.is_success() {
            anyhow::bail!("GraphQL request to {url} failed ({status}): {text}");
        }
        let json: Value = serde_json::from_str(&text)
            .with_context(|| format!("parsing JSON from {url}: {text}"))?;
        if let Some(errors) = json.get("errors")
            && errors.is_array()
            && !errors.as_array().unwrap().is_empty()
        {
            anyhow::bail!("GraphQL errors from {url}: {errors}");
        }
        Ok(json)
    }
}
