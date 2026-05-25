#!/bin/bash
# Studio UI env wrapper. Sources local-network .env, exports only the values
# that diverge from studio UI defaults (or that the UI strictly requires),
# then execs the passed command. With no args, runs the prod startup.
set -eu
. /opt/config/.env

# Required by studio UI (packages/ui/src/env/inlinedEnv.mjs throws on falsy):
export STUDIO_CLIENT_SIDE_GATEWAY_API_KEY="${GATEWAY_API_KEY}"
export STUDIO_GRAPHQL_HTTP_URI="http://localhost:${STUDIO_API_PORT}/graphql"
export STUDIO_GRAPHQL_WS_URI="ws://localhost:${STUDIO_API_PORT}/graphql"
export BASE_URI="http://localhost:${STUDIO_UI_PORT}"
export NETWORK_ID=1337
export INFURA_KEY="unused-local"
export ENVIRONMENT=local
export SAFE_API_KEY="${STUDIO_SAFE_API_KEY:-local-stub}"

# UI defaults point elsewhere — override for local stack:
export STUDIO_GRAPHQL_URI_SSR="http://studio-api:4000/graphql"
export STUDIO_JWKS_URI="http://studio-api:4000/.well-known/jwks.json"
# NOTE: IPFS_API_URL intentionally not exported — packages/ui/src/env/inlinedEnv.mjs
# hardcodes 'https://ipfs.thegraph.com' (no process.env read), so any value here
# is a no-op. Local IPFS image rendering needs an upstream patch.

# Local Hardhat chain addresses (deterministic from test mnemonic).
# TODO: read from /opt/config/horizon.json via lib.sh for robustness.
export LOCAL_GNS_ADDRESS="0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E"
export LOCAL_GRAPH_TOKEN_ADDRESS="0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690"
export LOCAL_L2_GRAPH_TOKEN_GATEWAY_ADDRESS="0x84eA74d481Ee0A5332c457a4d796187F6Ba67fEB"
export GRAPH_NETWORK_LOCAL_GRAPHQL_URI="http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"

# Billing — required by UI inlinedEnv but local doesn't exercise paid flows.
# GraphQL points at a non-routable host; addrs are zero; chain ID must be one
# that @edgeandnode/common's getCaip2IdFromChainId knows about like Sepolia (11155111)
export BILLING_GRAPHQL_HTTP_URI="http://billing-not-configured.local"
export BILLING_CONTRACT_ADDRESS="0x0000000000000000000000000000000000000000"
export BILLING_CONNECTOR_CONTRACT_ADDRESS="0x0000000000000000000000000000000000000000"
export BILLING_CONNECTOR_CONTRACT_CHAIN_ID="11155111"

if [ $# -eq 0 ]; then
  set -- bash -c "cd /app/packages/ui && exec npx next start -p ${STUDIO_UI_PORT}"
fi

exec "$@"
