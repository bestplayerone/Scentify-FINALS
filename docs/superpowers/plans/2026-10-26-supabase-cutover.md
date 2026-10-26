# Scentify Supabase Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Firebase as Scentify's active backend with Supabase Auth, Postgres/RLS/RPC, and Edge Functions for the full checkout/payment/invoice flow.

**Architecture:** Flutter uses `supabase_flutter` for auth and data. Trusted checkout, COD, online payment order creation, invoice snapshots, reservations, and settlement are Postgres functions. Supabase Edge Functions own Xendit API calls and webhook verification.

**Tech Stack:** Flutter/Dart, Supabase Flutter, PostgreSQL migrations, Deno TypeScript Edge Functions, Xendit Payment Sessions API.

**Spec:** `docs/superpowers/specs/2026-10-26-supabase-cutover-design.md`

## Global Constraints

- Xendit secrets exist only in Supabase Edge Function secrets.
- Flutter never supplies the authoritative amount, price, stock, or payment status.
- COD and online payments use separate server functions.
- Every order/payment/webhook path is idempotent.
- Firebase remains untouched until the Supabase path is verified.

## Review Focus

- Concurrent checkout for the same cart line must serialize on the variant row and reserve stock once — Task 2 RPC concurrency test.
- Replayed or forged webhook must not mark an order paid or change inventory — Task 3 webhook tests.
- Client-supplied amount/price must be ignored — Task 2 quote/order tests.
- Expired/canceled/pending payment must not become paid — Task 3 status tests.
- Authenticated user must not read or mutate another user's data — Task 1 RLS tests.

### Task 1: Supabase schema and security foundation

**Files:**
- Create: `supabase/migrations/20261026150000_supabase_checkout_cutover.sql`
- Create: `supabase/tests/checkout.sql`
- Modify: `supabase/README.md`

**Interfaces:**
- Produces RPCs `public.create_checkout_order`, `public.create_cod_order`, `public.get_checkout_order`, `public.release_expired_payment`, and tables `payment_sessions`, `inventory_reservations`, `invoice_snapshots`.

- [ ] Add payment/reservation/invoice columns and tables with unique order/session/event keys.
- [ ] Add security-definer RPCs that recalculate cart prices, delivery fees, and totals under row locks.
- [ ] Add webhook settlement RPC that verifies provider, session, amount, status, and deduplicates event IDs.
- [ ] Add SQL tests for ownership, amount tampering, stock locking, idempotent COD, and webhook replay.
- [ ] Run SQL lint/parse checks and document `supabase db push` plus secret setup.

### Task 2: Supabase Edge Functions

**Files:**
- Create: `supabase/functions/create-xendit-session/index.ts`
- Create: `supabase/functions/xendit-webhook/index.ts`
- Create: `supabase/functions/_shared/http.ts`
- Create: `supabase/functions/_shared/xendit.ts`
- Create: `supabase/functions/test/xendit_test.ts`

**Interfaces:**
- `POST /functions/v1/create-xendit-session` accepts order ID/payment method and returns `{reference, checkoutUrl}`.
- `POST /functions/v1/xendit-webhook` accepts Xendit session events and returns 2xx only after safe processing.

- [ ] Validate Supabase JWT on session creation and call the trusted order RPC.
- [ ] Call Xendit `/sessions` with `PAYMENT_LINK`, `PHP`, `PH`, `GCASH`, and disabled saved payment method.
- [ ] Persist provider session and return only the hosted checkout URL.
- [ ] Verify callback token and route completed/expired events to idempotent RPCs.
- [ ] Add Deno tests for request validation, provider errors, webhook replay, and status transitions.

### Task 3: Flutter Supabase adapters

**Files:**
- Create: `lib/core/supabase/supabase_auth_repository.dart`
- Create: `lib/core/supabase/supabase_checkout_api.dart`
- Create: `lib/features/catalog/data/supabase_catalog_repository.dart` (replace stub path if needed)
- Create/modify: Supabase cart, wishlist, address, order repositories
- Modify: `lib/main.dart`, checkout wiring, auth wiring, and error messages
- Test: `test/backend/supabase_checkout_api_test.dart`

**Interfaces:**
- Auth uses `Supabase.instance.client.auth`.
- Checkout API creates quotes/orders through RPC and invokes the Xendit Edge Function.

- [ ] Replace Firebase auth restoration/sign-in/sign-up with Supabase Auth.
- [ ] Replace catalog/cart/address/order reads and writes with Supabase repositories.
- [ ] Launch returned Xendit hosted checkout URL and keep order pending until realtime/poll refresh sees paid.
- [ ] Preserve COD as a separate RPC path.
- [ ] Add client tests for meaningful errors and no client-side payment-status mutation.

### Task 4: Invoice and cutover verification

**Files:**
- Modify: `lib/main.dart` invoice/tracking surfaces
- Modify: `README.md`, `supabase/README.md`
- Create: `scripts/verify_supabase_cutover.sh`

- [ ] Show invoice number/date/items/totals/payment status from the immutable Supabase order snapshot.
- [ ] Hide paid/confirmed invoice state for pending, canceled, expired, or failed payments.
- [ ] Run local Supabase tests, Dart tests, Edge Function tests, and a Test Mode Xendit session.
- [ ] Verify deployed project ID, Edge Function status, webhook URL, auth, RLS, order persistence, and inventory transitions.
- [ ] Remove Firebase runtime wiring only after all checks pass; leave migration notes for existing Firebase users.
