#!/usr/bin/env python3
"""Publish test subgraphs to GNS on the local network.

Builds a minimal block-tracker subgraph once, then creates N unique manifests
(varying startBlock), uploads each to IPFS, and publishes to GNS on-chain.

Does NOT deploy to graph-node (no indexing), curate, or allocate.

Usage:
    python3 scripts/deploy-test-subgraph.py           # publish 1
    python3 scripts/deploy-test-subgraph.py 50         # publish 50
    python3 scripts/deploy-test-subgraph.py 10 myname  # publish myname-1..myname-10
"""

import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.request import Request, urlopen

IPFS_API = "http://localhost:5001"
CHAIN_RPC = "http://localhost:8545"
MNEMONIC = "test test test test test test test test test test test junk"

SCHEMA = """\
type Block @entity(immutable: true) {
  id: ID!
  number: BigInt!
  timestamp: BigInt!
  gasUsed: BigInt!
}
"""

MAPPING = """\
import { ethereum } from "@graphprotocol/graph-ts"
import { Block } from "../generated/schema"

export function handleBlock(block: ethereum.Block): void {
  let entity = new Block(block.hash.toHexString())
  entity.number = block.number
  entity.timestamp = block.timestamp
  entity.gasUsed = block.gasUsed
  entity.save()
}
"""

PACKAGE_JSON = """\
{
  "name": "test-subgraph",
  "version": "0.1.0",
  "dependencies": {
    "@graphprotocol/graph-cli": "0.97.0",
    "@graphprotocol/graph-ts": "0.35.1"
  }
}
"""


def ipfs_add(content: str | bytes) -> str:
    """Upload content to IPFS, return the CID."""
    from urllib.request import urlopen as _urlopen

    if isinstance(content, str):
        content = content.encode()

    boundary = b"----PythonBoundary"
    body = (
        b"--" + boundary + b"\r\n"
        b'Content-Disposition: form-data; name="file"; filename="file"\r\n'
        b"Content-Type: application/octet-stream\r\n\r\n"
        + content + b"\r\n"
        b"--" + boundary + b"--\r\n"
    )
    req = Request(
        f"{IPFS_API}/api/v0/add?pin=true",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary.decode()}"},
        method="POST",
    )
    with _urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())["Hash"]


def run(cmd: str, cwd: str = None) -> str:
    result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAILED: {cmd}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def get_contract_address(contract_path: str, config_file: str) -> str:
    repo_root = Path(__file__).resolve().parent.parent
    output = run(
        f'DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml '
        f'exec -T indexer-agent jq -r \'.["1337"].{contract_path}\' /opt/config/{config_file}',
        cwd=str(repo_root),
    )
    if not output or output == "null":
        print(f"Could not read {contract_path} from {config_file}", file=sys.stderr)
        sys.exit(1)
    return output


def cid_to_hex(cid: str) -> str:
    """Convert an IPFS CIDv0 (Qm...) to the 32-byte hex used by GNS."""
    output = json.loads(run(f'curl -s -X POST "{IPFS_API}/api/v0/cid/format?arg={cid}&b=base16"'))
    return output["Formatted"][len("f01701220"):]


def build_once(source_address: str) -> tuple[str, str, str]:
    """Build the subgraph once, upload shared artifacts to IPFS.

    Returns (schema_cid, abi_cid, wasm_cid).
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "schema.graphql").write_text(SCHEMA)
        Path(tmpdir, "package.json").write_text(PACKAGE_JSON)
        Path(tmpdir, "abis").mkdir()
        Path(tmpdir, "abis", "Dummy.json").write_text("[]")
        Path(tmpdir, "src").mkdir()
        Path(tmpdir, "src", "mapping.ts").write_text(MAPPING)

        # Manifest just for building -- startBlock doesn't matter here
        Path(tmpdir, "subgraph.yaml").write_text(
            make_manifest("build", source_address, start_block=0)
        )

        print("Building subgraph (one-time)...")
        print("  npm install...")
        run("npm install --silent 2>&1", cwd=tmpdir)
        print("  codegen + build...")
        run("npx graph codegen 2>&1", cwd=tmpdir)
        run("npx graph build 2>&1", cwd=tmpdir)

        # Upload the three shared artifacts to IPFS
        schema_cid = ipfs_add(SCHEMA)
        abi_cid = ipfs_add("[]")
        wasm_path = Path(tmpdir, "build", next(
            p.name for p in Path(tmpdir, "build").iterdir() if p.is_dir()
        ))
        wasm_file = next(wasm_path.glob("*.wasm"))
        wasm_cid = ipfs_add(wasm_file.read_bytes())

        print(f"  schema={schema_cid} abi={abi_cid} wasm={wasm_cid}")
        return schema_cid, abi_cid, wasm_cid


def make_manifest(name: str, source_address: str, start_block: int) -> str:
    return f"""\
