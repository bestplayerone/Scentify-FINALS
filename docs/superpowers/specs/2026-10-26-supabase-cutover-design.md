# Scentify Supabase Cutover Design

## Intent

Move Scentify's active backend from Firebase/Firestore/Cloud Functions to the
existing Supabase project `jnukqrpkyqwoatesuelp`, with one authoritative source
for authentication, catalog, cart, checkout, orders, inventory, invoices, and
Xendit payment state.

## Goals

- Supabase Auth replaces Firebase Auth for email/password and Google sign-in.
- Postgres/RLS/RPC owns catalog reads, cart writes, trusted checkout quotes,
  COD orders, online-payment orders, reservations, and inventory.
- Supabase Edge Functions create Xendit Payment Sessions server-side and
  process authenticated Xendit webhooks idempotently.
- The Flutter app uses Supabase APIs only for the migrated flows.
- Invoice data is derived from the immutable order snapshot and is shown only
  for confirmed COD orders or orders paid by verified webhook.

## Non-goals

- Preserve existing Firebase Auth user IDs or passwords; users must sign in or
  register through Supabase Auth after the cutover.
- Keep Firebase as a fallback source of truth.
- Migrate FCM notifications in this pass; order status remains visible through
  Supabase reads and can be notified later with Supabase-compatible delivery.

## Approaches

1. Keep Firebase and add a Supabase payment function. Rejected: orders and
   inventory would remain split across systems, which cannot safely support
   payment webhooks.
2. Replace only payment and leave Firebase auth/data. Rejected: the requested
   Firebase removal is not achieved and the deployment/billing failure remains.
3. Full Supabase cutover with Postgres RPC/RLS and Edge Functions. Chosen: one
   source of truth, no Firebase deployment dependency, and the existing
   migration already supplies most tables and security foundations.

## Architecture

Flutter authenticates with Supabase Auth and calls Postgres through the
Supabase client. Trust-boundary writes go through `security definer` RPCs that
recalculate prices from published variants and lock inventory rows. Online
checkout first creates a pending order and reservation in one transaction,
then an Edge Function creates the Xendit Payment Session. Xendit callbacks
reach a public Edge Function protected by `x-callback-token`; only a verified,
amount-matching completion commits the reservation and marks the order paid.

## Constraints

- Xendit secret and webhook token remain Supabase Edge Function secrets.
- Payment amount is never accepted from Flutter as authoritative data.
- COD bypasses Xendit and is confirmed by its own RPC.
- Payment webhooks are idempotent and cannot deduct stock twice.
- Existing Firebase files remain only until all migrated Flutter callers are
  removed and the Supabase flow is verified.
