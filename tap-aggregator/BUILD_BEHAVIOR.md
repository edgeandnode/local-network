# TAP Aggregator V2/Horizon Build Behavior Documentation

## Overview

This document describes the expected behavior when building and running the TAP Aggregator service with v2/horizon features for the local-network upgrade. The service is built from the `horizon` branch with `v2` features enabled.

## Build Process

### Successful Build Indicators

When the Docker build completes successfully, you should see:

1. **Repository cloning**: 
   ```
   Cloning timeline-aggregation-protocol horizon branch...
   ```

2. **Build information display**:
   ```
   === TAP Aggregator V2/Horizon Build ===
   Repository: semiotic-ai/timeline-aggregation-protocol
   Branch: horizon
   Commit: [commit hash]
   Building for local-network v2 upgrade
   =======================================
   ```

3. **Rust compilation**: 
   ```
   Building TAP Aggregator with v2 features...
   cargo build --release --bin tap_aggregator --features v2
   ```

4. **Binary verification**: Both build and runtime stages verify `tap_aggregator --help` works

### Expected Build Time and Size

- **Build time**: ~140-150 seconds (first build, cached builds much faster)
- **Image size**: ~117MB (optimized multi-stage build)
- **Features**: v2 protocol features enabled by default

## Runtime Behavior

### Binary Functionality

The tap_aggregator binary should show comprehensive help output including v2-specific options:

```bash
# Test binary directly
docker run --rm --entrypoint="tap_aggregator" local-network-tap-aggregator --help
```

### Expected Startup Sequence

When the container starts correctly in local-network context:

1. **Environment loading**: `.env` file sourced from `/opt/.env`
2. **Contract address resolution**: `TAPVerifier.address` read from `contracts.json`
3. **Configuration setup**:

   ```bash
   export TAP_PORT="${TAP_AGGREGATOR}"
   export TAP_PRIVATE_KEY="${ACCOUNT0_SECRET}"
   export TAP_DOMAIN_CHAIN_ID=1337
   export TAP_DOMAIN_NAME="TAP"
   export TAP_DOMAIN_VERIFYING_CONTRACT="${tap_verifier}"
   export TAP_DOMAIN_VERSION="1"
   ```

4. **Service startup**: `tap_aggregator` binary execution

### Expected Success Patterns

Look for these log patterns indicating successful startup:

```
JSON-RPC server listening on port 7610
server listening
Starting TAP aggregator server
gRPC server initialized 
EIP-712 domain configured
Ready to accept aggregation requests
```

**Note**: The service uses port 7610 (from `TAP_AGGREGATOR` env var), not 7701.

### Expected Failure Points (Normal in Incomplete Environment)

The TAP Aggregator service will fail gracefully in local-network until dependencies are ready:

#### 1. Missing Environment File
- **Symptom**: `/opt/.env: No such file`
- **Cause**: Container started without proper environment mounting
- **Status**: Expected until full local-network setup

#### 2. Missing Contract Configuration
- **Symptom**: `TAPVerifier.address` not found in `/opt/contracts.json`
- **Cause**: TAP contracts not yet deployed
- **Status**: Expected until contract deployment phase

#### 3. Invalid Private Key
- **Symptom**: Private key parsing errors
- **Cause**: Invalid or missing `ACCOUNT0_SECRET`
- **Status**: Expected until proper key configuration

#### 4. Port Binding Issues
- **Symptom**: `Address already in use` or binding failures
- **Cause**: Port conflicts or permission issues
- **Status**: Environment-specific, check port availability

## V2/Horizon Specific Features

### Enhanced Protocol Support

The horizon branch includes these v2 enhancements:

1. **Extended Receipt Format**: Additional fields for `payer`, `data_service`, `service_provider`
2. **Enhanced RAV Structure**: Metadata field and improved aggregation logic
3. **Backward Compatibility**: Conversion layers for v1 compatibility
4. **Improved Error Handling**: Better error codes and messages

### Build Features

- **Default v2 Features**: `default = ["v2"]` in Cargo.toml
- **Explicit Feature Flag**: `--features v2` ensures v2 capabilities
- **Protocol Selection**: Runtime detection of receipt versions

## Testing and Validation

### Test Script Usage

```bash
# Test the horizon/v2 build
./test-build.sh
```

The test script validates:
- ✅ Build completes with horizon branch
- ✅ v2 features compiled successfully  
- ✅ Binary help output includes v2 options
- ✅ Service startup with proper environment (server listening)

#### Test Environment Setup

The test script automatically:
1. **Uses actual .env**: Mounts the root local-network `.env` file with `TAP_AGGREGATOR=7610`
2. **Provides contracts.json**: Creates minimal contract configuration for testing
3. **Validates startup**: Confirms the service starts and listens on port 7610
4. **Analyzes logs**: Checks for expected success patterns vs error patterns

### Manual Testing

```bash
# Build the image
docker build -t local-network-tap-aggregator .

# Test binary directly
docker run --rm --entrypoint="tap_aggregator" local-network-tap-aggregator --help

# Test with minimal environment (will fail but show configuration)
docker run --rm -e TAP_PRIVATE_KEY=0x123... local-network-tap-aggregator
```

## Integration with Local Network

### Required Components for Full Operation

1. **Environment Configuration**: Proper `.env` file with account secrets
2. **Contract Deployment**: TAP contracts deployed to local chain
3. **Contract Registry**: `contracts.json` with TAPVerifier address
4. **Network Connectivity**: Access to local blockchain on port 8545

### Expected Integration Flow

1. **Contract Deployment**: `tap-contracts` service deploys TAP verifier
2. **Contract Discovery**: `contracts.json` updated with deployment addresses
3. **Environment Setup**: Service configuration mounted to container
4. **Service Startup**: TAP Aggregator starts and validates configuration
5. **Health Check**: Service responds to JSON-RPC health requests

## Troubleshooting

### Build Issues

- **Rust Compilation Errors**: Check horizon branch is compatible with Rust 1.86
- **Feature Conflicts**: Ensure v2 features don't conflict with dependencies
- **Network Issues**: Verify access to GitHub for repository cloning

### Runtime Issues

- **Configuration Errors**: Check environment variable formatting
- **Port Conflicts**: Ensure TAP_PORT (7610) is available
- **Contract Errors**: Verify TAPVerifier contract is deployed and accessible

### Development Notes

For v2/horizon development:
- Service uses enhanced receipt validation with v2 fields
- Backward compatibility maintained through conversion layers
- Enhanced metrics include v2-specific aggregation statistics
- EIP-712 domain handling supports both v1 and v2 message formats