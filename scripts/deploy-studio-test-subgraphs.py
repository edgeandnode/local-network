#!/usr/bin/env python3
"""Seed Studio with N deployed-but-unpublished test subgraphs for a given wallet.

For a studio wallet address this:
  1. ensures a verified studio User exists (delegates to seed-studio-user.sh),
  2. builds a minimal block-tracker subgraph ONCE (npm install + codegen + build),
  3. for each of N subgraphs: uploads a unique manifest to IPFS (varying
     startBlock), inserts the Subgraphs row, and calls subgraph_deploy on the
     studio deployment-router with the user's deploy key. subgraph_deploy
     creates the SubgraphVersion, deploys the deployment to graph-node under the
     u<uid>/s<sid>/v<vid> + .../latest aliases, and wires the playground /
     query-proxy routing.

It deliberately does NOT publish to GNS. After running, the subgraphs show up in
Studio as deployed (not-yet-published) subgraphs. The user must publish each one
from the Studio UI with their own wallet (the on-chain GNS publish step).

Re-running is idempotent: an existing Subgraphs row or version label is left
untouched. Each subgraph's deployment CID is deterministic (varies only by
startBlock), so re-running deploys the same hashes.

Targets localhost (all-local Mac stack, or the VM over SSH). Build needs Node
>= 20.18.1 and the manifest IPFS upload needs the stack's IPFS on :5001.
Override endpoints via env: IPFS_API, GRAPH_NODE_QUERY, DEPLOYMENT_ROUTER_URL.

Usage:
    python3 scripts/deploy-studio-test-subgraphs.py 0xAC7f...3240            # 1
    python3 scripts/deploy-studio-test-subgraphs.py 0xAC7f...3240 50         # 50
    python3 scripts/deploy-studio-test-subgraphs.py 0xAC7f...3240 10 myname  # myname-1..10
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

IPFS_API = os.environ.get("IPFS_API", "http://localhost:5001")
GRAPH_NODE_QUERY = os.environ.get("GRAPH_NODE_QUERY", "http://localhost:8000")
DEPLOYMENT_ROUTER_URL = os.environ.get(
    "DEPLOYMENT_ROUTER_URL", "http://localhost:4001/deploy"
)

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
  "name": "studio-test-subgraph",
  "version": "0.1.0",
  "dependencies": {
    "@graphprotocol/graph-cli": "0.97.0",
    "@graphprotocol/graph-ts": "0.35.1"
  }
}
"""


# --- IPFS / build helpers (shared with deploy-test-subgraph.py) -------------


def ipfs_add(content) -> str:
    """Upload content to IPFS, return the CID."""
    if isinstance(content, str):
        content = content.encode()

    boundary = b"----PythonBoundary"
    body = (
        b"--" + boundary + b"\r\n"
        b'Content-Disposition: form-data; name="file"; filename="file"\r\n'
        b"Content-Type: application/octet-stream\r\n\r\n" + content + b"\r\n"
        b"--" + boundary + b"--\r\n"
    )
    req = Request(
        f"{IPFS_API}/api/v0/add?pin=true",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary.decode()}"},
        method="POST",
    )
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())["Hash"]


def run(cmd: str, cwd: str = None) -> str:
    result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"FAILED: {cmd}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def get_contract_address(contract_path: str, config_file: str) -> str:
    output = run(
        f"docker compose exec -T indexer-agent "
        f"jq -r '.[\"1337\"].{contract_path}' /opt/config/{config_file}",
        cwd=REPO_ROOT,
    )
    if not output or output == "null":
        print(f"Could not read {contract_path} from {config_file}", file=sys.stderr)
        sys.exit(1)
    return output


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
    name: str,
    source_address: str,
    start_block: int,
    schema_cid: str,
    abi_cid: str,
    wasm_cid: str,
) -> str:
    """Resolved manifest graph-node expects from IPFS (file refs -> /ipfs/CID)."""
    return json.dumps(
        {
            "specVersion": "0.0.4",
            "schema": {"file": {"/": f"/ipfs/{schema_cid}"}},
            "dataSources": [
                {
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
                }
            ],
        }
    )


def build_once(source_address: str):
    """Build the subgraph once, upload shared artifacts. Returns (schema, abi, wasm) CIDs."""
    with tempfile.TemporaryDirectory() as tmpdir:
        Path(tmpdir, "schema.graphql").write_text(SCHEMA)
        Path(tmpdir, "package.json").write_text(PACKAGE_JSON)
        Path(tmpdir, "abis").mkdir()
        Path(tmpdir, "abis", "Dummy.json").write_text("[]")
        Path(tmpdir, "src").mkdir()
        Path(tmpdir, "src", "mapping.ts").write_text(MAPPING)
        Path(tmpdir, "subgraph.yaml").write_text(
            make_manifest("build", source_address, start_block=0)
        )

        print("Building subgraph (one-time)...")
        print("  npm install...")
        run("npm install --silent 2>&1", cwd=tmpdir)
        print("  codegen + build...")
        run("npx graph codegen 2>&1", cwd=tmpdir)
        run("npx graph build 2>&1", cwd=tmpdir)

        schema_cid = ipfs_add(SCHEMA)
        abi_cid = ipfs_add("[]")
        wasm_dir = Path(
            tmpdir,
            "build",
            next(p.name for p in Path(tmpdir, "build").iterdir() if p.is_dir()),
        )
        wasm_file = next(wasm_dir.glob("*.wasm"))
        wasm_cid = ipfs_add(wasm_file.read_bytes())

        print(f"  schema={schema_cid} abi={abi_cid} wasm={wasm_cid}")
        return schema_cid, abi_cid, wasm_cid


