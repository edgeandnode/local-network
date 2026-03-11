#!/usr/bin/env python3
"""Generate a compose override file with N extra indexer stacks.

Each extra indexer gets its own postgres, graph-node, indexer-agent,
indexer-service, and tap-agent. Protocol subgraphs (network, epoch, TAP)
are read from the primary graph-node -- extra graph-nodes only handle
actual indexing work. On-chain registration (GRT stake, operator auth)
is handled by a shared init container.

Shared across all indexers: chain (hardhat), ipfs, gateway, dipper, iisa,
redpanda, contract addresses, protocol subgraphs (on primary graph-node).

Indexer accounts come from the "junk" mnemonic starting at index 2
(indices 0-1 are ACCOUNT0/ACCOUNT1). Hardhat pre-funds these with 10k ETH.

Each extra indexer gets a unique operator derived from a mnemonic of the
form "test test test test test test test test test test test {word}" where
{word} is a BIP39 word that passes the 12-word checksum. This gives each
indexer an independent operator, matching production topology.

Usage:
    python3 scripts/gen-extra-indexers.py 3    # generate 3 extra indexers
    python3 scripts/gen-extra-indexers.py 0    # remove the file
"""

import sys
from pathlib import Path

from eth_account import Account
from mnemonic import Mnemonic

Account.enable_unaudited_hdwallet_features()

# Hardhat "junk" mnemonic accounts starting at index 2.
# Deterministic and pre-funded with 10,000 ETH by Hardhat.
JUNK_ACCOUNTS = [
    ("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"),
    ("0x90F79bf6EB2c4f870365E785982E1f101E93b906", "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"),
    ("0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"),
    ("0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc", "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba"),
    ("0x976EA74026E726554dB657fA54763abd0C3a0aa9", "0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e"),
    ("0x14dC79964da2C08b23698B3D3cc7Ca32193d9955", "0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356"),
    ("0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f", "0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97"),
    ("0xa0Ee7A142d267C1f36714E4a8F75612F20a79720", "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6"),
    ("0xBcd4042DE499D14e55001CcbB24a551F3b954096", "0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897"),
    ("0x71bE63f3384f5fb98995898A86B02Fb2426c5788", "0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82"),
    ("0xFABB0ac9d68B0B445fB7357272Ff202C5651694a", "0xa267530f49f8280200edf313ee7af6b827f2a8bce2897751d06a843f644967b1"),
    ("0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec", "0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd"),
    ("0xdF3e18d64BC6A983f673Ab319CCaE4f1a57C7097", "0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa"),
    ("0xcd3B766CCDd6AE721141F452C550Ca635964ce71", "0x8166f546bab6da521a8369cab06c5d2b9e46670292d85c875ee9ec20e84ffb61"),
    ("0x2546BcD3c84621e976D8185a91A922aE77ECEc30", "0xea6c44ac03bff858b476bba40716402b03e41b8e97e276d1baec7c37d42484a0"),
    ("0xbDA5747bFD65F08deb54cb465eB87D40e51B197E", "0x689af8efa8c651a91ad287602527f3af2fe9f6501a7ac4b061667b5a93e037fd"),
    ("0xdD2FD4581271e230360230F9337D5c0430Bf44C0", "0xde9be858da4a475276426320d5e9262ecfc3ba460bfac56360bfa6c4c28b4ee0"),
    ("0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199", "0xdf57089febbacf7ba0bc227dafbffa9fc08a93fdc68e1e42411a14efcf23656e"),
]

MAX_EXTRA = len(JUNK_ACCOUNTS)  # 18
JUNK_MNEMONIC = "test test test test test test test test test test test junk"

# Operator mnemonics: "test*11 {word}" for each BIP39 word that passes
# the 12-word checksum. Skip "junk" (ACCOUNT0) and "zero" (RECEIVER).
_bip39 = Mnemonic("english")
_prefix = "test " * 11
OPERATOR_MNEMONICS: list[tuple[str, str]] = []  # (mnemonic, address)
for _word in _bip39.wordlist:
    if _word in ("junk", "zero"):
        continue
    _candidate = _prefix + _word
    if _bip39.check(_candidate):
        _addr = Account.from_mnemonic(_candidate).address
        OPERATOR_MNEMONICS.append((_candidate, _addr))

OUTPUT_FILE = Path(__file__).resolve().parent.parent / "compose" / "extra-indexers.yaml"


