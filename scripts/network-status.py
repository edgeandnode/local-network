#!/usr/bin/env python3
"""Print the local network state as a tree: network > subgraph > indexer."""

import json
import sys
from urllib.request import Request, urlopen

GRAPH_NODE_STATUS = "http://localhost:8030/graphql"
GRAPH_NODE_QUERY = "http://localhost:8000"
NAMED_SUBGRAPHS = ["graph-network", "semiotic/tap", "block-oracle"]


def gql(url: str, query: str) -> dict:
    req = Request(url, json.dumps({"query": query}).encode(), {"Content-Type": "application/json"})
    with urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read())
    if "errors" in data:
        raise RuntimeError(f"GraphQL error from {url}: {data['errors']}")
    return data["data"]


def fetch_indexing_statuses() -> dict:
    """deployment_id -> {network, health, latest_block, chain_head}"""
    data = gql(GRAPH_NODE_STATUS, """{
        indexingStatuses {
            subgraph
            health
            fatalError { message }
            chains { network latestBlock { number } chainHeadBlock { number } }
        }
    }""")
    out = {}
    for s in data["indexingStatuses"]:
        chain = s["chains"][0] if s["chains"] else {}
        out[s["subgraph"]] = {
            "network": chain.get("network", "unknown"),
            "health": s["health"],
            "latest_block": int(chain.get("latestBlock", {}).get("number", 0)),
            "chain_head": int(chain.get("chainHeadBlock", {}).get("number", 0)),
            "fatal_error": (s.get("fatalError") or {}).get("message"),
        }
    return out


def fetch_subgraph_names() -> dict:
    """deployment_id -> name for known named subgraphs."""
    names = {}
    for name in NAMED_SUBGRAPHS:
        try:
            data = gql(f"{GRAPH_NODE_QUERY}/subgraphs/name/{name}", "{ _meta { deployment } }")
            dep = data["_meta"]["deployment"]
            names[dep] = name
        except Exception:
            pass
    return names


def fetch_network_subgraph_id(names: dict) -> str | None:
    for dep, name in names.items():
        if name == "graph-network":
            return dep
    return None


def fetch_allocations(ns_id: str) -> list[dict]:
    """Fetch indexers and their active allocations from the network subgraph."""
    data = gql(f"{GRAPH_NODE_QUERY}/subgraphs/id/{ns_id}", """{
        indexers(first: 100) {
            id
            url
            stakedTokens
            allocations(where: {status: Active}) {
                subgraphDeployment { ipfsHash }
                allocatedTokens
            }
        }
    }""")
    return data["indexers"]


def fetch_gns_subgraphs(ns_id: str) -> list[dict]:
    """Fetch all subgraphs published to GNS from the network subgraph."""
    all_subgraphs = []
    skip = 0
    while True:
        data = gql(f"{GRAPH_NODE_QUERY}/subgraphs/id/{ns_id}", f"""{{
            subgraphs(first: 100, skip: {skip}, orderBy: createdAt) {{
                id
                currentVersion {{
                    subgraphDeployment {{ ipfsHash }}
                }}
            }}
        }}""")
        batch = data["subgraphs"]
        all_subgraphs.extend(batch)
        if len(batch) < 100:
            break
        skip += 100
    return all_subgraphs


def format_tokens(raw: str) -> str:
    grt = int(raw) / 1e18
    if grt >= 1_000_000:
        return f"{grt / 1_000_000:.1f}M GRT"
    if grt >= 1_000:
        return f"{grt / 1_000:.1f}k GRT"
    if grt == int(grt):
        return f"{int(grt)} GRT"
    return f"{grt:.4f} GRT"


def health_indicator(status: dict) -> str:
    if status["fatal_error"]:
        return " FATAL"
    if status["health"] == "healthy":
        lag = status["chain_head"] - status["latest_block"]
        if lag <= 1:
            return " synced"
        return f" {lag} blocks behind"
    return f" {status['health']}"


