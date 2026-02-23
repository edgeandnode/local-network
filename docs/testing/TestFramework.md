# Task: Test Framework for Local Network Automation

> Created: 2026-02-20

## Problem

Test automation currently uses bash scripts with custom PASS/FAIL helpers. This works well for Layers 0-1 (query validation, state observation) but will not scale to Layers 2-3 (operational lifecycle, timing-dependent flows) which require polling, retries, state tracking, parallel execution, and structured assertions.

## Current State

### Scripts

| Script                          | Layer | Lines | Pattern                    |
| ------------------------------- | ----- | ----- | -------------------------- |
| `test-baseline-queries.sh`      | 0     | 192   | curl + grep for errors     |
| `test-indexer-guide-queries.sh` | 0     | 182   | curl + cast + grep         |
| `test-baseline-state.sh`        | 1     | 261   | curl + jq assertions       |
| `test-reo-eligibility.sh`       | 2-3   | ~200  | curl + cast + polling loop |

### Strengths

- Clean, readable, well-documented
- Direct access to curl, cast, docker exec, jq
- Zero compilation overhead
- Familiar to operations-oriented teams

### Pain Points Growing With Scale

- Manual assertion logic (string comparison via `eval`)
- No parallel execution
- Duplicated helpers across scripts (`gql()`, `check()`, `run_query()`)
- Polling/retry patterns fragile in bash
- No structured test reporting (JSON/TAP/XML)
- No test filtering or selective execution

## Options Evaluated

### Option A: Bash + Shared Helpers

Extract common functions into `scripts/lib/test-helpers.sh`, keep writing bash.

| Aspect         | Rating                                                  |
| -------------- | ------------------------------------------------------- |
| Learning curve | None                                                    |
| Layer 0-1 fit  | Excellent                                               |
| Layer 2-3 fit  | Poor — polling, state machines, parallelism are fragile |
| Maintenance    | Degrades as test count grows                            |

**Verdict**: Right for Layers 0-1. Not sufficient for Layers 2-3.

### Option B: Python pytest

Already installed in devcontainer (v9.0.2 + pytest-cov).

| Aspect            | Rating                                                   |
| ----------------- | -------------------------------------------------------- |
| Learning curve    | Low — 1-2 hours for bash-familiar developers             |
| Layer 0-1 fit     | Overkill — just curl + jq                                |
| Layer 2-3 fit     | Strong — fixtures, retry, async, parallel (`-n auto`)    |
| JSON assertions   | Native dict access, no jq dependency                     |
| Subprocess calls  | `subprocess.run(["cast", ...])` — more verbose than bash |
| Failure reporting | Excellent — diffs, tracebacks, captured output           |

**Available plugins**: `pytest-asyncio`, `pytest-xdist` (parallel), `pytest-timeout`, `pytest-retry`. Would need `pip install` in Dockerfile (4 lines).

### Option C: Rust + cargo-nextest

Already installed: `cargo-nextest` 0.9.127, `cargo-make` 0.37.24, full async toolchain. The eligibility-oracle project at `/git/local/eligibility-oracle-node/` demonstrates the exact patterns needed.

| Aspect             | Rating                                                          |
| ------------------ | --------------------------------------------------------------- |
| Learning curve     | Medium — team already writes Rust                               |
| Layer 0-1 fit      | Acceptable — more verbose than bash but type-safe               |
| Layer 2-3 fit      | Strong — `tokio::test`, `reqwest`, structured error handling    |
| JSON assertions    | `serde_json` value access + `pretty_assertions` for diffs       |
| Subprocess calls   | `std::process::Command` — safe (no shell escaping), but verbose |
| Failure reporting  | Good — backtraces, `anyhow` context, `pretty_assertions`        |
| Compile time       | 20-30s initial, 2-5s incremental                                |
| Parallel execution | Built into nextest — automatic, zero config                     |
| IDE support        | Full rust-analyzer autocomplete, inline docs                    |

**Key advantage**: Primary language of the devcontainer and team. No context-switching. The `reqwest` + `serde_json` + `tokio::test` pattern is already proven in the workspace.

**Key trade-off**: 20-30s initial compile per session vs instant bash execution.

### Option D: BATS or Node.js

- **BATS**: Not installed, marginal benefit over bash + helpers, still bash underneath
- **Node.js (jest/vitest)**: Available but no advantage over Python or Rust for CLI orchestration

Neither recommended.

## Comparison: Layer 2-3 Test Example

A test that creates an allocation, advances epochs, and verifies rewards:

### Bash

