# Dipper DIPs Implementation Plan

## Overview

This plan details the changes required to the Dipper service to implement Safe-based GRT payments for DIPs, replacing the current TAP receipt system.

## Current State

The Dipper service currently:
- Generates TAP receipts for payment collection
- Returns receipts synchronously
- Has worker infrastructure for async tasks
- Stores receipts in PostgreSQL database

## Required Changes

### 1. Database Schema Updates

**Migration**: `dipper/source/migrations/20250130_payment_status.sql`

```sql
-- Add payment tracking to receipts
ALTER TABLE indexing_receipts 
ADD COLUMN payment_status TEXT DEFAULT 'PENDING' 
  CHECK (payment_status IN ('PENDING', 'SUBMITTED', 'FAILED')),
ADD COLUMN transaction_hash TEXT,
ADD COLUMN payment_submitted_at TIMESTAMP,
ADD COLUMN payment_error TEXT,
ADD COLUMN retry_count INTEGER DEFAULT 0;

-- Indexes for efficient queries
CREATE INDEX idx_receipts_payment_status ON indexing_receipts(payment_status);
CREATE INDEX idx_receipts_transaction_hash ON indexing_receipts(transaction_hash);
```

### 2. Registry Updates

**Location**: `dipper/source/bin/dipper-service/src/store/registry.rs`

Add payment status management:

```
New methods needed:
- update_receipt_payment_status(): Atomic status updates
- get_receipt_with_status(): Retrieve receipt with payment info
- get_receipts_by_status(): Query receipts by status
- increment_retry_count(): Track retry attempts
```

### 3. Worker System Integration

**Location**: `dipper/source/bin/dipper-service/src/worker/`

#### Add PayOnChain Message Type

```
WorkerMessage enum addition:
  PayOnChain {
    receipt_id: ReceiptId,
    amount: U256,
    recipient: Address,
    agreement_id: AgreementId,
  }
```

#### Implement Payment Handler

```
Payment handler logic:
1. Verify receipt is still PENDING
2. Calculate 1% burn amount
3. Submit payment via Safe Module
4. Update receipt status based on result
5. Handle retries for transient errors
```

### 4. Safe Module Client

**Location**: `dipper/source/bin/dipper-service/src/safe_client/`

Replace stub with working implementation:

```
Safe Module client needs:
- Initialize with Safe, GRT token, and MultiSend contracts
- Build batch transaction using MultiSend:
  1. Encode GRT transfer operation
  2. Encode 1% burn operation
  3. Pack operations into MultiSend call data
- Execute via execTransactionFromModule:
  - Target: Safe contract
  - Operation: delegatecall to MultiSend
  - Data: Encoded batch operations
- Handle nonce management for module transactions
- Return transaction hash after confirmation
```

### 5. gRPC Interface Updates

**Location**: `dipper/source` (proto files and service implementation)

#### Update CollectPayment

```
Changes:
1. Create receipt with PENDING status
2. Queue PayOnChain worker job
3. Return Receipt ID instead of TAP receipt in CollectPaymentResponse
4. Include initial status in response
```

#### Add GetReceiptById

```
New gRPC method:
- Add to proto definition
- Input: GetReceiptByIdRequest with receipt_id
- Query receipt with current status from database
- Return GetReceiptByIdResponse with status, transaction hash, error info
- Handle not found gracefully
```

### 6. Configuration

**Location**: `dipper/source/bin/dipper-service/src/config.rs`

```
Safe payment configuration:
- safe_address: Address of Safe contract
- grt_token_address: GRT token contract
- module_signer_key: Private key for module EOA
- rpc_url: Ethereum RPC endpoint
- burn_percentage: 1% protocol tax
- gas_settings: Limits and pricing
```

## Implementation Phases

### Phase 1: Database & Registry
1. Create and run migration
2. Update registry trait and implementation
3. Add status update methods
4. Test atomic operations

### Phase 2: Worker Integration
1. Add PayOnChain message type
2. Implement payment handler
3. Add retry logic
4. Integrate with registry

### Phase 3: Safe Client
1. Set up contract interfaces (Safe, GRT, MultiSend)
2. Implement batch transaction building:
   - Encode ERC20 transfer call for GRT to indexer
   - Encode ERC20 transfer call for 1% burn
   - Pack both into MultiSend.multiSend() call data
3. Add execTransactionFromModule calls:
   - Target: Safe contract
   - Value: 0 (no ETH)
   - Data: Delegatecall to MultiSend with packed operations
   - Operation: 1 (delegatecall)
4. Handle nonce and gas management

### Phase 4: RPC Updates
1. Modify collect_payment flow
2. Add polling endpoint
3. Remove TAP generation
4. Update response types

### Phase 5: Testing
1. Unit tests for all components
2. Integration tests
3. Local network testing
4. Testnet deployment

## Testing Strategy

### Unit Tests
```
Test coverage needed:
- Registry status updates
- Worker message handling
- Safe transaction building
- 1% burn calculations
- RPC response formatting
```

### Integration Tests
```
End-to-end scenarios:
- Receipt creation and status updates
- Payment execution flow
- Error handling and retries
- Concurrent payment processing
- Database consistency
```

### Local Testing
```
Validation steps:
1. Deploy with test Safe
2. Configure module authorization
3. Fund with test GRT
4. Process test payments
5. Verify on local chain
```

## Security Considerations

### Key Management
- Module key in environment variable
- No hardcoded keys
- Rotation capability

### Transaction Security
- Validate payment amounts
- Check Safe authorization
- Monitor gas prices
- Handle reverted transactions

### Access Control
- Verify indexer signatures
- Rate limit requests
- Validate work reports

## Monitoring

### Metrics
```
Key metrics:
- receipt_creation_rate
- payment_processing_time
- payment_success_rate
- retry_count_by_error
- gas_cost_per_payment
```

### Logging
```
Important events:
- Receipt creation
- Payment submission
- Status transitions
- Transaction hashes
- Error details
```

### Alerts
```
Alert conditions:
- High failure rate
- Stuck PENDING receipts
- Low Safe balance
- Module authorization issues
```

## Rollback Plan

1. Keep TAP code available
2. Feature flag for payment method
3. Database backups before migration
4. Manual payment capability
5. Clear rollback procedures

## Dependencies

### External
- Ethereum RPC provider
- Safe Module authorization
- GRT token in Safe
- Gas for transactions

### Internal
- Worker system operational
- Database available
- Registry functioning
- RPC server running

## Configuration Example

```toml
[safe_payment]
safe_address = "0x1234..."              # Safe contract with dipper EOA as module
grt_token_address = "0x5678..."         # GRT token contract
multisend_address = "0xA238..."         # Safe MultiSend contract
module_signer_key = "${SAFE_MODULE_KEY}" # Private key for module EOA
rpc_url = "https://sepolia.infura.io/v3/${KEY}"
burn_percentage = 1
burn_address = "0x0000000000000000000000000000000000000000"  # Or protocol burn address
min_payment_amount_grt = "50000000000000000000"  # 50 GRT

[safe_payment.gas]
max_price_gwei = 100
limit = 300000  # Higher limit for batch operations

[worker]
payment_retry_attempts = 3
payment_retry_delay_seconds = 60
```

## Success Criteria

- Receipt IDs returned immediately
- Payments process within 60 seconds
- State machine works correctly
- 1% burn executed properly
- No TAP receipts for DIPs
- Transactions verifiable on chain