specVersion: 0.0.4
schema:
  file: ./schema.graphql
dataSources:
  - kind: ethereum
    name: {name}
    network: hardhat
    source:
      abi: Dummy
      address: "{source_address}"
      startBlock: {start_block}
    mapping:
      apiVersion: 0.0.6
      language: wasm/assemblyscript
      kind: ethereum/events
      entities:
        - Block
      abis:
        - name: Dummy
          file: ./abis/Dummy.json
      blockHandlers:
        - handler: handleBlock
      file: ./src/mapping.ts
"""


def make_ipfs_manifest(
    name: str, source_address: str, start_block: int,
    schema_cid: str, abi_cid: str, wasm_cid: str,
) -> str:
    """Produce the resolved manifest that graph-node expects from IPFS.

    File references become IPFS links: {/: /ipfs/CID}
    """
    return json.dumps({
        "specVersion": "0.0.4",
        "schema": {"file": {"/": f"/ipfs/{schema_cid}"}},
        "dataSources": [{
            "kind": "ethereum",
            "name": name,
            "network": "hardhat",
            "source": {
                "abi": "Dummy",
                "address": source_address,
                "startBlock": start_block,
            },
            "mapping": {
                "apiVersion": "0.0.6",
                "language": "wasm/assemblyscript",
                "kind": "ethereum/events",
                "entities": ["Block"],
                "abis": [{"name": "Dummy", "file": {"/": f"/ipfs/{abi_cid}"}}],
                "blockHandlers": [{"handler": "handleBlock"}],
                "file": {"/": f"/ipfs/{wasm_cid}"},
            },
        }],
    })


def get_nonce() -> int:
    output = run(f'cast nonce 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url "{CHAIN_RPC}"')
    return int(output)


def publish_to_gns(deployment_hex: str, gns_address: str, nonce: int) -> str:
    """Publish to GNS with explicit nonce. Uses --async to avoid timeout."""
    tx_hash = run(
        f'cast send "{gns_address}" '
        f'"publishNewSubgraph(bytes32,bytes32,bytes32)" '
        f'"0x{deployment_hex}" '
        f'"0x0000000000000000000000000000000000000000000000000000000000000000" '
        f'"0x0000000000000000000000000000000000000000000000000000000000000000" '
        f'--rpc-url "{CHAIN_RPC}" --async '
        f'--nonce {nonce} '
        f'--mnemonic "{MNEMONIC}"'
    )
    return tx_hash


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    prefix = sys.argv[2] if len(sys.argv) > 2 else "test-subgraph"

    source_address = get_contract_address("L2GraphToken.address", "horizon.json")
    gns_address = get_contract_address("L2GNS.address", "subgraph-service.json")

    schema_cid, abi_cid, wasm_cid = build_once(source_address)

    print(f"\nPublishing {count} subgraph(s) to GNS: {prefix}-1..{prefix}-{count}\n")

    # Upload unique manifests to IPFS and collect deployment hashes
    to_publish = []
    for i in range(count):
        idx = i + 1
        name = f"{prefix}-{idx}"
        start_block = idx

        manifest_content = make_ipfs_manifest(
            name, source_address, start_block, schema_cid, abi_cid, wasm_cid
        )
        manifest_cid = ipfs_add(manifest_content)
        dep_hex = cid_to_hex(manifest_cid)
        to_publish.append((name, manifest_cid, dep_hex))
        print(f"  {name}  {manifest_cid}")

    # Batch-publish all to GNS with sequential nonces and --async
    if to_publish:
        print(f"\nPublishing {len(to_publish)} subgraph(s) to GNS...")
        nonce = get_nonce()
        for name, manifest_cid, dep_hex in to_publish:
            publish_to_gns(dep_hex, gns_address, nonce)
            nonce += 1
        # Wait for the last tx to confirm
        time.sleep(2)
        print("  done")

    print(f"\n{len(to_publish)}/{count} subgraph(s) published to GNS.")
    print("Not deployed to graph-node, curated, or allocated.")


if __name__ == "__main__":
    main()
