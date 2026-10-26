# Scentify Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Firebase-independent, testable Dart backend/domain core for Scentify commerce behavior.

**Architecture:** Feature-owned domain models and use cases depend on repository and payment interfaces. In-memory adapters make the rules executable now; a later Firebase/Cloud Functions adapter will provide server authority without changing the domain contracts.

**Tech Stack:** Dart 3.13, Flutter project, `flutter_test`/Dart test tooling, no new runtime dependencies in this checkpoint.

## Global Constraints

- Keep Firebase, payment credentials, network calls, and final UI out of this checkpoint.
- Use integer Philippine centavos for money.
- Cart prices are never authoritative; checkout rereads current catalog variants.
- Inventory updates must validate every line before applying changes.
- Order items must snapshot names, variants, quantities, and prices at checkout.
- Order transitions must follow `pending_payment → confirmed → processing → packed → shipped → delivered`.
- Production server authority remains a Firebase Cloud Functions and Firestore transaction concern for the later integration phase.

---

### Task 1: Shared primitives and typed catalog models

**Files:**
- Create: `lib/core/errors/app_exception.dart`
- Create: `lib/core/models/money.dart`
- Create: `lib/features/auth/domain/models/user_profile.dart`
- Create: `lib/features/catalog/domain/models/brand.dart`
- Create: `lib/features/catalog/domain/models/perfume.dart`
- Test: `test/backend/core_primitives_test.dart`

**Interfaces:**
- Produces `Money`, typed exceptions, `UserProfile`, `Brand`, `Perfume`, `PerfumeVariant`, and catalog enums for later services.

- [x] **Step 1: Write failing tests** for integer-centavo arithmetic, rejected negative money, immutable catalog variant copies, and customer/admin role checks.
- [x] **Step 2: Run `dart test test/backend/core_primitives_test.dart`** and confirm it fails because the backend types do not exist.
- [x] **Step 3: Implement the smallest immutable models** with `copyWith`, enum wire values, and stable exception codes.
- [x] **Step 4: Run the focused test again** and confirm it passes.

### Task 2: Catalog repository and filters

**Files:**
- Create: `lib/features/catalog/domain/repositories/catalog_repository.dart`
- Create: `lib/features/catalog/data/in_memory_catalog_repository.dart`
- Test: `test/backend/catalog_repository_test.dart`

**Interfaces:**
- `CatalogRepository.list({CatalogFilter filter})`, `findById`, `save`, and `delete`.

- [x] **Step 1: Write failing tests** for search/filter combinations and catalog stream updates.
- [x] **Step 2: Run the focused test** and confirm the expected missing-type failure.
- [x] **Step 3: Implement filter evaluation and deterministic catalog snapshots.**
- [x] **Step 4: Run the focused test** and confirm ranking, limits, and percentage values pass.

### Task 3: Cart and inventory behavior

**Files:**
- Create: `lib/features/cart/domain/models/cart.dart`
- Create: `lib/features/cart/domain/repositories/cart_repository.dart`
- Create: `lib/features/cart/data/in_memory_cart_repository.dart`
- Create: `lib/features/cart/domain/services/cart_service.dart`
- Create: `lib/core/inventory/inventory_service.dart`
- Test: `test/backend/cart_and_inventory_test.dart`

**Interfaces:**
- `CartService.addItem`, `setQuantity`, `removeItem`, `getCart`, and `clear`.
- `InventoryService.reserve` and `release`.

- [x] **Step 1: Write failing tests** for variant lookup, quantity limits, current stock checks, and no-negative-stock reservations.
- [x] **Step 2: Run the focused test** and verify it fails for missing services.
- [x] **Step 3: Implement immutable cart changes and prevalidated in-memory inventory updates.**
- [x] **Step 4: Run the focused test** and confirm all stock and quantity cases pass.

### Task 4: Checkout, payment abstraction, and immutable orders

**Files:**
- Create: `lib/features/checkout/domain/models/shipping_address.dart`
- Create: `lib/features/checkout/domain/models/delivery_option.dart`
- Create: `lib/features/checkout/domain/services/payment_gateway.dart`
- Create: `lib/features/checkout/data/sandbox_payment_gateway.dart`
- Create: `lib/features/orders/domain/models/order.dart`
- Create: `lib/features/orders/domain/repositories/order_repository.dart`
- Create: `lib/features/orders/data/in_memory_order_repository.dart`
- Create: `lib/features/checkout/domain/services/checkout_service.dart`
- Test: `test/backend/checkout_and_orders_test.dart`

**Interfaces:**
- `PaymentGateway.createPayment(PaymentRequest)` returns a provider-neutral `PaymentSession`.
- `CheckoutService.placeOrder` rereads current catalog prices, reserves stock, creates a pending-payment order, and stores a payment reference.
- `OrderRepository.save`, `findById`, and `forUser`.

- [x] **Step 1: Write failing tests** for required Philippine address fields, repricing after the cart was created, immutable order snapshots, and payment failure inventory cleanup.
- [x] **Step 2: Run the focused test** and confirm it fails before implementation.
- [x] **Step 3: Implement checkout orchestration** with injected clock and ID generator for deterministic tests.
- [x] **Step 4: Run the focused test** and confirm authoritative totals, snapshots, and cleanup pass.

### Task 5: Order transitions and admin operations

**Files:**
- Create: `lib/features/orders/domain/services/order_status_machine.dart`
- Create: `lib/features/orders/domain/services/order_service.dart`
- Create: `lib/features/admin/domain/services/admin_catalog_service.dart`
- Test: `test/backend/order_and_admin_test.dart`

**Interfaces:**
- `OrderStatusMachine.canTransition` and `assertTransition`.
- `OrderService.transitionStatus`.
- `AdminCatalogService.saveProduct` and `deleteProduct` guarded by `UserProfile.isAdmin`.

- [x] **Step 1: Write failing tests** for the exact happy-path status sequence, rejected skips/backwards transitions, and denied customer admin actions.
- [x] **Step 2: Run the focused test** and verify the intended failure.
- [x] **Step 3: Implement the state machine, event timestamps, and role guard.**
- [x] **Step 4: Run all backend tests** with `dart test test/backend`.

### Task 6: Documentation and static verification

**Files:**
- Modify: `README.md`
- Modify: `pubspec.yaml` only if test tooling requires a direct dependency

- [x] **Step 1: Document the Firebase-free backend boundary and test command.**
- [x] **Step 2: Run `dart analyze` and `dart test test/backend`.**
- [x] **Step 3: Run the existing Flutter smoke test separately if the local Flutter SDK is writable; otherwise report the SDK cache lock limitation explicitly.**
- [x] **Step 4: Review the changed file set and list the Firebase integration work remaining.**

The checkout has an empty `.git` directory rather than usable Git metadata, so commits are not part of this execution unless repository metadata is restored later.
