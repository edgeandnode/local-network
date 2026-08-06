#!/usr/bin/env python3
"""Set an offchain indexing rule on an indexer-agent for a named subgraph.

Usage:
    python3 scripts/set-offchain-rule.py indexing-payments               # primary agent (port 7600)
    python3 scripts/set-offchain-rule.py indexing-payments --port 17620   # specific agent

Exit codes: 0 = rule set, 1 = subgraph not found or agent unreachable.
"""

import json
import sys
from urllib.error import URLError
from urllib.request import Request, urlopen

GRAPH_NODE_QUERY = "http://localhost:8000"
DEFAULT_AGENT_PORT = 7600


def gql(url: str, query: str) -> dict:
    req = Request(
        url, json.dumps({"query": query}).encode(), {"Content-Type": "application/json"}
    )
    with urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read())
    if data.get("errors"):
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


def set_rule(port: int, deployment: str) -> dict:
    """Set an offchain indexing rule on the agent management API."""
    mutation = (
        "mutation { setIndexingRule("
        f'identifier: "{deployment}", '
        "rule: { "
        f'identifier: "{deployment}", '
        "identifierType: deployment, "
        "decisionBasis: offchain, "
        'protocolNetwork: "eip155:1337"'
        " }) { identifier decisionBasis } }"
    )
    return gql(f"http://localhost:{port}/", mutation)


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(
            "Usage: set-offchain-rule.py <subgraph-name> [--port PORT]", file=sys.stderr
        )
        return 1

    name = None
    port = DEFAULT_AGENT_PORT
    i = 0
    while i < len(args):
        if args[i] == "--port":
            if i + 1 >= len(args):
                print("--port requires a value", file=sys.stderr)
                return 1
            port = int(args[i + 1])
            i += 2
        elif args[i].startswith("-"):
            print(f"Unknown flag: {args[i]}", file=sys.stderr)
            return 1
        else:
            name = args[i]
            i += 1

    if name is None:
        print(
            "Usage: set-offchain-rule.py <subgraph-name> [--port PORT]", file=sys.stderr
        )
        return 1

    deployment = resolve_deployment(name)
    if deployment is None:
        print(f"subgraph '{name}' not found on graph-node", file=sys.stderr)
        return 1

    try:
        set_rule(port, deployment)
    except (URLError, ConnectionError, RuntimeError) as e:
        print(f"failed to set rule on agent port {port}: {e}", file=sys.stderr)
        return 1

    print(f"set offchain rule for {name} ({deployment}) on agent port {port}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
