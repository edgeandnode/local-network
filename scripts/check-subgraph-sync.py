#!/usr/bin/env python3
"""Check sync status of named subgraphs on the local graph-node.

Usage:
    python3 scripts/check-subgraph-sync.py                           # all named subgraphs
    python3 scripts/check-subgraph-sync.py indexing-payments          # specific subgraph
    python3 scripts/check-subgraph-sync.py --resume indexing-payments # resume if paused, then check

Exit codes: 0 = all synced (lag <= MAX_LAG), 1 = stalled/missing/errored.
"""

import json
import sys
import time
from urllib.error import URLError
from urllib.request import Request, urlopen

GRAPH_NODE_STATUS = "http://localhost:8030/graphql"
GRAPH_NODE_QUERY = "http://localhost:8000"
GRAPH_NODE_ADMIN = "http://localhost:8020"
NAMED_SUBGRAPHS = ["graph-network", "semiotic/tap", "block-oracle", "indexing-payments"]
MAX_LAG = 5
RESUME_TIMEOUT = 30
RESUME_POLL = 5


def gql(url: str, query: str) -> dict:
    req = Request(
        url, json.dumps({"query": query}).encode(), {"Content-Type": "application/json"}
    )
    with urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read())
    if "errors" in data:
        raise RuntimeError(f"GraphQL error from {url}: {data['errors']}")
    return data["data"]


def resolve_deployment(name: str) -> str | None:
    """Query the named subgraph endpoint for its deployment ID."""
    try:
        data = gql(
            f"{GRAPH_NODE_QUERY}/subgraphs/name/{name}",
            "{ _meta { deployment } }",
        )
        return data["_meta"]["deployment"]
    except Exception:
        return None


def fetch_sync_status(deployment: str) -> dict | None:
    """Query admin endpoint for indexing status of a deployment."""
    try:
        data = gql(
            GRAPH_NODE_STATUS,
            f'{{ indexingStatuses(subgraphs: ["{deployment}"]) '
            f"{{ subgraph synced health fatalError {{ message }} "
            f"chains {{ latestBlock {{ number }} chainHeadBlock {{ number }} }} }} }}",
        )
        statuses = data["indexingStatuses"]
        if not statuses:
            return None
        s = statuses[0]
        chains = s.get("chains", [])
        if not chains:
            return {
                "health": s.get("health", "unknown"),
                "synced": s.get("synced", False),
            }
        return {
            "health": s.get("health", "unknown"),
            "synced": s.get("synced", False),
            "latest_block": int(chains[0]["latestBlock"]["number"]),
            "chain_head": int(chains[0]["chainHeadBlock"]["number"]),
            "fatal_error": (s.get("fatalError") or {}).get("message"),
        }
    except Exception:
        return None


def resume_subgraph(deployment: str) -> bool:
    """Send subgraph_resume JSON-RPC to graph-node admin."""
    try:
        payload = json.dumps(
            {
                "jsonrpc": "2.0",
                "method": "subgraph_resume",
                "params": {"deployment": deployment},
                "id": 1,
            }
        ).encode()
        req = Request(GRAPH_NODE_ADMIN, payload, {"Content-Type": "application/json"})
        with urlopen(req, timeout=5) as resp:
            resp.read()
        return True
    except Exception:
        return False


def check_one(name: str, do_resume: bool) -> bool:
    """Check sync status for a single named subgraph. Returns True if synced."""
    deployment = resolve_deployment(name)
    if deployment is None:
        print(f"{name:<20s}  {'':16s}  NOT FOUND")
        return False

    dep_short = deployment[:16] + "..."

    if do_resume:
        resume_subgraph(deployment)
        deadline = time.monotonic() + RESUME_TIMEOUT
        while time.monotonic() < deadline:
            status = fetch_sync_status(deployment)
            if status and status.get("latest_block") is not None:
                lag = status["chain_head"] - status["latest_block"]
                if lag <= MAX_LAG:
                    break
            time.sleep(RESUME_POLL)

    status = fetch_sync_status(deployment)
    if status is None:
        print(f"{name:<20s}  {dep_short:19s}  NO STATUS")
        return False

    if status.get("fatal_error"):
        print(f"{name:<20s}  {dep_short:19s}  FATAL  {status['fatal_error']}")
        return False

    if status.get("latest_block") is None:
        print(f"{name:<20s}  {dep_short:19s}  {status['health']}")
        return status.get("synced", False)

    lag = status["chain_head"] - status["latest_block"]
    if lag <= MAX_LAG:
        label = "synced"
    else:
        label = "STALLED"
    print(f"{name:<20s}  {dep_short:19s}  {label:<8s} (lag={lag})")
    return lag <= MAX_LAG


def main() -> int:
    args = sys.argv[1:]
    do_resume = False
    names = []

    for arg in args:
        if arg == "--resume":
            do_resume = True
        elif arg.startswith("-"):
            print(f"Unknown flag: {arg}", file=sys.stderr)
            return 1
        else:
            names.append(arg)

    if not names:
        names = NAMED_SUBGRAPHS

    try:
        all_ok = all(check_one(name, do_resume) for name in names)
    except (URLError, ConnectionError) as e:
        print(f"Cannot reach graph-node: {e}", file=sys.stderr)
        return 1

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