def postgres_service(n: int) -> str:
    return f"""\
  postgres-{n}:
    container_name: postgres-{n}
    image: postgres:17-alpine
    command: postgres -c 'max_connections=200' -c 'shared_buffers=64MB'
    volumes:
      - postgres-{n}-data:/var/lib/postgresql/data
      - ./containers/core/postgres/setup.sql:/docker-entrypoint-initdb.d/setup.sql:ro
    environment:
      POSTGRES_INITDB_ARGS: "--encoding UTF8 --locale=C"
      POSTGRES_HOST_AUTH_METHOD: trust
      POSTGRES_USER: postgres
    healthcheck:
      interval: 1s
      retries: 20
      test: pg_isready -U postgres
    mem_limit: 256m
    restart: unless-stopped
"""


def graph_node_service(n: int) -> str:
    return f"""\
  graph-node-{n}:
    container_name: graph-node-{n}
    build:
      context: containers/indexer/graph-node
      args:
        GRAPH_NODE_VERSION: ${{GRAPH_NODE_VERSION}}
    depends_on:
      chain:
        condition: service_healthy
      ipfs:
        condition: service_healthy
      postgres-{n}:
        condition: service_healthy
    stop_signal: SIGKILL
    volumes:
      - ./containers/shared:/opt/shared:ro
      - ./.env:/opt/config/.env:ro
      - config-local:/opt/config:ro
    environment:
      POSTGRES_HOST: "postgres-{n}"
    healthcheck:
      interval: 2s
      retries: 60
      start_period: 10s
      test: curl -f http://127.0.0.1:8030
    dns_opt:
      - timeout:2
      - attempts:5
    mem_limit: 256m
    restart: unless-stopped
"""


def agent_service(n: int, address: str, secret: str, operator_mnemonic: str) -> str:
    return f"""\
  indexer-agent-{n}:
    container_name: indexer-agent-{n}
    platform: linux/arm64
    build:
      target: "wrapper"
      dockerfile_inline: |
        FROM node:22-slim AS wrapper
        RUN apt-get update \\
            && apt-get install -y --no-install-recommends \\
                build-essential curl git jq python3 \\
            && rm -rf /var/lib/apt/lists/*
        COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \\
            /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/
        RUN npm install -g tsx nodemon
    entrypoint: ["bash", "/opt/run-dips.sh"]
    depends_on:
      graph-node-{n}:
        condition: service_healthy
    ports:
      - "{17600 + n * 10}:7600"
    stop_signal: SIGKILL
    volumes:
      - ${{INDEXER_AGENT_SOURCE_ROOT:?Set INDEXER_AGENT_SOURCE_ROOT}}:/opt/indexer-agent-source-root
      - ./containers/indexer/indexer-agent/dev/run-dips.sh:/opt/run-dips.sh:ro
      - ./containers/shared:/opt/shared:ro
      - ./.env:/opt/config/.env:ro
      - config-local:/opt/config:ro
    environment:
      INDEXER_ADDRESS: "{address}"
      INDEXER_SECRET: "{secret}"
      INDEXER_OPERATOR_MNEMONIC: "{operator_mnemonic}"
      INDEXER_DB_NAME: "indexer_components_1"
      INDEXER_SVC_HOST: "indexer-service-{n}"
      GRAPH_NODE_HOST: "graph-node-{n}"
      PROTOCOL_GRAPH_NODE_HOST: "graph-node"
      POSTGRES_HOST: "postgres-{n}"
      INDEXER_MANAGEMENT_PORT: "7600"
    healthcheck:
      interval: 10s
      retries: 600
      start_period: 30s
      test: curl -f http://127.0.0.1:7600/
    dns_opt:
      - timeout:2
      - attempts:5
    mem_limit: 512m
    restart: unless-stopped
"""