```bash
# Create allocation (fragile string parsing)
result=$(curl -s "$AGENT_URL" -H 'content-type: application/json' \
  -d '{"query": "mutation { createAllocation(...) { id } }"}')
alloc_id=$(echo "$result" | jq -r '.data.createAllocation.id')

# Advance 3 epochs (manual loop)
for i in 1 2 3; do
  ./scripts/advance-epoch.sh
done

# Poll until closed (manual timeout)
elapsed=0
while [ $elapsed -lt 120 ]; do
  status=$(curl -s "$SUBGRAPH_URL" ... | jq -r '.data.allocations[0].status')
  [ "$status" = "Closed" ] && break
  sleep 5; elapsed=$((elapsed + 5))
done
[ "$status" = "Closed" ] || { echo "FAIL: timed out"; exit 1; }
```

### Rust

```rust
#[tokio::test]
async fn test_allocation_lifecycle() -> Result<()> {
    let net = TestNetwork::from_env()?;

    let alloc = net.create_allocation(&deployment).await?;
    net.advance_epochs(3).await?;
    net.close_allocation(&alloc.id).await?;

    let result = net.poll_until(Duration::from_secs(120), || async {
        let a = net.query_allocation(&alloc.id).await?;
        Ok(a.status == "Closed")
    }).await?;

    assert!(result.indexing_rewards > 0, "Expected rewards, got 0");
    Ok(())
}
```

### Python

```python
def test_allocation_lifecycle(network):
    alloc = network.create_allocation(deployment)
    network.advance_epochs(3)
    network.close_allocation(alloc["id"])

    result = network.poll_until(
        timeout=120,
        check=lambda: network.query_allocation(alloc["id"])["status"] == "Closed"
    )

    assert result["indexingRewards"] != "0"
```

## Recommendation: Rust for Layers 2-3, Keep Bash for Layers 0-1

### Rationale

1. **Layers 0-1 are done and working** in bash. Moving them gains nothing.
2. **Layers 2-3 need orchestration** that bash handles poorly.
3. **Rust is the team's primary language** — the devcontainer, the eligibility-oracle, and the broader Graph ecosystem tooling are Rust-first.
4. **The tooling is already paid for**: cargo-nextest, tokio, reqwest, serde_json are all installed and proven in the workspace.
5. **pytest is the pragmatic alternative** if Rust compile times prove too disruptive during rapid test development. It's installed and ready.

### Decision Point

Try Rust first on one test (port `test-reo-eligibility.sh` to a Rust integration test). If the compile-time overhead is acceptable during active development, continue with Rust. If not, fall back to pytest — the test structure and helper patterns are identical, just in a different language.

## Implementation Plan

### Phase 1: Shared Bash Helpers (immediate)

Extract duplicated functions into a shared library:

```
scripts/lib/
  test-helpers.sh    # gql(), check(), jq_test(), run_query(), run_cast()
  test-constants.sh  # URL resolution, env loading, PATH setup
```

Refactor existing Layer 0-1 scripts to source these. No behavior change.

### Phase 2: Rust Test Crate (next)

```
tests/
  Cargo.toml
  src/
    lib.rs           # TestNetwork struct, shared helpers
    graphql.rs       # GraphQL query helpers
    cast.rs          # cast CLI wrapper
    polling.rs       # poll_until, retry logic
  tests/
    reo_eligibility.rs    # Port of test-reo-eligibility.sh
    allocation_cycle.rs   # Layer 2: create → close → verify
```

Minimal `Cargo.toml`:

```toml
[package]
name = "local-network-tests"
version = "0.1.0"
edition = "2024"

[dependencies]
reqwest = { version = "0.12", features = ["json"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
anyhow = "1"

[dev-dependencies]
pretty_assertions = "1"
```

### Phase 3: Migrate Remaining Tests

Once the pattern is proven:

- Layer 2 operational lifecycle tests in Rust
- Layer 3 timing-dependent tests in Rust
- Keep bash scripts for quick manual validation (they remain useful documentation)

### Integration

```bash
# Run bash tests (Layers 0-1)
./scripts/test-baseline-queries.sh
./scripts/test-baseline-state.sh
./scripts/test-indexer-guide-queries.sh

# Run Rust tests (Layers 2-3)
cd tests && cargo nextest run

# Run everything
cargo make test-all  # Orchestrates both
```

## Dependencies

- Extract shared bash helpers (no new deps)
- Rust test crate: `reqwest`, `serde_json`, `tokio`, `anyhow` (all already in workspace)
- Optional: `pretty_assertions` for better diff output
