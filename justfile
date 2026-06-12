# If .env.local exists, layer it over .env for docker compose
env_files := if path_exists(".env.local") == "true" { "--env-file .env --env-file .env.local" } else { "" }

default:
    @just --list

# Resolve the active recipe (or specify one) into .env. `docker compose`
# picks .env up automatically — after this, bare `docker compose` commands
# work without --env-file. (.env.local is baked into the resolved .env;
# {{env_files}} layering below covers post-resolve .env.local edits.)
# Recipe selection: $RECIPE → .recipe.local → .recipe → "baseline".
resolve recipe="":
    ./scripts/resolve-recipe.sh {{recipe}}

# List available recipes.
recipes:
    @ls -1 recipes/*.json | sed 's,recipes/,,; s,\.json$,,'

# Show the current active recipe selection (without resolving).
recipe-active:
    @if [ -f .recipe.local ]; then \
        echo "from .recipe.local: $(cat .recipe.local)"; \
    elif [ -f .recipe ]; then \
        echo "from .recipe: $(cat .recipe)"; \
    else \
        echo "from default: baseline"; \
    fi

# Bring the compose stack up. Resolves the active recipe first (writes
# .env), then `docker compose up -d --build`. Pass a recipe name as the
# first arg to override; remaining args forward to compose.
up recipe="" *args="":
    ./scripts/resolve-recipe.sh {{recipe}}
    docker compose {{env_files}} up -d --build {{args}}

# Tear the compose stack down.
down *args:
    docker compose {{env_files}} down {{args}}

# Follow logs for one or more services
logs *services:
    docker compose {{env_files}} logs -f {{services}}

# Rebuild and restart specific services (or all if no args). Useful after
# editing run.sh / Dockerfile in any container.
rebuild *services:
    docker compose {{env_files}} up -d --build {{services}}

# Connect the current container to the compose network so service hostnames resolve
connect:
    ./scripts/connect-network.sh

# Capture local-network state for offline debugging.
# Default output dir: _dumps/<UTC-timestamp>. Pass an arg for a custom path.
dump-state *args:
    ./scripts/dump-state.sh {{args}}

# Snapshot the running stack for fast restore later.
# Default output: _snapshots/<active-recipe>/. Stack must be up + healthy + ready.
bake-snapshot *args:
    ./scripts/bake-snapshot.sh {{args}}

# Restore the stack from a previously-baked snapshot. Destructive on the
# named volumes — wipes current state. Default: the fingerprint-resolved slot
# for the active recipe (FRESH if inputs match, else latest with a STALE warning).
restore-snapshot *args:
    ./scripts/restore-snapshot.sh {{args}}

# List baked baselines (recipe / fingerprint / age / size; * = current fingerprint).
baseline-list:
    ./scripts/baseline-list.sh

# Mine N blocks (default 1), advancing time by 12s per block
mine count="1":
    ./scripts/mine-block.sh {{count}}

# Advance N epochs (default 1) by mining the required blocks
advance-epoch count="1":
    ./scripts/advance-epoch.sh {{count}}

# Recreate containers, preserving volumes (chain state etc.)
restart:
    docker compose {{env_files}} down
    docker compose {{env_files}} up -d

# Tear the stack down and wipe volumes — clean slate (run `up` to start fresh).
# Activates every defined profile during teardown so containers from inactive
# recipes (e.g. dipper/iisa left behind when switching baseline ↔ indexing-payments)
# are removed too — otherwise they hold volume references and the subsequent
# `volume rm` fails silently, leaving stale address books that break the next
# `up` in Phase 3 of graph-contracts (stale IssuanceAllocator etc.).
# Also force-removes leftover per-test compose stacks (`local-network-test-*`)
# from `cargo nextest` runs.
reset:
    -docker ps -a --filter "name=^local-network-test-" -q | xargs -r docker rm -f
    -COMPOSE_PROFILES=$(docker compose config --profiles | paste -sd,) \
        docker compose {{env_files}} down -v --remove-orphans
    -docker volume ls -q --filter "name=^local-network_" | xargs -r docker volume rm

# Stop containers whose service is no longer in the active profile set —
# e.g. dipper/iisa left running after `just up baseline` from indexing-payments.
# `docker compose up --remove-orphans` does NOT cover this (it only removes
# services missing from the compose file entirely). Use this after a recipe
# shrink, or use `just reset` for a full wipe.
stop-orphans:
    #!/usr/bin/env bash
    set -eu
    active=$(docker compose config --services 2>/dev/null | sort)
    running=$(docker compose ps --services --status=running 2>/dev/null | sort)
    orphans=$(comm -23 <(echo "$running") <(echo "$active"))
    if [ -z "$orphans" ]; then
      echo "No orphan services running."
    else
      echo "Stopping out-of-profile services:"
      echo "$orphans" | sed 's/^/  /'
      echo "$orphans" | xargs docker compose stop
    fi

# Run integration tests (forwards args to tests/justfile)
test *args:
    just -f tests/justfile test {{args}}

# Run a recipe's test set from a CLEAN baked baseline: resolve recipe →
# restore _snapshots/<recipe>/ → nextest with the recipe's test_profile.
# Reset hygiene so runs don't drift on accumulated stack state. Bake first
# with `just up <recipe> && just bake-snapshot`.
#   just test-set                 # active recipe
#   just test-set reo-live        # explicit recipe (+ extra nextest args)
test-set *args:
    ./scripts/test-set.sh {{args}}