# --- Studio helpers (shared with deploy-studio-subgraph.py) -----------------


def derive_display_name(name: str) -> str:
    return name.replace("-", " ").replace("_", " ").title()


def psql(sql: str, db: str = "studio") -> str:
    result = subprocess.run(
        [
            "docker", "compose", "exec", "-T", "postgres",
            "psql", "-U", "postgres", "-d", db, "-tAc", sql,
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"psql failed: {sql}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def ensure_user(eth_address: str):
    """Return (userId, deployKey), creating the studio user if it doesn't exist."""
    query = (
        f"SELECT id, \"deployKey\" FROM \"Users\" "
        f"WHERE lower(\"ethAddress\") = lower('{eth_address}');"
    )
    row = psql(query)
    if not row:
        print(f"User {eth_address} not found - seeding via seed-studio-user.sh...")
        seed = subprocess.run(
            ["bash", os.path.join(REPO_ROOT, "scripts", "seed-studio-user.sh"), eth_address],
            cwd=REPO_ROOT,
        )
        if seed.returncode != 0:
            print("seed-studio-user.sh failed", file=sys.stderr)
            sys.exit(1)
        row = psql(query)
    if not row:
        print(f"User {eth_address} still missing after seed", file=sys.stderr)
        sys.exit(1)
    user_id, deploy_key = row.split("|")
    return int(user_id), deploy_key


def ensure_subgraph_row(user_id: int, name: str, display_name: str) -> int:
    """Insert the Subgraphs row (idempotent), return its id."""
    psql(
        f"INSERT INTO \"Subgraphs\" (name, \"displayName\", \"userId\") "
        f"VALUES ('{name}', '{display_name}', {user_id}) "
        f"ON CONFLICT (\"userId\", name) DO NOTHING;"
    )
    sid = psql(
        f"SELECT id FROM \"Subgraphs\" "
        f"WHERE \"userId\" = {user_id} AND name = '{name}';"
    )
    return int(sid)


def deploy(deploy_key: str, name: str, version_label: str, ipfs_hash: str) -> dict:
    """Call subgraph_deploy on the deployment-router (deploys to graph-node)."""
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "subgraph_deploy",
            "params": {
                "name": name,
                "version_label": version_label,
                "ipfs_hash": ipfs_hash,
                "deploy_key": deploy_key,
            },
        }
    ).encode()
    req = Request(DEPLOYMENT_ROUTER_URL, body, {"Content-Type": "application/json"})
    try:
        with urlopen(req, timeout=180) as resp:
            return json.loads(resp.read())
    except (HTTPError, URLError) as err:
        print(f"Could not reach deployment-router at {DEPLOYMENT_ROUTER_URL}: {err}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("eth_address", help="studio wallet address")
    parser.add_argument("count", nargs="?", type=int, default=1, help="how many (default 1)")
    parser.add_argument("prefix", nargs="?", default="test-subgraph", help="name prefix")
    parser.add_argument("--version-label", default="v0.1.0", help="default v0.1.0")
    args = parser.parse_args()

    count = args.count
    prefix = args.prefix
    version_label = args.version_label

    source_address = get_contract_address("L2GraphToken.address", "horizon.json")

    user_id, deploy_key = ensure_user(args.eth_address)
    print(f"user id={user_id}")

    schema_cid, abi_cid, wasm_cid = build_once(source_address)

    print(f"\nSeeding {count} studio subgraph(s) for u{user_id}: {prefix}-1..{prefix}-{count}\n")

    deployed = 0
    for i in range(count):
        idx = i + 1
        name = f"{prefix}-{idx}"
        display_name = derive_display_name(name)
        start_block = idx

        manifest = make_ipfs_manifest(
            name, source_address, start_block, schema_cid, abi_cid, wasm_cid
        )
        ipfs_hash = ipfs_add(manifest)

        subgraph_id = ensure_subgraph_row(user_id, name, display_name)

        resp = deploy(deploy_key, name, version_label, ipfs_hash)
        if "result" in resp:
            deployed += 1
            print(f"  {name}  s{subgraph_id}  {ipfs_hash}  deployed '{version_label}'")
        else:
            msg = (resp.get("error") or {}).get("message", "")
            if "Version label already exists" in msg:
                deployed += 1
                print(f"  {name}  s{subgraph_id}  {ipfs_hash}  already deployed")
            else:
                print(f"  {name}  FAILED: {msg or resp}", file=sys.stderr)

    print(f"\n{deployed}/{count} subgraph(s) deployed to graph-node and seeded in Studio.")
    print("NOT published to GNS - publish each from the Studio UI with your wallet.")
    print(f"Studio: http://localhost:5000/studio/")


if __name__ == "__main__":
    main()
