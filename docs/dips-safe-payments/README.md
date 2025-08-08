# DIPs Safe Payments Documentation

This folder contains all documentation for the DIPs (Distributed Indexing Payments) Safe-based payment system implementation.

## Overview

The DIPs Safe payment system replaces TAP (Timeline Aggregation Protocol) for indexing fee payments, using on-chain GRT transfers via Safe Module pattern with asynchronous processing.

## Documentation Structure

### Architecture
- [`architecture.md`](./architecture.md) - System architecture, design principles, and component interactions

### Implementation Plans
- [`indexer-agent-plan.md`](./indexer-agent-plan.md) - Changes needed for the Indexer Agent to handle Receipt IDs and polling
- [`dipper-plan.md`](./dipper-plan.md) - Core payment processing implementation in the Dipper service
- [`indexer-service-plan.md`](./indexer-service-plan.md) - Minimal protocol buffer updates for the Indexer Service

## Quick Links

### For Indexer Agent Development
Start with the [Indexer Agent Plan](./indexer-agent-plan.md) which covers:
- Receipt ID tracking
- Status polling mechanism
- Database schema updates

### For Dipper Development
See the [Dipper Plan](./dipper-plan.md) for:
- Safe Module client implementation
- Worker-based payment processing
- Receipt status management

### For Understanding the System
Read the [Architecture Document](./architecture.md) to understand:
- Payment flow and state machine
- Security considerations
- API specifications

## Key Concepts

- **Receipt ID**: Replaces TAP receipts, enables async processing
- **State Machine**: PENDING → SUBMITTED/FAILED
- **Safe Module**: Direct execution pattern for GRT transfers
- **1% Protocol Burn**: Automatic burn on all payments