def main():
    statuses = fetch_indexing_statuses()
    names = fetch_subgraph_names()
    ns_id = fetch_network_subgraph_id(names)

    if not ns_id:
        print("network subgraph not found", file=sys.stderr)
        return 1

    indexers = fetch_allocations(ns_id)
    gns_subgraphs = fetch_gns_subgraphs(ns_id)

    # All deployment IDs published to GNS
    gns_deployments = set()
    for sg in gns_subgraphs:
        cv = sg.get("currentVersion")
        if cv and cv.get("subgraphDeployment"):
            gns_deployments.add(cv["subgraphDeployment"]["ipfsHash"])

    # Build tree: network -> [(deployment, name, status, [(indexer_id, alloc_tokens)])]
    tree: dict[str, list] = {}
    for idx in indexers:
        for alloc in idx["allocations"]:
            dep = alloc["subgraphDeployment"]["ipfsHash"]
            status = statuses.get(dep, {})
            network = status.get("network", "unknown")

            if network not in tree:
                tree[network] = {}
            if dep not in tree[network]:
                tree[network][dep] = []
            tree[network][dep].append({
                "id": idx["id"],
                "url": idx.get("url", ""),
                "staked": idx["stakedTokens"],
                "allocated": alloc["allocatedTokens"],
            })

    # Print summary
    total_indexers = len(indexers)
    total_on_gns = len(gns_subgraphs)
    total_indexed = len(statuses)
    total_networks = len(tree)
    print(f"{total_indexers} indexer(s), {total_on_gns} subgraph(s) on GNS, {total_indexed} indexed by graph-node, {total_networks} network(s)\n")

    # Print tree
    networks = sorted(tree.keys())
    for ni, network in enumerate(networks):
        is_last_network = ni == len(networks) - 1
        print(f"{network}")

        deployments = sorted(tree[network].keys(), key=lambda d: names.get(d, d))
        for di, dep in enumerate(deployments):
            is_last_dep = di == len(deployments) - 1
            branch = "\u2514\u2500" if is_last_dep else "\u251c\u2500"
            cont = "  " if is_last_dep else "\u2502 "

            name = names.get(dep, "")
            status = statuses.get(dep, {})
            label = name if name else dep
            if name:
                label += f"  {dep}"
            label += health_indicator(status)

            print(f"  {branch} {label}")

            idx_list = tree[network][dep]
            for ii, idx in enumerate(idx_list):
                is_last_idx = ii == len(idx_list) - 1
                idx_branch = "\u2514\u2500" if is_last_idx else "\u251c\u2500"
                addr = idx["id"]
                alloc = format_tokens(idx["allocated"])
                print(f"  {cont} {idx_branch} {addr}  {alloc}")

        if not is_last_network:
            print()

    # Unallocated subgraphs (indexed by graph-node but no active allocation)
    allocated_deps = {dep for net in tree.values() for dep in net}
    unallocated = [dep for dep in statuses if dep not in allocated_deps]
    if unallocated:
        print(f"\nunallocated (indexed but no active allocation)")
        for i, dep in enumerate(unallocated):
            is_last = i == len(unallocated) - 1
            branch = "\u2514\u2500" if is_last else "\u251c\u2500"
            name = names.get(dep, "")
            status = statuses[dep]
            network = status.get("network", "unknown")
            label = name if name else dep
            if name:
                label += f"  {dep}"
            label += f"  ({network}){health_indicator(status)}"
            print(f"  {branch} {label}")

    # GNS-only subgraphs (published on-chain but not deployed to graph-node)
    gns_only = sorted(gns_deployments - set(statuses.keys()))
    if gns_only:
        print(f"\nGNS-only ({len(gns_only)} published on-chain, not indexed)")
        for i, dep in enumerate(gns_only):
            is_last = i == len(gns_only) - 1
            branch = "\u2514\u2500" if is_last else "\u251c\u2500"
            print(f"  {branch} {dep}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
