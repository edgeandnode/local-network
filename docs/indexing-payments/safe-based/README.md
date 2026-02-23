# Indexing Payments Documentation

This folder contains all documentation for the Indexing Payments Safe-based payment system implementation.

This approach is obsolete.

## Overview

The Indexing Payments Safe payment system replaces TAP (Timeline Aggregation Protocol) for indexing fee payments, using on-chain GRT transfers via Safe Module pattern with asynchronous processing.

## Documentation Structure

### Architecture

- [`Architecture.md`](./Architecture.md) - System architecture, design principles, and component interactions

### Implementation Plans

- [`IndexerAgentPlan.md`](./IndexerAgentPlan.md) - Changes needed for the Indexer Agent to handle Receipt IDs and polling
- [`DipperServicePlan.md`](./DipperServicePlan.md) - Core payment processing implementation in the Dipper service
- [`IndexerServicePlan.md`](./IndexerServicePlan.md) - Minimal protocol buffer updates for the Indexer Service

## Quick Links

### For Indexer Agent Development

Start with the [Indexer Agent Plan](./IndexerAgentPlan.md) which covers:

- Receipt ID tracking
- Status polling mechanism
- Database schema updates

### For Dipper Development

See the [Dipper Plan](./DipperServicePlan.md) for:

- Safe Module client implementation
- Worker-based payment processing
- Receipt status management

### For Understanding the System

Read the [Architecture Document](./Architecture.md) to understand:

- Payment flow and state machine
- Security considerations
- API specifications

## Key Concepts

- **Receipt ID**: Replaces TAP receipts, enables async processing
- **State Machine**: PENDING → SUBMITTED/FAILED
- **Safe Module**: Direct execution pattern for GRT transfers
- **1% Protocol Burn**: Automatic burn on all payments
