# DIPs Safe Payments Architecture

## Overview

This document describes the architecture for implementing Safe-based on-chain payments for DIPs (Distributed Indexing Payments) in The Graph Protocol, as specified in RFC-001. This implementation replaces TAP (Timeline Aggregation Protocol) for indexing fees due to impractical allocation requirements.

## Background

RFC-001 identifies critical issues with TAP for DIPs:
- **High Capital Requirements**: $50-$1000 allocations needed for $5-$100 monthly payments
- **Complex Allocation Management**: Variable allocation amounts create operational complexity
- **Capital Inefficiency**: Large amounts of stake must be kept free for DIPs
- **Missing Infrastructure**: TAP escrow management functionality not yet implemented

## Architecture Overview

### Core Design Principles

1. **Asynchronous Processing**: Non-blocking receipt ID system for immediate responses
2. **Safe Module Pattern**: Direct execution via `execTransactionFromModule` without multi-sig complexity
3. **State Machine**: Clear PENDING → SUBMITTED/FAILED status tracking
4. **Protocol Compliance**: 1% burn on all payments
5. **Clear Separation**: DIPs use Safe payments, query fees continue using TAP

### System Components

```
┌─────────────┐     RPC      ┌──────────────┐    Worker    ┌──────────────┐
│   Indexer   │ ──────────> │   Dipper     │ ──────────> │   Payment    │
│    Agent    │ <────────── │   Service    │              │   Handler    │
└─────────────┘   Receipt ID └──────────────┘              └──────────────┘
      │                             │                              │
      │ Poll Status                 │                              │
      ▼                             ▼                              ▼
┌─────────────┐              ┌──────────────┐              ┌──────────────┐
│  Receipt    │              │   Receipt    │              │ Safe Module  │
│  Storage    │              │   Registry   │              │   Client     │
└─────────────┘              └──────────────┘              └──────────────┘
                                    │                              │
                                    │                              ▼
                                    │                       ┌──────────────┐
                                    └──────────────────────>│  Blockchain  │
                                         Status Update      │ (GRT + Burn) │
                                                           └──────────────┘
```

## Payment Flow

### 1. Payment Collection (Indexer → Dipper)

The indexer initiates payment collection by reporting completed work:

```
Indexer sends collect_payment request:
- Agreement ID
- Work metrics (entity count, etc.)
- Indexer address
```

### 2. Receipt Creation (Dipper Service)

Dipper validates the work and creates a receipt:

1. Validate work report against agreement
2. Calculate payment amount including 1% burn
3. Create receipt record with PENDING status
4. Queue PayOnChain job for async processing
5. Return Receipt ID immediately

### 3. Asynchronous Payment Processing (Worker)

Worker processes payments in the background:

1. Retrieve receipt from registry
2. Verify PENDING status (skip if already processed)
3. Calculate exact burn amount (1% of total)
4. Submit payment via Safe Module:
   - Transfer GRT to indexer
   - Burn 1% to protocol address
5. Update receipt status:
   - SUBMITTED with transaction hash on success
   - FAILED with error message on failure

### 4. Status Polling (Indexer)

Indexers poll for payment status:

1. Request status using Receipt ID
2. Receive current status and details
3. For SUBMITTED status, get transaction hash
4. Verify payment on-chain if desired

## State Machine

```
                    ┌─────────┐
                    │ PENDING │──────┐
                    └────┬────┘      │
                         │           │
                    Submit│          │Fatal
                    Success│         │Error
                         │           │
                         ▼           ▼
                  ┌──────────┐  ┌────────┐
                  │SUBMITTED │  │ FAILED │
                  └──────────┘  └────────┘
```

**State Definitions:**
- **PENDING**: Receipt created, payment queued for processing
- **SUBMITTED**: Payment successfully submitted to blockchain with transaction hash
- **FAILED**: Payment failed due to error (gas, balance, revocation, etc.)

## Safe Module Implementation

### Configuration

The Safe Module pattern requires:
- Dipper EOA authorized as Safe Module
- Safe contract holding GRT tokens
- Module can execute transactions directly
- No multi-sig coordination required

### Transaction Execution

Payments are executed as batch operations using the Safe MultiSend contract:

