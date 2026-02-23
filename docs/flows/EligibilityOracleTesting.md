# Eligibility Oracle Testing Flow

Test the Rewards Eligibility Oracle (REO) end-to-end: indexer starts ineligible, serves queries through the gateway, and is marked eligible by the REO node.

## Prerequisites

1. Local network running with the rewards-eligibility profile enabled (`COMPOSE_PROFILES=rewards-eligibility` in `.env`, enabled by default):
   ```bash
   docker compose up -d --build
   ```

2. All core services healthy (gateway, graph-node, redpanda, chain, graph-contracts):
   ```bash
   docker compose ps
   ```

3. REO contract deployed (Phase 4 in graph-contracts logs):
   ```bash
   docker compose logs graph-contracts | grep "Phase 4"
   ```

4. REO node running and connected:
   ```bash
   docker compose logs --tail 20 eligibility-oracle-node
   ```

5. `cast` available on the host (installed with Foundry).

6. Source environment variables:
   ```bash
   source .env
   ```

## Automated Test

Run the full cycle with a single script:

```bash
./scripts/test-reo-eligibility.sh        # default: 10 queries
./scripts/test-reo-eligibility.sh 50      # send 50 queries
```

The script:
1. Checks eligibility validation is enabled (done by deployment, errors if not)
2. Seeds `lastOracleUpdateTime` to disable the fail-safe (if needed)
3. Verifies the indexer is NOT eligible
4. Sends queries through the gateway
5. Polls `isEligible()` every 10s until true or timeout (150s)

## Manual Step-by-Step

### 1. Read REO contract address

```bash
source .env
REO=$(docker exec graph-node cat /opt/config/issuance.json | jq -r '.["1337"].RewardsEligibilityOracle.address')
RPC="http://localhost:${CHAIN_RPC_PORT}"
echo "REO: $REO"
```

### 2. Check contract state

```bash
# Is eligibility validation enabled?
cast call --rpc-url="$RPC" "$REO" "getEligibilityValidation()(bool)"

# When was the last oracle update?
cast call --rpc-url="$RPC" "$REO" "getLastOracleUpdateTime()(uint256)"

# Is the indexer eligible?
cast call --rpc-url="$RPC" "$REO" "isEligible(address)(bool)" "$RECEIVER_ADDRESS"
```

### 3. Verify eligibility validation is enabled

Deployment (Phase 4) enables validation automatically. Confirm:

```bash
cast call --rpc-url="$RPC" "$REO" "getEligibilityValidation()(bool)"
# Expected: true
```

If not enabled, re-run graph-contracts or enable manually:
```bash
# Requires OPERATOR_ROLE (ACCOUNT0)
cast send --rpc-url="$RPC" --confirmations=0 \
  --private-key="$ACCOUNT0_SECRET" \
  "$REO" "setEligibilityValidation(bool)" true
```

### 4. Seed the oracle timestamp

If `lastOracleUpdateTime` is 0 (never updated), the fail-safe makes everyone eligible regardless. Seed it with an empty update:

```bash
# Requires ORACLE_ROLE (ACCOUNT0)
cast send --rpc-url="$RPC" --confirmations=0 \
  --private-key="$ACCOUNT0_SECRET" \
  "$REO" "renewIndexerEligibility(address[],bytes)" "[]" "0x"
```

### 5. Verify indexer is NOT eligible

```bash
cast call --rpc-url="$RPC" "$REO" "isEligible(address)(bool)" "$RECEIVER_ADDRESS"
# Expected: false
```

### 6. Send queries through the gateway

```bash
# Mine blocks first to keep the gateway happy
./scripts/mine-block.sh 5

# Send 10 queries
./scripts/query_gateway.sh 10
```

### 7. Wait for the REO node cycle

The REO node cycles every 60 seconds in local network configuration. Watch the logs:

```bash
docker compose logs -f eligibility-oracle-node
```

Look for:
- `Consumed N messages from gateway_queries`
- `Eligible indexers: [0xf4ef...]`
- `renewIndexerEligibility` transaction submitted

### 8. Verify indexer IS eligible

```bash
cast call --rpc-url="$RPC" "$REO" "isEligible(address)(bool)" "$RECEIVER_ADDRESS"
# Expected: true
```

## Understanding the Contract Behaviour

The REO contract has three layers of eligibility logic:

| Condition | `isEligible()` returns | Notes |
|---|---|---|
| Validation disabled | `true` (all) | Default after deployment |
| Validation enabled, oracle never updated (fail-safe) | `true` (all) | `lastOracleUpdateTime=0`, timeout expired |
| Validation enabled, oracle active, indexer not renewed | `false` | Deny-by-default |
| Validation enabled, oracle active, indexer renewed | `true` | Within `eligibilityPeriod` (14 days) |
| Validation enabled, oracle stale (`> oracleUpdateTimeout`) | `true` (all) | Fail-safe for oracle downtime |

The automated test script handles states 1 and 2 by enabling validation and seeding the oracle timestamp.

## Troubleshooting

### Indexer already eligible before test
The REO node may have already submitted eligibility in a previous cycle. Wait for the `eligibilityPeriod` (14 days on-chain, but you can check the configured value) to expire, or redeploy the contracts with `docker compose down -v && up`.

### REO node not submitting on-chain
Check that:
- The `gateway_queries` Redpanda topic has messages: `docker compose exec redpanda rpk topic consume gateway_queries --num 1`
- The node has ORACLE_ROLE: `cast call --rpc-url="$RPC" "$REO" "hasRole(bytes32,address)(bool)" "$(cast call --rpc-url=$RPC $REO 'ORACLE_ROLE()(bytes32)')" "$ACCOUNT0_ADDRESS"`
- The node can reach the chain: check logs for RPC errors

### All queries failing (HTTP != 200)
- Mine blocks: `./scripts/mine-block.sh 10`
- Check gateway health: `docker compose ps gateway`
- Ensure at least one subgraph is allocated and synced

### Cast command fails
- Ensure Foundry is installed: `cast --version`
- Check chain is running: `cast block-number --rpc-url="$RPC"`
