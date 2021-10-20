# Local Graph network

This environment provides a complete local graph network for use in building and testing components and the network
as a whole. It uses Overmind to manage the various component processes see the section on [working with Overmind](#Overmind)
for details and suggested usage patterns.

## Prerequisites

- [Rust (latest stable)](https://www.rust-lang.org/tools/install)
    - [Cargo watch](https://github.com/watchexec/cargo-watch) - required for auto restarting the rust components upon code changes.
- PostgreSQL with timescaledb extension
  - [PostgreSQL downloads](https://www.postgresql.org/download/)
  - [Installing timescaledb](https://docs.timescale.com/timescaledb/latest/how-to-guides/install-timescaledb/self-hosted/)
- [IPFS](https://docs.ipfs.io/install/)
- [Yalc](https://github.com/wclr/yalc) - required for linking packages, uses a local package repository.
- [Overmind](https://github.com/DarthSim/overmind) - used to manage subprocesses and tear down everything if one of the processes exits.

## Running a local Graph network

### Startup

Make sure to update the .overmind.env file to represent your local test environment before spinning up the local network.
You should only need to update the database configs and the source paths to each component.

  ```shell
  # All components
  overmind start

  # Explicitly start all components
  overmind start -l chain,contracts,ipfs,graph-node,network-subgraph,indexer-agent,indexer-service,setup-indexer,gateway-agent,gateway,setup-query-user,fisherman

  # Just an indexer
  overmind start -l chain,contracts,ipfs,graph-node,network-subgraph,indexer-agent,indexer-service,setup-indexer

  # Just a gateway
  overmind start -l chain,contracts,ipfs,graph-node,gateway-agent,gateway,fisherman,setup-query-user
  ```

### Working with the environment

#### Overmind

Overmind is a fully features process manager that bundles the output of all the processes together in one terminal
while also providing access to each process terminal directly. It starts each process in a tmux session, so one can
easily connect to any specific process and gain control of it. Parameters can be set globally using the overmind.env
file and then accessed in the individual process startup scripts. Below are some useful commands to illustrate
how to interact with a running Overmind environment.

```shell
# Connect to specific process - This will open up a `tmux` panel for the process.  You can use `tmux` commands to manage the window. You can view list of process panels, switch between process panels, manage the layout of multiple panels, etc..
overmind connect <PROCESS_NAME>

# Restart specific process
overmind restart <PROCESS_NAME>

# Stop specific process
overmind stop <PROCESS_NAME>

# Run command from within Overmind environment
# This is useful for:
#   - using Overmind ENV vars in scripts (see the commands folder)
#   - using deploy scripts separate from the initial startup (if the network is already running you can use this to deploy another component separate from the Overmind process group)
overmind run <COMMAND>

# Gracefully quit all processes
overmind quit

# Kill all processes
overmind kill

# Echo output from main Overmind instance
overmind echo
```

#### Interacting with contracts

Several commands have been added to this repo for convenience interacting with the contracts. Alternatively the contracts
CLI can be accessed directly, see the next section for a few examples of direct CLI usage.
```shell
# All commands are executed from a wallet generated from the main mnemonic currently at address: `0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1`
# Approve staking contract and stake GRT in the network
overmind run ./commands/stake.sh

# Pause the network
overmind run ./commands/pause.sh

# Unpause the network
overmind run ./commands/unpause.sh

# Mint signal on the accounts first subgraph (number: `0`)
overmind run ./commands/mintAndSignal.sh
```

The contracts CLI can be used directly to interact with the contracts. Here are some example commands (run from root directory of the contracts repo):
```shell
  # Update epoch length
  ts-node ./cli/cli.ts protocol set epochs-length 5

  # Pause contracts
  ts-node ./cli/cli.ts protocol set controller-set-paused 1

  # Publish subgraph
  ts-node ./cli/cli.ts contracts gns publishNewSubgraph \
    --mnemonic "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --provider-url http://127.0.0.1:8545/ \
    --ipfs http://127.0.0.1:5001/ \
    --graphAccount 0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1 \
    --subgraphDeploymentID QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy \
    --subgraphPath '/subgraphMetadata.json' \
    --versionPath '/versionMetadata.json'

  # Approve and stake
  ts-node ./cli/cli.ts contracts graphToken approve \
    --mnemonic "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --provider-url http://127.0.0.1:8545/ \
    --account 0x6eD79Aa1c71FD7BdBC515EfdA3Bd4e26394435cC \
    --amount 1000000

  ts-node ./cli/cli.ts contracts staking stake \
    --mnemonic "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --provider-url http://127.0.0.1:8545/ \
    --amount 1000000

  # Mint signal
  ts-node ./cli/cli.ts contracts graphToken approve \
    --mnemonic "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --provider-url http://127.0.0.1:8545/ \
    --account 0x630589690929E9cdEFDeF0734717a9eF3Ec7Fcfe \
    --amount 1000000

  ts-node ./cli/cli.ts contracts gns mintNSignal \
    --graphAccount 0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1 \
    --tokens 1000 \
    --subgraphNumber 0
```

### Querying

Included are some simple example queries that can be used to test different areas of the query pipeline.
```shell
  # Send query directly to the graph-node
  curl -X POST \
    -H 'Content-Type: application/json' \
    --data '{"query": "{allocations{id}}"}' \
    http://localhost:8000/subgraphs/id/QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy

      # Response
      # {"data":{"allocations":[{"id":"0xf918d3c3c6a35edcb0bb06c8eec891780111b0b4"},{"id":"0xfee23495f78c8ab7c93941cea84bb0721762f29c"}]}}


  # Send to indexer-service (no auth token)
  curl -X POST \
    -H 'Content-Type: application/json' \
    --data '{"query": "{allocations{id}}"}' \
    http://localhost:7600/subgraphs/id/QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy

      # Response
      # {"error":"No Scalar-Receipt header provided"}


  # Send to the indexer-service with free query bearer token
  curl -X POST \
    -H 'Content-Type: application/json' \
      -H 'Authorization: Bearer superdupersecrettoken' \
    --data '{"query": "{allocations{id}}"}' \
    http://localhost:7600/subgraphs/id/QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy

      # Response
      # {"graphQLResponse":"{\"data\":{\"allocations\":[{\"id\":\"0xf918d3c3c6a35edcb0bb06c8eec891780111b0b4\"},{\"id\":\"0xfee23495f78c8ab7c93941cea84bb0721762f29c\"}]}}"}

  # Send to gateway (use ipfs hash instead of subgraph id)
  curl -X POST \
    -H 'Content-Type: application/json' \
    --data '{"query": "{allocations{id}}"}' \
    http://localhost:6700/api/f69b1e20cd09b73fa871920cd1150f08/subgraphs/id/QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy

      # Response (before adding grt to studio balance)
      # {"errors":[{"message":"Subgraph has no deployment"}]}

  # Send to gateway (using correctly formatted subgraph id - '0x<account_address>-<subgraph_number_for_account>')
  curl -X POST \
    -H 'Content-Type: application/json' \
    --data '{"query": "{allocations(block:{number:8000000}){id}}"}' \
    http://localhost:6700/api/f69b1e20cd09b73fa871920cd1150f08/subgraphs/id/0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1-0

	# Response
	# {"errors":[{"message":"Failed to query subgraph deployment 'QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy': Exhausted list of indexers"}]}
```

#### Monitoring

##### Network state

Monitoring network state via the subgraph
- Navigate to http://localhost:8000 in the browser to open query playground.
- Query the state of the network.
  ```graphql
  {
    graphAccount(id: "0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1") {
      id
      defaultName {
        id
        name
      }
      defaultDisplayName
      description
      balance
      stakingApproval
      curator {
        id
      }
      indexer {
        id
        url
        geoHash
        defaultDisplayName
        stakedTokens
        allocatedTokens
        totalAllocations {
          allocatedTokens
          effectiveAllocation
          createdAtBlockNumber
          queryFeeRebates
          queryFeesCollected
          curatorRewards
          indexingRewards
          status
          createdAtEpoch
          subgraphDeployment {
            id
            ipfsHash
          }
        }
        totalAllocationCount
        tokenCapacity
        tokensLockedUntil
        unstakedTokens
        delegatedTokens
      }
      delegator {
        id
      }
    }
    graphNetworks {
      graphToken
      epochManager
      curation
      staking
      disputeManager
      gns
      serviceRegistry
      rewardsManager
      governor
      pauseGuardian
      channelDisputeEpochs
      maxAllocationEpochs
      isPaused
      isPartialPaused
      currentEpoch
      lastRunEpoch
      epochLength
    }
    subgraphs {
      id
      currentVersion {
        id
        subgraphDeployment {
          id
          manifest
          schema
          ipfsHash
          network {
            id
          }
          schemaIpfsHash
          signalAmount
          stakedTokens
          indexingRewardAmount
          queryFeesAmount
          pricePerShare
          curatorFeeRewards
          signalledTokens
          network {
            id
          }
        }
      }
      displayName
      signalledTokens
    }
  }
  ```

##### Processes

Each Overmind managed process can be monitored by connecting to the process via tmux or by accessing the log file.

Monitoring the Indexer agent for example
```shell
# Connect to process instance in a tmux panel
overmind connect indexer-agent

# View latest 1000 logs from the log file
tail -n 1000 -f /tmp/indexer-agent.log | less
```
x
