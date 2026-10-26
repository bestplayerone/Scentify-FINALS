# Supabase migration foundation

This is the Supabase cutover backend. The initial schema is applied remotely;
`20261026150000_supabase_checkout_cutover.sql` adds trusted online checkout,
reservations, invoices, and Xendit settlement.

## Before applying

1. Export Firestore and record collection counts, IDs, relationships, and invalid references.
2. Link the existing Supabase project and inspect its schema before applying migrations.
3. Configure Supabase Auth providers for email/password and Google sign-in.
4. Test anonymous, owner, other-customer, and admin access with Supabase JWTs.
5. Import a recoverable copy and compare IDs, totals, stock, addresses, wishlists, and reviews.

The migration expects JWT claims `admin: true` or `superadmin: true` for administrators and the normal Supabase `role: authenticated` claim for customer RPC calls. `ensure_customer_profile()` creates only a basic customer row from verified token claims; it does not provision admin roles.

`catalog_variants` is the client-facing view and omits `on_hand` and `reserved`. `admin_variants` exposes those fields only when the verified token carries an admin claim. Checkout, inventory adjustment, and review writes are restricted to SQL functions.

## Current limits

- The remote project has the cutover migration and Edge Functions deployed; run `scripts/deploy_supabase.sh` for future releases.
- Existing Firebase users are not automatically imported; they must authenticate through Supabase Auth after cutover.
- The customer runtime is wired to Supabase. Firebase-backed admin/review/address/notification modules remain legacy code until their equivalent Supabase modules are implemented.
