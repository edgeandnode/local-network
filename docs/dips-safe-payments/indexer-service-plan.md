# Indexer Service DIPs Implementation Plan

## Overview

This plan details the minimal changes required to the Indexer Service to support the new Safe-based DIPs payment system. The indexer service acts primarily as a pass-through for DIPs, so changes are limited to protocol definitions and response handling.

## Development Branch

**Branch**: `pcv/ipfs-dips-timeout`

This work will continue on the existing `pcv/ipfs-dips-timeout` branch, which has been used for debugging and improving DIPs functionality.

## Current State

The Indexer Service currently:
- Implements gRPC server for DIPs using protocol buffers
- Forwards collect payment requests to the gateway
- Returns TAP receipts in the response
- Has no business logic for payment processing (pass-through)

## Required Changes

### 1. Database Migration for DIPs Receipts

**Location**: `indexer-service/source/migrations/`

Create a new migration for DIPs receipts table to support testing:

```sql
-- 20250XXX_dips_receipts.up.sql
CREATE TABLE IF NOT EXISTS dips_receipts (
    id UUID PRIMARY KEY,
    agreement_id UUID NOT NULL REFERENCES indexing_agreements(id),
    receipt_id VARCHAR(255) NOT NULL UNIQUE,
    amount NUMERIC(39) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    transaction_hash CHAR(66),
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    last_polled_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT valid_status CHECK (status IN ('PENDING', 'SUBMITTED', 'FAILED'))
);

CREATE INDEX idx_dips_receipts_agreement_id ON dips_receipts(agreement_id);
CREATE INDEX idx_dips_receipts_status ON dips_receipts(status);
CREATE INDEX idx_dips_receipts_receipt_id ON dips_receipts(receipt_id);
```

### 2. Protocol Buffer Updates

**Location**: `indexer-service/source/crates/dips/proto/gateway.proto`

#### Update CollectPaymentResponse

The main change is to modify the response to return a Receipt ID instead of TAP receipt:

```protobuf
// Current definition
message CollectPaymentResponse {
  uint64 version = 1;
  CollectPaymentStatus status = 2;
  bytes tap_receipt = 3;
}

// New definition
message CollectPaymentResponse {
  uint64 version = 1;
  CollectPaymentStatus status = 2;
  string receipt_id = 3;        // Receipt ID for polling
  string amount = 4;            // Payment amount in GRT
  string payment_status = 5;    // Initial status: "PENDING"
}
```

#### Add GetReceiptById RPC Method

Add a new RPC method to the service definition:

```protobuf
service GatewayDipsService {
  // ... existing methods ...
  
  /**
   * Get the status of a payment receipt by ID.
   *
   * This method allows the indexer to poll for the status of a previously
   * initiated payment collection.
   */
  rpc GetReceiptById(GetReceiptByIdRequest) returns (GetReceiptByIdResponse);
}

message GetReceiptByIdRequest {
  uint64 version = 1;
  string receipt_id = 2;
}

message GetReceiptByIdResponse {
  uint64 version = 1;
  string receipt_id = 2;
  string status = 3;            // "PENDING" | "SUBMITTED" | "FAILED"
  string transaction_hash = 4;  // Present when SUBMITTED
  string error_message = 5;     // Present when FAILED
  string amount = 6;
  string payment_submitted_at = 7;  // ISO timestamp when SUBMITTED
}
```

#### Remove TAP-specific Status Codes

Review and potentially update the `CollectPaymentStatus` enum if any codes are TAP-specific:

```protobuf
enum CollectPaymentStatus {
  ACCEPT = 0;                    // Keep - payment request accepted
  ERR_TOO_EARLY = 1;            // Keep - still relevant
  ERR_TOO_LATE = 2;             // Keep - still relevant
  ERR_AMOUNT_OUT_OF_BOUNDS = 3; // Keep - still relevant
  ERR_UNKNOWN = 99;             // Keep - generic error
}
```

### 3. Generated Code Updates

**Location**: `indexer-service/source/crates/dips/src/proto/`

After updating the proto files:

1. Regenerate the Rust bindings using the build script
2. The generated files will automatically include the new fields
3. No manual edits needed to generated code

### 4. Client Code Updates (if any)

**Location**: Check for any client code that constructs or handles `CollectPaymentResponse`

Search for usage of `CollectPaymentResponse` to ensure compatibility:
- Update any code that accesses the old `tap_receipt` field
- Add handling for new fields (`receipt_id`, `amount`, `payment_status`)

## Implementation Steps

### Step 1: Create Database Migration

1. Create new migration file for dips_receipts table
2. Add down migration to drop the table
3. Test migration up and down

### Step 2: Update Protocol Definitions

1. Modify `gateway.proto` with new response structure
2. Remove `tap_receipt` field
3. Add `receipt_id`, `amount`, and `payment_status` fields
4. Ensure backward compatibility considerations

### Step 3: Regenerate Protocol Bindings

```bash
cd indexer-service/source
cargo build -p dips
```

This will trigger the build script to regenerate the proto bindings.

### Step 4: Update Response Handling

Search for any code that constructs `CollectPaymentResponse`:

```bash
# Find usage of CollectPaymentResponse
grep -r "CollectPaymentResponse" crates/
```

Update any found usage to use the new fields.

### Step 5: Version Compatibility

Consider protocol version handling:
- Current version = 1
- Decide if version bump is needed
- Document any breaking changes

## Testing Requirements

### Unit Tests

1. Test proto serialization/deserialization with new fields
2. Verify generated code compiles correctly
3. Test any client code that uses the response

### Integration Tests

1. Test with mock gateway returning new response format
2. Verify indexer-agent can handle new response
3. Test error scenarios with new fields

### Manual Testing

1. Deploy updated indexer-service
2. Trigger payment collection from indexer-agent
3. Verify Receipt ID is returned
4. Confirm no TAP receipts are generated

## Configuration

No configuration changes required for indexer-service. The service continues to forward requests to the gateway.

## Rollback Plan

If issues arise:
1. Revert to previous proto definitions
2. Regenerate bindings
3. Deploy previous version
4. Ensure indexer-agent compatibility

## Dependencies

### External Dependencies
- Gateway must implement new response format
- Indexer-agent must handle Receipt IDs

### Build Dependencies
- Protocol buffer compiler (protoc)
- Prost build dependencies

## Implementation Sequence

This requires both schema and protocol changes:

1. Create database migration for dips_receipts table
2. Update protocol definitions in gateway.proto
3. Regenerate bindings and test compilation
4. Search and update any response handling code
5. Write and run tests
6. Integration testing with other components

## Success Criteria

- Protocol definitions updated with new fields
- Generated code compiles without errors
- No TAP receipt field in responses
- Receipt ID returned successfully
- Integration tests pass with indexer-agent

## Notes

- The indexer-service remains a thin pass-through layer
- No business logic changes required
- Main change is protocol definition only
- Ensure coordination with gateway and indexer-agent teams