def service_service(n: int, address: str, secret: str, operator_mnemonic: str) -> str:
    return f"""\
  indexer-service-{n}:
    container_name: indexer-service-{n}
    cap_add:
      - NET_ADMIN
    platform: linux/arm64
    build:
      target: "wrapper"
      dockerfile_inline: |
        FROM rust:1-slim-bookworm AS wrapper
        RUN apt-get update \\
            && apt-get install -y --no-install-recommends \\
                build-essential curl git jq pkg-config \\
                protobuf-compiler libssl-dev libsasl2-dev \\
            && rm -rf /var/lib/apt/lists/*
    entrypoint: ["bash", "/opt/run-dips.sh"]
    depends_on:
      indexer-agent-{n}:
        condition: service_healthy
    ports:
      - "{17601 + n * 10}:7601"
      - "{17602 + n * 10}:7602"
    stop_signal: SIGKILL
    volumes:
      - ${{INDEXER_SERVICE_SOURCE_ROOT:?Set INDEXER_SERVICE_SOURCE_ROOT}}:/opt/source
      - ./containers/indexer/indexer-service/dev/run-dips.sh:/opt/run-dips.sh:ro
      - ./containers/shared:/opt/shared:ro
      - ./.env:/opt/config/.env:ro
      - config-local:/opt/config:ro
    environment:
      INDEXER_ADDRESS: "{address}"
      INDEXER_SECRET: "{secret}"
      INDEXER_OPERATOR_MNEMONIC: "{operator_mnemonic}"
      INDEXER_DB_NAME: "indexer_components_1"
      GRAPH_NODE_HOST: "graph-node-{n}"
      PROTOCOL_GRAPH_NODE_HOST: "graph-node"
      POSTGRES_HOST: "postgres-{n}"
      RUST_LOG: info,indexer_service_rs=info,indexer_monitor=warn,indexer_dips=debug
      RUST_BACKTRACE: "1"
      SQLX_OFFLINE: "true"
    healthcheck:
      interval: 10s
      retries: 600
      test: curl -f http://127.0.0.1:7601/
    dns_opt:
      - timeout:2
      - attempts:5
    mem_limit: 192m
    restart: unless-stopped
"""


def tap_service(n: int, address: str, secret: str, operator_mnemonic: str) -> str:
    return f"""\
  tap-agent-{n}:
    container_name: tap-agent-{n}
    build:
      context: containers/query-payments/tap-agent
      args:
        INDEXER_TAP_AGENT_VERSION: ${{INDEXER_TAP_AGENT_VERSION}}
    depends_on:
      indexer-agent-{n}:
        condition: service_healthy
    stop_signal: SIGKILL
    volumes:
      - ./containers/shared:/opt/shared:ro
      - ./.env:/opt/config/.env:ro
      - config-local:/opt/config:ro
    environment:
      INDEXER_ADDRESS: "{address}"
      INDEXER_SECRET: "{secret}"
      INDEXER_OPERATOR_MNEMONIC: "{operator_mnemonic}"
      INDEXER_DB_NAME: "indexer_components_1"
      GRAPH_NODE_HOST: "graph-node-{n}"
      PROTOCOL_GRAPH_NODE_HOST: "graph-node"
      POSTGRES_HOST: "postgres-{n}"
      RUST_LOG: info,indexer_tap_agent=trace
      RUST_BACKTRACE: "1"
    dns_opt:
      - timeout:2
      - attempts:5
    mem_limit: 128m
    restart: unless-stopped
"""


def registration_block(n: int, address: str, secret: str, operator_mnemonic: str) -> str:
    return f"""\
        # --- Extra indexer {n}: {address} ---
        ADDR="{address}"
        KEY="{secret}"
        OP_MNEMONIC="{operator_mnemonic}"

        # Derive this indexer's unique operator address from its mnemonic
        OPERATOR=$$(cast wallet address --mnemonic="$$OP_MNEMONIC")
        echo "Extra indexer {n}: $$ADDR  operator: $$OPERATOR"

        # Staking (idempotent -- skip if already staked)
        STAKE=$$(cast call --rpc-url="$$RPC" "$$STAKING" 'getStake(address)(uint256)' "$$ADDR")
        if [ "$$STAKE" != "0" ]; then
          echo "  already staked ($$STAKE)"
        else
          # Fund indexer with ETH + GRT, then stake
          retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --mnemonic="$$MNEMONIC" \\
            --value=1ether "$$ADDR"
          retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --mnemonic="$$MNEMONIC" \\
            "$$TOKEN" 'transfer(address,uint256)' "$$ADDR" '100000000000000000000000'
          retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --private-key="$$KEY" \\
            "$$TOKEN" 'approve(address,uint256)' "$$STAKING" '100000000000000000000000'
          retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --private-key="$$KEY" \\
            "$$STAKING" 'stake(uint256)' '100000000000000000000000'
          echo "  staked"
        fi

        # Operator auth (always run -- idempotent on-chain, ensures auth
        # even if a previous run staked but failed on the auth step).
        # setOperator(verifier, operator, allowed) -- verifier first!
        retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --mnemonic="$$MNEMONIC" \\
          --value=1ether "$$OPERATOR"
        retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --private-key="$$KEY" \\
          "$$STAKING" 'setOperator(address,address,bool)' "$$SSA" "$$OPERATOR" "true"
        retry_cast cast send --rpc-url="$$RPC" --confirmations=1 --private-key="$$KEY" \\
          "$$STAKING" 'setOperator(address,address,bool)' "$$STAKING" "$$OPERATOR" "true"
        echo "  operator authorized"
"""


