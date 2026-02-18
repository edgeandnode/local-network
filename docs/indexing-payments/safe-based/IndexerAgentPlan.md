# Indexer Agent Implementation Plan

## Overview

This plan details the changes required to the Indexer Agent to support the new Safe-based Indexing Payments system. The implementation replaces TAP receipt collection with a Receipt ID polling mechanism.

## Development Branch

**Branch**: `dips-horizon-rebase`

This work will continue on top of the existing `dips-horizon-rebase` branch, which already contains indexing payments improvements.

## Current State

The Indexer Agent currently:
- Uses payment collector class to collect TAP receipts from the gateway
- Stores TAP receipts locally for later redemption
- Makes synchronous calls expecting immediate receipt data
- Has existing database models for tracking receipts

## Required Changes

### 1. Database Schema Updates

**Location**: `indexer-agent/source/packages/indexer-common/src/indexer-management/models/`

Create a new model for indexing payment receipts:

```
IndexingPaymentReceipt model:
- receiptId: string (primary key - unique identifier from dipper)
- agreementId: foreign key to indexing_agreements
- amount: bigint (payment amount in GRT wei)
- status: enum ['PENDING', 'SUBMITTED', 'FAILED']
- transactionHash: string (optional, populated when SUBMITTED)
- errorMessage: string (optional, populated when FAILED)
- createdAt: timestamp
- updatedAt: timestamp
```

**Note**: These schema changes will also need to be mirrored in the indexer-service migrations for Rust testing compatibility.

### 2. Update Payment Collector Class

**Location**: `indexer-agent/source/packages/indexer-common/src/indexing-fees/indexing-payments.ts`

#### Remove TAP Dependencies

- Remove all TAP receipt handling code
- Remove receipt signature verification
- Remove TAP-specific imports and types

#### Implement Receipt ID Collection

Update the payment collection flow:

```
async collectPayment(agreement):
  1. Calculate work metrics (entity count, etc.)
  2. Call dipper.collect_payment with work report
  3. Receive Receipt ID and initial status
  4. Store Receipt ID in database with PENDING status
  5. Return immediately (no polling here)
```

**Critical**: The collectPayment method does NOT start any polling. All polling is handled by a single background task that processes all pending receipts together.

### 3. Update gRPC Client

**Location**: `indexer-agent/source/packages/indexer-common/src/indexing-fees/gateway-indexing-service-client.ts`

#### Update gRPC Calls

Extend the Dipper gRPC client:

```
CollectPayment:
  Input: Same as before (work report)
  Output: {
    receiptId: string
    amount: string
    status: 'PENDING'
  }

GetReceiptById (new):
  Input: { receiptId: string }
  Output: {
    receiptId: string
    status: 'PENDING' | 'SUBMITTED' | 'FAILED'
    transactionHash?: string
    errorMessage?: string
    amount: string
  }
```

### 4. Update collectAllPayments Method

**Location**: `indexer-agent/source/packages/indexer-common/src/indexing-fees/indexing-payments.ts`

Extend the existing `collectAllPayments` method to also poll for pending receipts:

```
async collectAllPayments():
  // Existing logic - collect new payments
  1. Find outstanding agreements
  2. For each agreement: tryCollectPayment()
  
  // New logic - poll pending receipts
  3. Query database for ALL PENDING receipts
  4. For each receipt:
     - Call dipper.get_receipt_by_id
     - Update database with new status if changed
     - Log state transitions
```

**Benefits of this approach**:
- Reuses existing periodic task (runs every 60 seconds)
- Keeps all indexing payment logic in one place
- No need for separate background task
- Natural fit since both operations deal with payment lifecycle
- Simplifies the implementation

### 5. Monitoring and Logging

**Location**: Throughout the codebase

Add comprehensive logging:

```
Log Events:
- Payment request initiated
- Receipt ID received
- Each polling attempt
- Status transitions
- Transaction hash when SUBMITTED
- Error details when FAILED
- Polling attempts
```

Add metrics:

```
Metrics to track:
- payment_requests_total
- receipt_status_transitions
- polling_duration_seconds
- payment_success_rate
- payment_failure_reasons
```

## Implementation Steps

### Phase 1: Database and Models

1. Create migration for new receipt fields
2. Update IndexingPaymentReceipt model
3. Add status enum type
4. Test database changes

### Phase 2: RPC Client Updates

1. Add GetReceiptById method to RPC client
2. Update CollectPayment response handling
3. Remove TAP-specific response parsing
4. Add proper error handling

### Phase 3: Core Collection Logic

1. Refactor Payment Collector class
2. Remove all TAP receipt logic
3. Implement Receipt ID storage
4. Add polling mechanism
5. Handle all status transitions

### Phase 4: Extend collectAllPayments

1. Add receipt polling logic to existing method
2. Implement timeout handling for stale receipts
3. Add batch status checking
4. Ensure fault tolerance

### Phase 5: Testing and Validation

1. Unit tests for new collection flow
2. Integration tests with mock dipper
3. Test status polling mechanism
4. Test error scenarios
5. Performance testing

## Testing Plan

### Unit Tests

```
Test Cases:
- Receipt ID storage and retrieval
- Status update logic
- Polling state tracking
- Error propagation
```

### Integration Tests

```
Test Scenarios:
- Full payment flow with mock dipper
- Status transitions (PENDING → SUBMITTED)
- Failure scenarios (PENDING → FAILED)
- Network interruption handling
- Concurrent receipt polling
```

### Manual Testing

```
Validation Steps:
1. Deploy to local-network
2. Create test indexing agreement
3. Trigger payment collection
4. Monitor Receipt ID creation
5. Verify polling behavior
6. Check final transaction on chain
```

## Configuration Changes

### Environment Variables

```bash
# Dipper endpoint
DIPPER_ENDPOINT=http://dipper:8000
```

### Command Line Arguments

```bash
indexer-agent start \
  --dipper-endpoint http://dipper:8000
```

## Error Handling

### Transient Errors
- Network timeouts: Retry polling
- Dipper unavailable: Exponential backoff
- Database errors: Log and retry

### Fatal Errors
- Invalid Receipt ID: Log error
- Authentication errors: Alert operator

## Migration Considerations

### Backward Compatibility
- Keep TAP code for query fees
- Add feature flag for new payment system
- Support gradual rollout

### Data Migration
- No migration needed for existing TAP receipts
- New receipts use Receipt ID system
- Clear separation in database

## Success Metrics

### Functional Metrics
- All payments create Receipt IDs
- Status polling works reliably
- Transactions appear on chain
- No TAP receipts for indexing fees

### Performance Metrics
- Receipt creation < 1 second
- Status updates within 30 seconds
- Polling doesn't impact performance
- Database queries remain efficient

## Rollback Plan

If issues arise:
1. Disable new payment flow via feature flag
2. Revert to TAP receipt collection
3. Investigate and fix issues
4. Re-deploy with fixes

## Dependencies

### External Dependencies
- Dipper service with new RPC methods
- Safe Module configuration on chain
- GRT tokens in Safe

### Internal Dependencies
- Database schema changes
- RPC client updates
- Background task system

## Implementation Order

1. Database updates
2. RPC client changes
3. Core logic implementation
4. Background tasks
5. Testing and validation
6. Integration and deployment