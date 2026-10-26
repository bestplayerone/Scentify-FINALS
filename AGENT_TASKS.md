# Scentify input-validation audit

- [x] Frontend, Cloud Functions, and Firestore Rules audit completed against `CONTEXT.md`; Builder implementation and Reviewer review completed for the approved tranche.
- [x] Backend: order/review/intent ownership and snapshot binding; quantity limit 100; UID-keyed address rate limits; exact enum validation; transactional webhook replay; strict cart row validation (exact fields, safe IDs, quantity bounds, duplicates); malformed cart writes fail without dropping existing rows.
- [x] Firestore Rules: order quote/payment binding, empty initial events, trusted cart marker allowlist, saved-address nonblank text/placeId/coordinate validation, primary-only address writes.
- [x] Frontend/repository: saved-address length caps and field errors; preserve existing saved-address notes without adding notes UI; registration and profile-edit name caps; safe provider-name fallback; wishlist ID validation, invalid legacy ID filtering, and 100-item cap.
- [x] Added/updated tests; latest Functions suite 40/40, `npm run check` and JS test-file syntax checks pass. Reviewer approved code and test coverage; Flutter tests and Rules assertions could not execute in this environment.
- [ ] Waiting on user decisions: same-ID quote refresh/PayMongo fetch race; late-payment handling and authoritative provider timestamp; exact same-day delivery areas; accepted Philippine phone formats; whether to redesign cart/wishlist writes/storage to enforce nested member validation in Rules.
- [ ] Deferred: align review text grapheme/code-unit limits; admin catalog schema enforcement; postal-code trim/reject contract; delivery-instructions UI. Nested cart validation is enforced by callable paths but direct Firestore list writes remain capable of malformed rows; wishlist per-ID validation is repository-side only.

Verification limitations: `flutter`, `dart`, `firebase`, and Java are unavailable. `npm run test:rules` reaches 42 setup failures because no Firestore emulator host/port is available. Firestore Rules runtime/compilation, real transaction concurrency, live App Check/FCM/PayMongo behavior remain unverified. The Functions package declares Node 22; current test runtime is Node 26.11.1. The mounted `.git` is unusable; current files are authoritative.

Constraints retained: no pricing, order-status, secret, or documented sandbox-inventory changes. Delivery-instructions UI remains deferred; stored address notes are preserved when editing and remain part of the existing data model.
