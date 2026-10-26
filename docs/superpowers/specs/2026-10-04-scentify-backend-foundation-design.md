# Scentify Backend Foundation Design

**Date:** 2026-10-04

## Goal

Build the Firebase-independent backend/domain foundation for Scentify while the mobile wireframe is being prepared. The checkpoint must make the main commerce rules executable and testable without a network, database, or UI.

## Scope

This checkpoint includes strongly typed Dart models, repository contracts, in-memory adapters, validation, catalog filtering, cart operations, authoritative recalculation of current variant prices, inventory reservation, payment abstraction, immutable order snapshots, order status transitions, and customer/admin authorization guards.

Firebase Auth, Cloud Firestore, Firebase Storage, Cloud Functions, security rules, real payment credentials, and final UI styling are deferred to a later integration checkpoint. The in-memory implementation is a test adapter and is not presented as production security.

## Architecture

Feature folders own their domain models, repository interfaces, and use cases. Business logic depends on interfaces rather than Firebase or Flutter widgets. In-memory repositories provide deterministic tests now; Firebase repositories and server-side callable functions will implement the same boundaries later.

Money is represented as integer Philippine centavos. Cart prices are display data only. Checkout reads the current catalog variant before calculating totals and building immutable order-line snapshots. Inventory is validated for every line before any update is applied. The eventual Firestore implementation must replace the in-memory update with a Firestore transaction.

## Backend units

- `core`: money, exceptions, validation, and shared inventory request types.
- `auth`: typed user profile and role guard.
- `catalog`: brands, perfumes, variants, filters, and catalog repository.
- `cart`: customer cart models, repository, and current-catalog-aware cart service.
- `checkout`: addresses, delivery options, payment port, sandbox adapter, and checkout orchestration.
- `orders`: immutable snapshots, order repository, status state machine, and order service.
- `admin`: authorization-protected catalog management operations.

## Security boundary

The client will never be trusted for final price, stock, role, or payment status. This checkpoint exposes those rules as domain behavior. The Firebase phase will move the authoritative checkout and inventory operation behind Cloud Functions, use server timestamps, and enforce the same ownership and role checks in Firestore Security Rules.

## Error behavior

Invalid input throws typed `AppException` subclasses with stable error codes. Missing products or variants are not silently ignored. Empty carts cannot be checked out. Insufficient stock fails before any inventory changes. Invalid order transitions are rejected. Payment creation failure releases an in-memory reservation before surfacing the error.

## Testing strategy

Pure Dart tests cover money arithmetic, validation, catalog filtering, recommendation percentages, cart quantity limits, stock reservation, authoritative repricing, order snapshots, status transitions, payment failure cleanup, and admin authorization. The existing Flutter smoke test remains separate; Flutter/Firebase integration tests will be added after Firebase setup.

## Exclusions

No UI redesign, network API, Firebase package, payment secret, notification system, coupon engine, review system, or production deployment is included in this checkpoint.
