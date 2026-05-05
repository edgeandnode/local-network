#!/usr/bin/env python3
"""Monitor a DIPs indexing request through the full agreement lifecycle.

Polls dipper's postgres for agreement status changes and checks indexing-payments
subgraph health proactively. Exits when all agreements reach a terminal state.

Usage:
    python3 scripts/monitor-dips-pipeline.py <REQUEST_ID>
    python3 scripts/monitor-dips-pipeline.py <REQUEST_ID> --timeout 300

Exit codes: 0 = all agreements AcceptedOnChain, 1 = any failure or timeout.
"""

import json
import subprocess
import sys
import time
from urllib.request import Request, urlopen

GRAPH_NODE_STATUS = "http://localhost:8030/graphql"
GRAPH_NODE_QUERY = "http://localhost:8000"
DEFAULT_TIMEOUT = 600
POLL_INTERVAL = 10
SUBGRAPH_WARN_AFTER = (
    60  # warn about indexing-payments after this many seconds in Created
)

STATUS_NAMES = {
    -1: "CREATED",
    1: "DELIVERY_FAILED",
    3: "CANCELED_BY_REQUESTER",
    4: "CANCELED_BY_INDEXER",
    5: "EXPIRED",
    6: "ACCEPTED_ON_CHAIN",
    7: "REJECTED",
    8: "ABANDONED_BY_INDEXER",
}
TERMINAL_SUCCESS = {6}
TERMINAL_FAILURE = {1, 3, 4, 5, 7, 8}
TERMINAL = TERMINAL_SUCCESS | TERMINAL_FAILURE


def gql(url: str, query: str) -> dict:
    req = Request(
        url, json.dumps({"query": query}).encode(), {"Content-Type": "application/json"}
    )
    with urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read())
    if "errors" in data:
        raise RuntimeError(f"GraphQL error from {url}: {data['errors']}")
    return data["data"]


def psql(query: str) -> str:
    """Run a query against dipper's postgres via docker exec."""
    result = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            "postgres",
            "psql",
            "-U",
            "postgres",
            "-d",
            "dipper_1",
            "-t",
            "-A",
            "-c",
            query,
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        raise RuntimeError(f"psql failed: {result.stderr.strip()}")
    return result.stdout.strip()


def fetch_request(request_id: str) -> dict | None:
    """Fetch an indexing request from dipper's DB."""
    rows = psql(
        f"SELECT id, status, deployment_id, num_candidates "
        f"FROM dipper_reg_indexing_requests WHERE id = '{request_id}'"
    )
    if not rows:
        return None
    parts = rows.splitlines()[0].split("|")
    return {
        "id": parts[0],
        "status": int(parts[1]),
        "deployment_id": parts[2],
        "num_candidates": int(parts[3]),
    }


def fetch_agreements(request_id: str) -> list[dict]:
    """Fetch all agreements for an indexing request."""
    rows = psql(
        f"SELECT id, encode(indexer_id, 'hex'), status, rejection_reason, created_at "
        f"FROM dipper_reg_indexing_agreements "
        f"WHERE indexing_request_id = '{request_id}' ORDER BY created_at"
    )
    if not rows:
        return []
    agreements = []
    for line in rows.splitlines():
        if not line.strip():
            continue
        parts = line.split("|")
        agreements.append(
            {
                "id": parts[0],
                "indexer": f"0x{parts[1]}",
                "status": int(parts[2]),
                "rejection_reason": parts[3] if len(parts) > 3 else None,
                "created_at": parts[4] if len(parts) > 4 else None,
            }
        )
    return agreements


def format_indexer(hex_addr: str) -> str:
    """Shorten 0x... address to 0xAAAA...BBBB."""
    if len(hex_addr) < 12:
        return hex_addr
    return f"{hex_addr[:6]}...{hex_addr[-4:]}"


