#!/bin/bash
# Studio UI env wrapper. Sources local-network .env, exports only the values
# that diverge from studio UI defaults (or that the UI strictly requires),
# then execs the passed command. With no args, runs the prod startup.
set -eu
. /opt/config/.env

# Required by studio UI (packages/ui/src/env/inlinedEnv.mjs throws on falsy):
export STUDIO_CLIENT_SIDE_GATEWAY_API_KEY="${GATEWAY_API_KEY}"
# Server-side Playground gateway proxy (pages/api/gateway/query/[id].ts) authenticates
# to the gateway with this. Sourced from .env but must be exported to reach next; not
# in inlinedEnv, so it stays server-only and is never shipped to the browser.
export GATEWAY_API_KEY="${GATEWAY_API_KEY}"
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

# Local Hardhat chain addresses. Read live from the mounted config volume —
# deterministic-from-mnemonic addresses shift whenever deploy order changes
# (e.g. audit branch adding contracts), so hardcoding them silently breaks the
# UI publish flow with `nextAccountSeqID` reverting on a wrong/empty address.
# jq isn't in the node image, so read via node.
read_addr() {
  # $1 = contract name, $2 = config file basename (no .json)
  node -e "
    const j = require('/opt/config/$2.json');
    const v = j && j['1337'] && j['1337']['$1'] && j['1337']['$1'].address;
    if (!v) { console.error('address $1 not found in /opt/config/$2.json'); process.exit(1); }
    process.stdout.write(v);
  "
}
# Assign separately from export so set -e aborts if an address can't be read.
LOCAL_GNS_ADDRESS="$(read_addr L2GNS subgraph-service)"
LOCAL_GRAPH_TOKEN_ADDRESS="$(read_addr L2GraphToken horizon)"
LOCAL_L2_GRAPH_TOKEN_GATEWAY_ADDRESS="$(read_addr L2GraphTokenGateway horizon)"
# Host-facing display URL (Endpoints tab). Inlined into the client bundle, so it
# must resolve from the browser on the host, where ${GATEWAY_PORT} is port-mapped.
export LOCAL_GATEWAY_QUERY_URL="http://localhost:${GATEWAY_PORT}/api"
# In-network URL for the server-side Playground proxy (pages/api/gateway/query/[id].ts),
# which runs inside this container and can't reach the host-mapped localhost:${GATEWAY_PORT};
# it must hit the gateway service directly. The Endpoints display path uses
# LOCAL_GATEWAY_QUERY_URL above, so it remains host-facing.
export LOCAL_GATEWAY_PROXY_URL="http://gateway:7700/api"
export LOCAL_GNS_ADDRESS LOCAL_GRAPH_TOKEN_ADDRESS LOCAL_L2_GRAPH_TOKEN_GATEWAY_ADDRESS
export GRAPH_NETWORK_LOCAL_GRAPHQL_URI="http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
export INDEXING_PAYMENTS_SUBGRAPH_ENABLED=true
# DIPS default chain for multi-network published subgraphs. Studio commit e454e269
# dropped INDEXING_PAYMENTS_SUBGRAPH_URL (per-network URL now hardcoded in the client).
# Read only by inlinedEnv.mjs here; default already matches local. Pinned for parity with api.sh.
export DIPS_PUBLISHED_DEFAULT_CHAIN_CAIP2ID="eip155:1337"

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
