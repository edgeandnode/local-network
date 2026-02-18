# Testing Flows

This directory contains step-by-step guides for testing specific features and workflows in the local-network environment.

## Available Flows

### [Indexing Payments Testing](./IndexingPaymentsTesting.md)
Test the Indexing Payments system including:
- Setting up dipper credentials
- Registering indexing requests
- Monitoring payment flows
- Verifying receipt aggregation

### [Eligibility Oracle Testing](./EligibilityOracleTesting.md)
Test the Rewards Eligibility Oracle (REO) end-to-end cycle:
- Verifying deny-by-default (indexer not eligible)
- Sending gateway queries to generate eligibility data
- REO node evaluation and on-chain submission
- Verifying indexer becomes eligible
- Automated script: `./scripts/test-reo-eligibility.sh`

### [Indexer Setup](./indexer-setup.md) *(coming soon)*
Complete workflow for setting up a new indexer including:
- Indexer registration
- Allocation management
- Cost model configuration
- Health monitoring

### [Subgraph Deployment](./start-indexing.md) *(coming soon)*
Deploy and test subgraphs including:
- IPFS upload verification
- Allocation creation
- Query testing
- Indexing status monitoring

### [Gateway Testing](./gateway-testing.md) *(coming soon)*
Test gateway query routing including:
- Query submission with payment
- Receipt verification
- Load balancing behavior
- Error handling

## Creating New Flow Documentation

When documenting a new flow, include:
1. Prerequisites (services that must be running, initial state)
2. Step-by-step commands with expected outputs
3. Verification steps
4. Common issues and troubleshooting
5. Cleanup procedures