def check_indexing_payments_health() -> str | None:
    """Check indexing-payments subgraph sync status. Returns warning message or None."""
    try:
        data = gql(
            GRAPH_NODE_QUERY + "/subgraphs/name/indexing-payments",
            "{ _meta { block { number } } }",
        )
        # If we can query it, it's at least responding
        block = data["_meta"]["block"]["number"]

        # Check lag against chain head
        status_data = gql(
            GRAPH_NODE_STATUS,
            "{ indexingStatuses { subgraph chains { latestBlock { number } "
            "chainHeadBlock { number } } } }",
        )
        for s in status_data["indexingStatuses"]:
            chains = s.get("chains", [])
            if not chains:
                continue
            latest = int(chains[0]["latestBlock"]["number"])
            head = int(chains[0]["chainHeadBlock"]["number"])
            if latest == int(block):
                lag = head - latest
                if lag > 10:
                    return f"indexing-payments subgraph lagging ({lag} blocks behind) -- chain_listener cannot see recent events"
                return None
        return None
    except Exception:
        return "indexing-payments subgraph unreachable -- chain_listener will stall"


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(
            "Usage: monitor-dips-pipeline.py <REQUEST_ID> [--timeout SECONDS]",
            file=sys.stderr,
        )
        return 1

    request_id = None
    timeout = DEFAULT_TIMEOUT
    i = 0
    while i < len(args):
        if args[i] == "--timeout":
            if i + 1 >= len(args):
                print("--timeout requires a value", file=sys.stderr)
                return 1
            timeout = int(args[i + 1])
            i += 2
        elif args[i].startswith("-"):
            print(f"Unknown flag: {args[i]}", file=sys.stderr)
            return 1
        else:
            request_id = args[i]
            i += 1

    if request_id is None:
        print(
            "Usage: monitor-dips-pipeline.py <REQUEST_ID> [--timeout SECONDS]",
            file=sys.stderr,
        )
        return 1

    # Validate request exists
    try:
        req = fetch_request(request_id)
    except RuntimeError as e:
        print(f"cannot query dipper DB: {e}", file=sys.stderr)
        return 1

    if req is None:
        print(f"request {request_id} not found", file=sys.stderr)
        return 1

    print(
        f"monitoring request {request_id}"
        f"  deployment={req['deployment_id'][:16]}..."
        f"  candidates={req['num_candidates']}"
    )

    start = time.monotonic()
    prev_states: dict[str, int] = {}
    subgraph_warned = False

    while True:
        elapsed = int(time.monotonic() - start)

        try:
            agreements = fetch_agreements(request_id)
        except RuntimeError as e:
            print(f"[+{elapsed}s] DB error: {e}", file=sys.stderr)
            time.sleep(POLL_INTERVAL)
            continue

        if not agreements:
            print(f"[+{elapsed}s] waiting for IISA candidate selection...")
            if elapsed >= timeout:
                print(f"timeout after {timeout}s with no agreements", file=sys.stderr)
                return 1
            time.sleep(POLL_INTERVAL)
            continue

        # Print state transitions
        for ag in agreements:
            key = ag["id"]
            status = ag["status"]
            if key not in prev_states or prev_states[key] != status:
                old_name = STATUS_NAMES.get(prev_states.get(key, -99), "?")
                new_name = STATUS_NAMES.get(status, f"UNKNOWN({status})")
                indexer = format_indexer(ag["indexer"])
                if key not in prev_states:
                    print(f"[+{elapsed}s] {indexer}  {new_name}")
                else:
                    reason = (
                        f"  ({ag['rejection_reason']})"
                        if ag.get("rejection_reason")
                        else ""
                    )
                    print(f"[+{elapsed}s] {indexer}  {old_name} -> {new_name}{reason}")
                prev_states[key] = status

        # Check for stale Created agreements and warn about indexing-payments
        if not subgraph_warned and elapsed >= SUBGRAPH_WARN_AFTER:
            created_count = sum(1 for ag in agreements if ag["status"] == -1)
            if created_count > 0:
                warning = check_indexing_payments_health()
                if warning:
                    print(f"[+{elapsed}s] WARNING: {warning}")
                    print(
                        f"[+{elapsed}s] {created_count} agreement(s) stuck in CREATED -- "
                        f"run: python3 scripts/check-subgraph-sync.py --resume indexing-payments"
                    )
                    subgraph_warned = True

        # Check termination
        statuses = {ag["status"] for ag in agreements}
        all_terminal = all(s in TERMINAL for s in statuses)

        if all_terminal and agreements:
            success_count = sum(1 for s in statuses if s in TERMINAL_SUCCESS)
            failure_count = sum(1 for s in statuses if s in TERMINAL_FAILURE)
            print(
                f"\ndone: {success_count} accepted, {failure_count} failed ({elapsed}s)"
            )
            if failure_count == 0:
                return 0
            return 1

        if elapsed >= timeout:
            created = sum(1 for ag in agreements if ag["status"] not in TERMINAL)
            print(
                f"\ntimeout after {timeout}s: {created} agreement(s) still pending",
                file=sys.stderr,
            )
            return 1

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    sys.exit(main())
