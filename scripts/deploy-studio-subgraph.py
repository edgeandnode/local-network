#!/usr/bin/env python3
"""Make an already-deployed graph-node subgraph show up in Studio.

For a given studio wallet address and graph-node subgraph name this:
  1. ensures a verified studio User exists (delegates to seed-studio-user.sh),
  2. inserts the Subgraphs row for that user,
  3. calls subgraph_deploy on the studio deployment-router with the user's
     deploy key, which creates the SubgraphVersion, the u<uid>/s<sid>/v<vid>
     + .../latest graph-node aliases, and the playground/query-proxy routing.

The deployment hash is read live from graph-node, so this survives a fresh
deploy (the hash changes every rebuild). Re-running is idempotent: an existing
Subgraphs row or version label is left untouched.

The Studio display name is derived from the graph-node name (kebab/snake ->
Title Case), since graph-node carries no reliable human-readable name. Override
with --display-name when the derived title isn't what you want.

Targets localhost (works on an all-local Mac stack, or on the VM over SSH).
Override endpoints via env if needed: GRAPH_NODE_QUERY, DEPLOYMENT_ROUTER_URL.

Usage:
    python3 scripts/deploy-studio-subgraph.py 0xAC7f...3240 indexing-payments
    python3 scripts/deploy-studio-subgraph.py 0xAC7f...3240 graph-network v0.2.0
    python3 scripts/deploy-studio-subgraph.py 0xAC7f...3240 my-sg --display-name "My SG"
"""

import argparse
import json
import os
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GRAPH_NODE_QUERY = os.environ.get("GRAPH_NODE_QUERY", "http://localhost:8000")
DEPLOYMENT_ROUTER_URL = os.environ.get(
    "DEPLOYMENT_ROUTER_URL", "http://localhost:4001/deploy"
)


def derive_display_name(name: str) -> str:
    """kebab/snake-case graph-node name -> Title Case Studio display name."""
    return name.replace("-", " ").replace("_", " ").title()


def psql(sql: str, db: str = "studio") -> str:
    """Run a one-shot query against a stack postgres DB, return trimmed output."""
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


def get_deployment(name: str) -> str:
    """Read the live deployment hash for a named subgraph from graph-node."""
    url = f"{GRAPH_NODE_QUERY}/subgraphs/name/{name}"
    req = Request(
        url,
        json.dumps({"query": "{ _meta { deployment } }"}).encode(),
        {"Content-Type": "application/json"},
    )
    try:
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
    except (HTTPError, URLError) as err:
        print(f"Could not reach graph-node at {url}: {err}", file=sys.stderr)
        sys.exit(1)
    meta = (data.get("data") or {}).get("_meta")
    if not meta or not meta.get("deployment"):
        print(f"No '{name}' subgraph on graph-node. Is it deployed?", file=sys.stderr)
        sys.exit(1)
    return meta["deployment"]


def ensure_user(eth_address: str) -> tuple[int, str]:
    """Return (userId, deployKey), creating the studio user if it doesn't exist."""
    row = psql(
        f"SELECT id, \"deployKey\" FROM \"Users\" "
        f"WHERE lower(\"ethAddress\") = lower('{eth_address}');"
    )
    if not row:
        print(f"User {eth_address} not found — seeding via seed-studio-user.sh...")
        seed = subprocess.run(
            ["bash", os.path.join(REPO_ROOT, "scripts", "seed-studio-user.sh"), eth_address],
            cwd=REPO_ROOT,
        )
        if seed.returncode != 0:
            print("seed-studio-user.sh failed", file=sys.stderr)
            sys.exit(1)
        row = psql(
            f"SELECT id, \"deployKey\" FROM \"Users\" "
            f"WHERE lower(\"ethAddress\") = lower('{eth_address}');"
        )
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
    """Call subgraph_deploy on the deployment-router."""
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
        with urlopen(req, timeout=120) as resp:
            return json.loads(resp.read())
    except (HTTPError, URLError) as err:
        print(f"Could not reach deployment-router at {DEPLOYMENT_ROUTER_URL}: {err}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("eth_address", help="studio wallet address")
    parser.add_argument("name", help="graph-node subgraph name (e.g. graph-network)")
    parser.add_argument("version_label", nargs="?", default="v0.1.0", help="default v0.1.0")
    parser.add_argument(
        "--display-name",
        help="Studio display name (default: Title Case of name)",
    )
    args = parser.parse_args()

    name = args.name
    display_name = args.display_name or derive_display_name(name)
    version_label = args.version_label

    ipfs_hash = get_deployment(name)
    print(f"{name} deployment: {ipfs_hash}")

    user_id, deploy_key = ensure_user(args.eth_address)
    print(f"user id={user_id}")

    subgraph_id = ensure_subgraph_row(user_id, name, display_name)
    print(f"Subgraphs row id={subgraph_id} (u{user_id}/{name}, \"{display_name}\")")

    resp = deploy(deploy_key, name, version_label, ipfs_hash)

    if "result" in resp:
        r = resp["result"]
        print(f"\nDeployed version '{version_label}'.")
        print(f"  playground: {r['playground']}")
        print(f"  queries:    {r['queries']}")
    else:
        msg = (resp.get("error") or {}).get("message", "")
        if "Version label already exists" in msg:
            print(f"\nVersion '{version_label}' already deployed — nothing to do.")
            print(f"  playground: http://localhost:5000/subgraph/{name}")
            print(f"  queries:    http://localhost:4002/query/{user_id}/{name}/{version_label}")
        else:
            print(f"\nsubgraph_deploy failed: {msg or resp}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
