# Scentify

Supabase is the active customer runtime. Flutter uses Supabase Auth/Postgres and Edge Functions; service-role, Xendit, and webhook secrets remain backend-only.

## Feature status

### Customer app

- Catalog browsing, search/filtering, product details, favorites, and cart flows are connected to the app repositories. Firebase-backed catalog/cart behavior requires the configured Firebase project and deployed Functions/rules.
- Checkout obtains a server-reviewed quote before creating a Firestore order. The default payment gateway is the sandbox; PayMongo Hosted Checkout is selected only for Firestore-backed orders when `SCENTIFY_PAYMONGO_ENABLED=true`.
- Signed-in customers can save one primary delivery address at `users/{uid}/addresses/primary`. Checkout uses Firestore storage; demo/test sessions use in-memory storage. Manual address entry remains available.
- Address suggestions and place details call App Check-protected Functions and read the private `addressSuggestions` collection. **This is not a live geocoder:** suggestions remain empty until trusted address data is loaded. The repository currently has no importer or seed dataset. Each document needs a lowercase `searchKey`, `primaryText`, `secondaryText`, `addressLine1`, `barangay`, `city`, `province`, four-digit `postalCode`, `latitude`, and `longitude`; the document ID is the `placeId`. Firestore rules deny client reads and writes to this collection.
- Product reviews are submitted through the trusted `submitProductRating` Function. The server checks that the signed-in user owns a delivered order containing the rated variant, prevents duplicate ratings, and updates the product aggregate. Product pages display verified reviews; customers can submit one from a delivered purchase.
- Order push notifications use FCM on supported devices. Delivery depends on notification permission, valid device tokens, and the deployed order-status trigger. The admin Notifications module is informational; it does not compose or manually send campaigns.

### Admin app

- Order/payment approval and fulfillment status transitions are the active management workflow and remain protected by server-side role checks.
- Products and inventory are read-only previews. Product editing/publishing and inventory adjustments are not exposed in the admin UI.
- Customers is an order-account count, not a customer directory. Search, export, and profile-management tools are unavailable.
- Settings shows the current account, payment mode, and loaded product count; it cannot change store configuration.
- Superadmin access shows the account role only. Admin staff management is unavailable.

## Supabase and Xendit setup

The active project is `jnukqrpkyqwoatesuelp`. Deploy Supabase migrations and Edge Functions with `./scripts/deploy_supabase.sh`. Register `https://jnukqrpkyqwoatesuelp.supabase.co/functions/v1/xendit-webhook` in Xendit Test Mode for `payment_session.completed` and `payment_session.expired`. Keep provider and service-role secrets in Edge Function secrets only.

Before testing against a Firebase project:

1. Confirm `lib/firebase_options.dart` and the native Firebase configuration belong to the intended project.
2. Configure the appropriate App Check providers for the target platforms. The callable Functions used by checkout, ratings, and address suggestions enforce App Check.
3. Deploy the current Firestore rules and Functions:

   ```bash
   firebase deploy --only firestore:rules,functions
   ```

   Cloud Functions deployment requires the Firebase project to be on the Blaze (pay-as-you-go) plan. Firestore rules can be deployed separately.

4. Load trusted address suggestion documents into `addressSuggestions` if autocomplete is needed. Without that dataset, use manual address entry.
5. For PayMongo test checkout, configure the backend environment from `functions/.env.example`, deploy Functions, and register the deployed webhook for `checkout_session.payment.paid`. Never put provider secrets in Flutter code or public configuration.
6. For Xendit test checkout, provision `XENDIT_SECRET_KEY` and `XENDIT_WEBHOOK_TOKEN` in Firebase Secret Manager, deploy the `asia-southeast1` Functions to **`scentify-b97e5`**, register the deployed `xenditWebhook` URL for `payment_session.completed` and `payment_session.expired`, and build with `--dart-define=SCENTIFY_XENDIT_ENABLED=true`:
   ```bash
   npx firebase-tools deploy --only functions --project scentify-b97e5
   # callable: https://asia-southeast1-scentify-b97e5.cloudfunctions.net/createXenditCheckoutSession
   # webhook:  https://asia-southeast1-scentify-b97e5.cloudfunctions.net/xenditWebhook
   ```
   The active checkout/order backend is Firebase/Firestore; Supabase is currently only the staged catalog/schema migration and does not contain the payment function.
7. For push notifications, configure FCM for the target platform and grant notification permission on the device.

Google sign-in also requires the Firebase Auth Google provider and platform OAuth configuration. The app's Firebase flows are intended for Android and Chrome; iOS and Linux have not been verified.

## Verification

From the project root:

```bash
flutter analyze
flutter test
firebase emulators:exec --only firestore --project demo-scentify-rules "npm --prefix functions run test:rules"
(cd functions && npm run check)
```

The automated Flutter tests exercise in-memory repositories and widget flows. They do not prove that live Firebase rules, deployed Functions, address data, App Check, FCM delivery, or PayMongo credentials/webhooks are configured correctly. No live payment or production deployment is performed by these checks.

# Scentify-FINALS
