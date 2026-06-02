# Studio DIPs Test Setup

**1. Create project root folder**

```bash
mkdir dips && cd dips
```

**2. Clone studio**

```bash
git clone git@github.com:edgeandnode/subgraph-studio.git
```

**3. Clone iisa**

```bash
git clone git@github.com:edgeandnode/subgraph-dips-indexer-selection.git
```

**4. Clone dipper**

```bash
git clone git@github.com:edgeandnode/dipper.git
```

**5. Clone local-network**

```bash
git clone git@github.com:edgeandnode/local-network.git
```

**6. Setup GHCR authentication**

Requires a GitHub classic PAT with `read:packages` scope.

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

See: https://github.com/edgeandnode/local-network#ghcr-authentication-indexing-payments

**7. (Mac only) Build arm64 image for iisa-cronjob**

```bash
MAXMIND_LICENSE_KEY=skip docker build --platform linux/arm64 \
      --secret id=maxmind,env=MAXMIND_LICENSE_KEY \
      -t ghcr.io/edgeandnode/subgraph-dips-indexer-selection-cronjob:latest \
      ./subgraph-dips-indexer-selection/cronjobs/compute_scores
```

**8. Build Studio with local ui env**

```bash
cd subgraph-studio
cat > packages/ui/.env.local <<'EOF'
ENVIRONMENT=local

STUDIO_CLIENT_SIDE_GATEWAY_API_KEY=deadbeefdeadbeefdeadbeefdeadbeef
STUDIO_GRAPHQL_HTTP_URI=http://localhost:4000/graphql
STUDIO_GRAPHQL_URI_SSR=http://localhost:4000/graphql
STUDIO_GRAPHQL_WS_URI=wss://localhost:4000/graphql

BASE_URI=http://localhost:5000

BILLING_GRAPHQL_HTTP_URI=https://gateway.thegraph.com/api/subgraphs/id/ByuvFGbqvLd7YMsFyb4eNFZ9HrwtqJ3fex4WW3FTgkEk
BILLING_CONTRACT_ADDRESS=0xDb29A6dD3028e8cb8c7Db27E36701D533BE99EB6
BILLING_CONNECTOR_CONTRACT_ADDRESS=0x0000000000000000000000000000000000000000
BILLING_CONNECTOR_CONTRACT_CHAIN_ID=11155111

NETWORK_ID=1337
INFURA_KEY=placeholder
SAFE_API_KEY=placeholder
EOF
bun install
bun run build
```

**9. Checkout local-network studio dips dev branch**

```bash
cd ../local-network
git checkout nas/studio-dips-development
```

**10. Start docker containers**

```bash
DOCKER_DEFAULT_PLATFORM= docker compose up -d
```

**11. Check that studio ui loads**

Visit http://localhost:5000/studio . Do not connect wallet / login.

**12. In local-network folder, run script to seed Studio user**

```bash
scripts/seed-studio-user.sh {your-wallet-address}
```

**13. Run script to fund your wallet with ETH for gas on hardhat**

```bash
scripts/fund-wallet.sh {your-wallet-address} 10
```

**14. Create indexing-payment subgraph in your studio account**

```bash
python3 scripts/deploy-studio-subgraph.py {your-wallet-address} indexing-payments
```

**15. Generate 3 deployed test subgraphs in your studio account**

```bash
python3 scripts/deploy-studio-test-subgraphs.py {your-wallet-address} 3
```

**16. Connect wallet and verify dashboard**

Make sure your metamask wallet is connected to local hardhat (id: 1337) and connect to Studio UI at http://localhost:5000/studio

Check that the indexing-payment subgraph and 3 test subgraphs are showing in the dashboard.

**17. Publish a test subgraph**

Click into any one of the test subgraphs and then go through the Publish flow using metamask to submit a transaction to the hardhat network. Once the publish pane shows success status, check that the subgraph detail page is also updated to reflect deployed -> published status and take note of the deployment-ID in the Endpoints tab.

**18. Send an indexing request**

Start claude in the local-network folder and tell it to use the `send-indexing-request` skill to submit an indexing request for the published subgraph deployment-ID from the above step.

**19. Verify the indexing agreement**

Once the indexing request is accepted, click into the `indexing-payments` subgraph in your studio dashboard and check in the playground that an indexing agreement was created for the above deploymentID.