def init_indexers_service(registrations: str) -> str:
    return f"""\
  start-indexing-extra:
    container_name: start-indexing-extra
    build:
      context: containers/indexer/start-indexing
    depends_on:
      start-indexing:
        condition: service_completed_successfully
    restart: on-failure:5
    volumes:
      - ./containers/shared:/opt/shared:ro
      - ./.env:/opt/config/.env:ro
      - config-local:/opt/config:ro
    entrypoint: ["bash", "-c"]
    command:
      - |
        set -eu
        . /opt/config/.env
        . /opt/shared/lib.sh

        retry_cast() {{ for i in 1 2 3 4 5; do "$$@" && return 0; echo "Attempt $$i failed, retrying in 3s..."; sleep 3; done; echo "Failed after 5 attempts: $$*"; return 1; }}

        RPC="http://chain:$${{CHAIN_RPC_PORT}}"
        MNEMONIC="$${{MNEMONIC}}"
        TOKEN=$$(contract_addr L2GraphToken.address horizon)
        STAKING=$$(contract_addr HorizonStaking.address horizon)
        SSA=$$(contract_addr SubgraphService.address subgraph-service)

{registrations}
        echo "All extra indexers registered"
"""


def generate(count: int) -> str:
    if count > len(OPERATOR_MNEMONICS):
        print(
            f"Only {len(OPERATOR_MNEMONICS)} valid operator mnemonics available, "
            f"requested {count}",
            file=sys.stderr,
        )
        sys.exit(1)

    parts = []
    reg_blocks = []
    volume_names = []

    for i in range(count):
        n = i + 2  # service suffix: postgres-2, graph-node-2, etc.
        address, secret = JUNK_ACCOUNTS[i]
        op_mnemonic, op_address = OPERATOR_MNEMONICS[i]
        volume_names.append(f"postgres-{n}-data")

        parts.append(postgres_service(n))
        parts.append(graph_node_service(n))
        parts.append(agent_service(n, address, secret, op_mnemonic))
        parts.append(service_service(n, address, secret, op_mnemonic))
        parts.append(tap_service(n, address, secret, op_mnemonic))
        reg_blocks.append(registration_block(n, address, secret, op_mnemonic))

    parts.append(init_indexers_service("\n".join(reg_blocks)))

    header = """\
# Auto-generated by scripts/gen-extra-indexers.py -- do not edit manually
#
# Usage:
#   python3 scripts/gen-extra-indexers.py N
#   COMPOSE_FILE=docker-compose.yaml:compose/dev/dips.yaml:compose/extra-indexers.yaml

"""

    volumes = "\nvolumes:\n"
    for v in volume_names:
        volumes += f"  {v}:\n"

    return header + "services:\n" + "\n".join(parts) + volumes


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} N", file=sys.stderr)
        print(f"  N=1..{MAX_EXTRA}: generate compose/extra-indexers.yaml with N extra indexers", file=sys.stderr)
        print(f"  N=0: remove the generated file", file=sys.stderr)
        sys.exit(1)

    count = int(sys.argv[1])

    if count == 0:
        if OUTPUT_FILE.exists():
            OUTPUT_FILE.unlink()
            print(f"Removed {OUTPUT_FILE}")
        else:
            print("Nothing to remove")
        return

    if count < 0 or count > MAX_EXTRA:
        print(f"Count must be 0..{MAX_EXTRA}, got {count}", file=sys.stderr)
        sys.exit(1)

    yaml_content = generate(count)
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(yaml_content)
    print(f"Generated {OUTPUT_FILE} with {count} extra indexer(s)")
    print(f"Service suffixes: {', '.join(str(i+2) for i in range(count))}")
    print(f"\nPer-indexer stack: postgres, graph-node, indexer-agent, indexer-service, tap-agent")
    print(f"Protocol subgraphs read from primary graph-node (no deploy-subgraphs needed)")
    print(f"Plus: start-indexing-extra (shared on-chain init)")
    print(f"\nTo activate, set in .environment:")
    print(f"  COMPOSE_FILE=docker-compose.yaml:compose/dev/dips.yaml:compose/extra-indexers.yaml")


if __name__ == "__main__":
    main()