1. **Batch Construction**: 
   - Create array of operations (GRT transfer + 1% burn)
   - Encode using MultiSend contract interface
   
2. **Execution Flow**:
   - Module calls `execTransactionFromModule` on the Safe
   - Safe delegatecalls to MultiSend contract
   - MultiSend executes both operations atomically:
     - Transfer GRT to indexer
     - Burn 1% to protocol address

3. **Benefits**:
   - Single transaction for multiple operations
   - Atomic execution (all or nothing)
   - Gas efficient batching
   - Standard Safe pattern

## Security Considerations

### Access Control
- Safe Module authorization can be revoked by Safe owners
- Module limited to specific operations (GRT transfers)
- No ability to modify Safe configuration

### Key Management
- Module signer key stored securely (environment variables)
- Regular key rotation capability
- No hardcoded keys in code

### Transaction Security
- Nonce management prevents replay attacks
- Gas price limits prevent excessive fees
- Amount validation ensures correct payments

## Database Schema

### Receipt Status Tracking

```sql
-- Enhanced receipts table
ALTER TABLE indexing_receipts 
ADD COLUMN payment_status TEXT DEFAULT 'PENDING',
ADD COLUMN transaction_hash TEXT,
ADD COLUMN payment_submitted_at TIMESTAMP,
ADD COLUMN payment_error TEXT,
ADD COLUMN retry_count INTEGER DEFAULT 0;

CREATE INDEX idx_receipts_payment_status ON indexing_receipts(payment_status);
```

## API Specifications

### gRPC Interface (Indexer Service → Dipper)

#### CollectPaymentRequest (Unchanged)
```protobuf
message CollectPaymentRequest {
  uint64 version = 1;
  bytes signed_collection = 2;  // ERC-712 signed work report
}
```

#### CollectPaymentResponse (Modified)
```protobuf
message CollectPaymentResponse {
  uint64 version = 1;
  string receipt_id = 2;        // Receipt ID for polling (replaces tap_receipt)
  string amount = 3;            // Total amount including burn
  string status = 4;            // Initial status: "PENDING"
}
```

### Dipper gRPC Interface Extension

#### GetReceiptById (New RPC method)
```protobuf
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

## Configuration

### Dipper Service
```yaml
safe_payment:
  safe_address: "0x..."          # Safe with module
  grt_token_address: "0x..."     # GRT token contract
  module_signer_key: "${KEY}"    # Module EOA key
  rpc_url: "https://..."         # Ethereum RPC
  burn_percentage: 1             # Protocol tax
  min_payment_amount_grt: "50"   # Minimum payment
```

### Indexer Agent
```yaml
payment_collection:
  dipper_endpoint: "http://dipper:8000"
```

## Components to Modify

### 1. Dipper Service (Gateway Side)
The dipper service requires the most significant changes as it manages the payment flow:

- **Receipt Registry**: Add payment status tracking (PENDING/SUBMITTED/FAILED)
- **Worker System**: Add PayOnChain message handler for async payment processing
- **Safe Module Client**: Implement GRT transfers with 1% burn via execTransactionFromModule
- **RPC Interface**: Return Receipt IDs instead of TAP receipts, add polling endpoint

### 2. Indexer Agent
The indexer agent needs updates to handle the new async payment pattern:

- **DipsCollector**: Replace TAP receipt storage with Receipt ID tracking
- **Polling Mechanism**: Add background task to poll for payment status
- **Database Models**: Update to store Receipt IDs and payment status
- **RPC Client**: Update to handle new response format and polling endpoint

### 3. Indexer Service
The indexer service requires minimal changes, primarily to the gRPC protocol definitions:

- **Protocol Update**: Modify `CollectPaymentResponse` in `gateway.proto` to return Receipt ID
- **Response Handling**: Update response structure to include status field
- **No Core Logic Changes**: The indexer service acts as a pass-through for DIPs

## Success Criteria

The implementation succeeds when:
- ✅ Non-blocking payment requests with Receipt IDs
- ✅ Asynchronous GRT transfers via Safe Module
- ✅ 1% protocol burn on all payments
- ✅ Clear state machine transitions
- ✅ Indexers can verify payments on-chain
- ✅ Complete separation from TAP for indexing fees