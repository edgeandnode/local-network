# If .env.local exists, layer it over .env for docker compose
env_files := if path_exists(".env.local") == "true" { "--env-file .env --env-file .env.local" } else { "" }

default:
    @just --list

# Bring the compose stack up in the background
up *args:
    docker compose {{env_files}} up -d {{args}}

# Tear the compose stack down
down *args:
    docker compose {{env_files}} down {{args}}

# Follow logs for one or more services
logs *services:
    docker compose {{env_files}} logs -f {{services}}

# Connect the current container to the compose network so service hostnames resolve
connect:
    ./scripts/connect-network.sh

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

# Tear the stack down and wipe volumes — clean slate (run `up` to start fresh)
reset:
    docker compose {{env_files}} down -v

# Run integration tests (forwards args to tests/justfile)
test *args:
    just -f tests/justfile test {{args}}
