# Indexer Agent Testing Flow

This guide explains how to run tests for the indexer-agent when developing from source.

## Prerequisites

- Docker installed and running
- Node.js 20 or 22 installed
- Indexer-agent source initialized: `git submodule update --init --recursive indexer-agent/source`

## Quick Start

From the local-network root directory:

```bash
# Run all tests
./scripts/test-indexer-agent.sh

# Run specific test command
./scripts/test-indexer-agent.sh test:ci
./scripts/test-indexer-agent.sh test         # More verbose output
```

**⚠️ Important**: 
- Tests can take 10-15 minutes or more to complete, especially on first run when dependencies are being installed. The test suite runs tests for multiple packages (indexer-common, indexer-agent, indexer-cli) sequentially.
- **The test script may exit with a non-zero status code even when it runs successfully** - this just means some tests failed. Always check the output or log file to see the actual test results and failure details.

## How It Works

The test script automatically:

1. **Starts a fresh PostgreSQL container** on port 5433 (to avoid conflicts with local-network's PostgreSQL on 5432)
2. **Sets up test environment variables** required by the test suite
3. **Installs dependencies** if not already present
4. **Runs the tests** using the test command specified
5. **Cleans up** the PostgreSQL container on exit

## Test Environment

The script sets up the following test database:
- Host: `localhost`
- Port: `5433`
- Database: `indexer_tests`
- User: `testuser`
- Password: `testpass`

## Running Specific Tests

You can pass any yarn test command to the script:

```bash
# Run tests for a specific file
./scripts/test-indexer-agent.sh test src/__tests__/agent.ts

# Run tests with coverage
./scripts/test-indexer-agent.sh test --coverage

# Run tests in watch mode
./scripts/test-indexer-agent.sh test --watch
```

### Running Tests for Specific Packages

Since the monorepo contains multiple packages, you can run tests for specific packages to save time:

```bash
# Run tests only for indexer-agent package
cd indexer-agent/source/packages/indexer-agent
export POSTGRES_TEST_HOST=localhost
export POSTGRES_TEST_PORT=5433
export POSTGRES_TEST_DATABASE=indexer_tests
export POSTGRES_TEST_USERNAME=testuser
export POSTGRES_TEST_PASSWORD=testpass
yarn test

# Note: You'll need to set up PostgreSQL container manually for this approach
```

## Important Learnings

### Directory Navigation
- **Always check your current directory** before running commands with `pwd`
- The test script changes directories to `indexer-agent/source` during execution
- Test output files are created in the directory where you run the script
- After debugging, you might be in `indexer-agent/source` instead of the local-network root
- Use absolute paths when in doubt: `/home/pablo/repos/local-network/scripts/test-indexer-agent.sh`

### Understanding Test Output
- The test script exits with non-zero status if any tests fail - this is normal
- Always check the actual test output to understand what happened
- Tests run for multiple packages sequentially:
  1. `@graphprotocol/indexer-common` (runs first)
  2. `@graphprotocol/indexer-agent` (only runs if indexer-common passes)
  3. `@graphprotocol/indexer-cli` (only runs if previous packages pass)
- If indexer-common fails, the other packages won't run at all

### Making Code Changes
- After modifying TypeScript files, you must compile before running tests:
  ```bash
  cd indexer-agent/source
  yarn compile
  ```
- Test error line numbers may not match exactly due to transpilation
- Debug console.log statements work and will appear in test output

### Environment Variables
- `INDEXER_TEST_JRPC_PROVIDER_URL` - Ethereum RPC endpoint (defaults to public Arbitrum Sepolia)
- `INDEXER_TEST_API_KEY` - API key for The Graph's subgraph endpoints (may be required)

## Troubleshooting

### Tests fail with connection errors
- Ensure Docker is running
- Check if port 5433 is available: `lsof -i :5433`
- Try running with more verbose output: `./scripts/test-indexer-agent.sh test`

### Dependencies not found
- The script should auto-install dependencies, but you can manually run:
  ```bash
  cd indexer-agent/source
  yarn install --frozen-lockfile
  ```

### PostgreSQL container issues
- The script automatically cleans up containers, but you can manually remove:
  ```bash
  docker stop indexer-tests-postgres
  docker rm indexer-tests-postgres
  ```

### Cleaning Test Output
- Remove ANSI escape codes from test output for easier reading:
  ```bash
  cat test-output.log | sed 's/\x1b\[[0-9;]*m//g' > test-output-clean.log
  ```

## CI Integration

The tests run in CI using GitHub Actions with:
- PostgreSQL service container
- Matrix testing for Node.js 20 and 22
- Environment secrets for integration tests (optional)

### Timeout Considerations

When running tests in automation or CI:
- Set appropriate timeouts (15-20 minutes minimum)
- First runs take longer due to dependency installation
- The test suite runs multiple packages sequentially (indexer-common → indexer-agent → indexer-cli)

## Manual Testing (Advanced)

If you need more control, you can run the PostgreSQL container manually:

```bash
# Start PostgreSQL
docker run -d \
  --name indexer-tests-postgres \
  -e POSTGRES_DB=indexer_tests \
  -e POSTGRES_USER=testuser \
  -e POSTGRES_PASSWORD=testpass \
  -p 5433:5432 \
  postgres:13

# Set environment
export POSTGRES_TEST_HOST=localhost
export POSTGRES_TEST_PORT=5433
export POSTGRES_TEST_DATABASE=indexer_tests
export POSTGRES_TEST_USERNAME=testuser
export POSTGRES_TEST_PASSWORD=testpass
export NODE_OPTIONS="--dns-result-order=ipv4first"

# Run tests
cd indexer-agent/source
yarn test

# Clean up
docker stop indexer-tests-postgres
docker rm indexer-tests-postgres
```