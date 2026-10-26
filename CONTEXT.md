# Scentify — Context Transfer

> **Purpose:** This file is the handoff brief for any AI agent (Claude, Codex, or a human engineer) working on Scentify. Read it fully before inspecting or changing code. It describes what the app is, how it is wired, what each module owns, and which invariants must not be broken.

---

## 0. Agent brief (copy-paste prompt)

```text
You are working on Scentify, a Flutter + Firebase perfume-commerce app for the
Philippines with a customer storefront and a separate admin workspace.

Before changing code:
1. Read CONTEXT.md at the repository root completely.
2. Inspect the files you intend to change and every caller of the functions you touch.
3. Preserve these invariants:
   - Money is integer Philippine centavos, never a floating-point peso value.
   - Checkout must obtain a server-reviewed quote before creating a Firestore order.
   - Orders store immutable item/address/delivery snapshots and move forward only
     through the fixed status machine.
   - Admin authority is checked in the domain layer AND in Firestore rules AND
     through Firebase custom claims where available.
   - No payment secret, service-account credential, or admin-only key may enter
     Flutter code.
4. Match the existing feature-first structure under lib/core and lib/features.
   Do not move domain logic into widgets or rewrite the router.
5. When a data contract changes, update the Dart model, FirestoreCodecs, seed or
   fixtures, Firestore rules, Cloud Functions, and tests together.
6. Verify with: flutter analyze && flutter test
   Backend rules: firebase emulators:exec --only firestore \
     --project demo-scentify-rules "npm --prefix functions run test:rules"
   Functions syntax: (cd functions && npm run check)
7. Report what changed, what was verified, and any remaining limitation.

If this document and the code disagree, the code wins. Fix the document or report
the drift instead of silently assuming.
```

---

## 1. Product summary

Scentify is a mobile-first perfume storefront for customers in the Philippines, with an embedded admin workspace.

- **Customer job:** discover perfumes by brand, gender, fragrance family, notes, occasion, and vibe; save favorites; add variants to a cart; check out with a Philippine delivery address; pay via GCash, Maya, or card; track orders; leave verified reviews.
- **Admin job:** monitor sales/fulfillment, approve payments, advance order statuses, and inspect catalog/inventory/customer counts. Most non-order admin modules are read-only in the current build.
- **Locale assumptions:** Philippine addresses (barangay, city, province, four-digit postal code), Philippine peso pricing in centavos, Metro Manila delivery options.
- **Visual identity:** warm ivory/paper surfaces, espresso ink, restrained champagne/brass accents, Montserrat utility type, DM Serif Display headings, editorial product photography.

### Workspaces

| Workspace | Entry | Navigation |
| --- | --- | --- |
| Customer | Splash → onboarding → auth → home | Five tabs: Home, Top Picks, Shop, Wishlist, Profile |
| Admin | After authentication, if role is `admin` or `superadmin` | Separate dashboard; not a customer tab |

---

## 2. Current capability status

Treat this as the honest state of the repository, not a roadmap.

### Working and wired

- Email/password and Google authentication with Firebase Auth.
- Live Firestore catalog stream for published perfumes.
- Client-side catalog search, filters, and sorting.
- Product detail, variant selection, quick view, wishlist.
- Cart with selection, quantity, and removal; persisted per user in Firestore.
- Checkout address capture, one saved primary address, delivery choice, payment choice.
- Server-reviewed checkout quote via `getOrderReview`.
- Sandbox payment by default; PayMongo Hosted Checkout when explicitly enabled.
- Order creation, customer order history, tracking timeline, admin status transitions.
- Verified product reviews through `submitProductRating`.
- FCM order notifications on supported devices.
- Firestore Security Rules with schema and ownership validation.
- Admin dashboard for order/payment approval and fulfillment progression.

### Read-only or intentionally limited

- Admin **Products**: preview only; no edit/publish UI.
- Admin **Inventory**: stock counts only; no adjustments.
- Admin **Customers**: count of accounts with orders; no directory/PII.
- Admin **Settings**: displays account, role, payment mode, and loaded product count.
- Admin **Notifications**: informational; no campaign composer.
- Admin **Admin access**: superadmin-only role display; no staff management.
- One saved delivery address per user (`users/{uid}/addresses/primary`).
- Address autocomplete is **not a live geocoder**; it reads a curated `addressSuggestions` collection that has no importer or seed in this repo.
- No coupons, tax engine, refunds, cancellations, or multi-address support.

### Platform status

- Firebase is initialized only on **web** and **Android**.
- iOS, Linux, macOS, and Windows run with in-memory/demo repositories and do not initialize Firebase auth in the current bootstrap.
- README states Android and Chrome are the intended verified targets; iOS/Linux are unverified.
- Automated tests use in-memory repositories and do not prove live Firebase, App Check, FCM, address data, or PayMongo configuration.

---

## 3. Tech stack

| Layer | Technology |
| --- | --- |
| App | Flutter / Dart, SDK `^3.13.4` |
| State | `StatefulWidget` + `setState`; no Riverpod/Bloc/Provider |
| Navigation | Root page enum + manual history stack; no named routes or GoRouter |
| Auth | `firebase_auth`, Google Sign-In |
| Database | Cloud Firestore (`cloud_firestore`) |
| Backend | Firebase Cloud Functions v2, Node.js 22, region `asia-southeast1` |
| Payments | Sandbox gateway (default), PayMongo Hosted Checkout (opt-in) |
| Push | `firebase_messaging` + `flutter_local_notifications` |
| Security | Firebase App Check, custom claims, Firestore rules |
| Local storage | `shared_preferences` for onboarding only; Firestore persistence on mobile |
| External links | `url_launcher` |
| Tests | `flutter_test`, pure Dart `test`, Node test runner + `@firebase/rules-unit-testing` |

### Key dependencies (`pubspec.yaml`)

`cloud_firestore`, `firebase_auth`, `firebase_core`, `google_sign_in`, `firebase_messaging`, `firebase_app_check`, `flutter_local_notifications`, `cloud_functions`, `shared_preferences`, `url_launcher`.

### Project identifiers

- Firebase project: `scentify-b97e5` (`.firebaserc`, `firebase.json`, `lib/firebase_options.dart`)
- Functions region: `asia-southeast1` (`scentifyFunctionsRegion`)
- Android config: `android/app/google-services.json`
- Native/web Firebase config exists; Android relies on the native config file, web uses generated options.

---

## 4. Repository map

```text
scentify/
├── CONTEXT.md                     # this handoff document
├── README.md                      # user-facing setup + honest feature status
├── pubspec.yaml                   # Flutter dependencies, fonts, assets
├── firebase.json                  # Functions + Firestore + Flutter config
├── firestore.rules                # all client security rules
├── lib/
│   ├── main.dart                  # bootstrap, app shell, router, all customer/admin UI (≈14.8k lines)
│   ├── firebase_options.dart      # web Firebase config
│   ├── ui/
│   │   ├── scentify_design_system.dart   # colors, type, spacing, theme, reusable widgets
│   │   └── scentify_breakpoints.dart     # responsive width classes and catalog grid math
│   ├── core/
│   │   ├── addresses/             # address autocomplete callable client
│   │   ├── cache/                 # generic TTL cache (currently unused)
│   │   ├── cart/                  # server add-to-cart callable client (currently unused)
│   │   ├── errors/                # sealed AppException hierarchy
│   │   ├── firebase/              # Firestore codecs + persistence settings
│   │   ├── inventory/             # client inventory port + no-op for Firestore
│   │   ├── models/                # Money value object
│   │   ├── network/               # client rate limiter, debouncer (utilities)
│   │   ├── notifications/         # FCM + local notification service
│   │   ├── orders/                # order review + my-purchases callable clients
│   │   ├── payments/              # payment enums/snapshots
│   │   ├── ratings/               # submit-rating callable client
│   │   └── security/              # App Check activation
│   └── features/
│       ├── auth/                  # Firebase auth repo, user profile models/repos
│       ├── catalog/               # Perfume/Brand/Review models, repos, seed catalog
│       ├── cart/                  # cart models, repos, CartService
│       ├── checkout/              # address models, checkout service, payment gateways
│       ├── orders/                # order models, repos, status machine, admin service
│       ├── wishlist/              # wishlist repo + service
│       └── admin/                 # admin catalog service (guarded, UI not exposed)
├── functions/
│   ├── index.js                   # all Cloud Functions (≈1.5k lines)
│   ├── .env.example               # PayMongo secrets contract
│   ├── scripts/                   # admin provisioning/import helpers
│   └── test/firestore_rules.test.mjs
├── test/
│   ├── backend/                   # pure Dart domain/repository tests
│   ├── *.dart                     # widget/integration-style UI tests
├── assets/                        # fonts, product/brand/editorial imagery
├── docs/superpowers/              # design specs and implementation plans
├── design_mockups/                # visual reference screenshots
└── android/, ios/, web/, ...      # platform shells
```

### Known structural reality

`lib/main.dart` is intentionally called out as a hotspot: it owns bootstrap, the page enum, all navigation state, customer pages, checkout flow, and the admin dashboard. The domain layer is separated cleanly, but **presentation is not yet modularized**. Do not assume a `presentation/` folder exists under each feature.

---

## 5. Bootstrap sequence

Entry point: `lib/main.dart` → `main()`.

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. **Web:** `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
   **Android:** `Firebase.initializeApp()` using native `google-services.json`, then `configureScentifyFirestore()` sets a 100 MiB persistence cache.
   **Other platforms:** Firebase is not initialized; repositories fall back to in-memory implementations.
3. On web/Android: `activateScentifyAppCheck()`.
   - Debug builds use debug providers.
   - Release web requires `SCENTIFY_RECAPTCHA_SITE_KEY`.
   - Android release uses Play Integrity; Apple uses App Attest with DeviceCheck fallback.
4. Read `SharedPreferences` onboarding flag: `scentify.has_seen_onboarding`.
5. Restore Firebase Auth user (customer sessions only).
6. Resolve role from:
   - custom claims (`superadmin`, `admin`), refreshed once, and
   - `users/{uid}.role` profile document.
   - Admin/superadmin wins.
7. **Deliberate security rule:** if a restored user is an admin, the session is signed out and not restored. Admin must authenticate again each app launch.
8. Construct repositories:
   - Firestore on web/Android for catalog, cart, wishlist, orders, profile, saved address, reviews, autocomplete.
   - In-memory repositories otherwise (demo mode).
9. Initialize `NotificationService` (Android; web is a no-op).
10. Choose payment gateway:
    - `SCENTIFY_PAYMONGO_ENABLED=true` **and** Firebase platform → `PayMongoPaymentGateway`.
    - Otherwise → `SandboxPaymentGateway`.
11. `runApp(MyApp(...))` with repositories injected.

### Compile-time flags

| Flag | Effect |
| --- | --- |
| `SCENTIFY_PAYMONGO_ENABLED` | Enables PayMongo hosted checkout instead of sandbox |
| `SCENTIFY_RECAPTCHA_SITE_KEY` | Required for release web App Check |
| `SCENTIFY_GOOGLE_SERVER_CLIENT_ID` | Optional Google Sign-In server client ID on Android |

---

## 6. App shell and navigation

### Page enum

`ScentifyPage` contains 22 destinations:

`splash`, `onboarding`, `auth`, `home`, `catalog`, `topPicks`, `filters`, `product`, `wishlist`, `cart`, `checkoutAddress`, `checkoutDelivery`, `checkoutPayment`, `confirmation`, `tracking`, `notifications`, `profile`, `purchases`, `paymentMethods`, `helpCentre`, `about`, `admin`.

### Navigation mechanics

- `_page` is the current page; `_history` is a manual stack.
- `_go(page)` pushes the current page; `_replace(page)` clears history.
- `_back()` pops history or falls back to home.
- Android system back is intercepted with `PopScope`; it pops history, returns to home for authenticated non-home pages, otherwise exits.
- `KeyedSubtree(key: ValueKey(_page))` swaps complete pages synchronously to avoid Flutter inherited-widget assertions during fast navigation.
- Customer tab indices: `0 Home`, `1 Top Picks`, `2 Shop`, `3 Wishlist`, `4 Profile`.
- Admin is reached only by role-driven routing after auth, never from the customer bottom bar.

### Launch routing

```text
Splash (2.8s)
  ├─ onboarding seen? ── no ──> Onboarding (4 stages) ──> Auth or Home
  └─ yes
      ├─ authenticated customer ──> Home
      ├─ authenticated admin/superadmin ──> Admin
      └─ no session ──> Auth
```

Admin sessions are intentionally **not** restored between launches.

---

## 7. Customer surface map

| Page | Primary job | Key behavior / data |
| --- | --- | --- |
| Splash | Brand while loading | Logo, descriptor, progress |
| Onboarding | Explain value | Four stages; persists seen flag; skip available |
| Auth | Sign in/register | Email+password, Google, password reset; errors mapped to safe messages |
| Home | Start discovery | Search, campaign hero carousel, category shortcuts, brands, product modules, favorites, quick view |
| Catalog / Shop | Browse and narrow | Search, sort, gender chips, filters, adaptive product grid |
| Filters | Narrow the result set | Brand, gender, price range, fragrance family; apply/reset |
| Top Picks | Scan ranked recommendations | Ranked rows; opens product detail |
| Product Detail | Evaluate before buying | Image carousel, identity/price/rating, variant selection, notes, accordions, recommendations, verified reviews, sticky purchase bar |
| Quick View | Preview or add | Bottom sheet; size selection; add to cart; “View full details” |
| Wishlist | Revisit saved items | Reads `wishlists/{uid}`; toggle; open detail; add to cart |
| Cart | Confirm purchase | Select items/groups, quantities, remove, subtotal, checkout selected |
| Checkout: Address | Capture delivery | Manual entry or autocomplete; one saved address; edit/delete; validation |
| Checkout: Delivery | Choose speed | Standard ₱80, Express ₱150, Same day ₱250 |
| Checkout: Payment | Review and pay | Order summary, GCash/Maya/Card, server quote, place order |
| Confirmation | Reassure | Order reference and “View order” |
| Tracking | Status transparency | Timeline from order `events`, item summary, delivery details |
| Notifications | See order updates | In-app notification list, unread state, mark all read, deep-link to tracking |
| Profile | Account hub | Identity, order/wishlist counts, latest order, addresses, payment methods, help, about, logout |
| My Purchases | Order history + reviews | Filters, order cards, track, submit one verified review per purchased variant |
| Payment Methods | Choose default method | Selection only; no card storage |
| Help Centre | Support entry | FAQ/contact-style content and purchases shortcut |
| About Scentify | Brand information | Static editorial content |

### Discovery and filtering

- Home shortcuts map:
  - `For Her`, `For Him`, `Unisex` → gender filter.
  - `Floral`, `Fresh`, `Woody` → fragrance-family filter.
- Filters are applied client-side in `CatalogPage` / `CatalogFilters` over the streamed catalog.
- Product cards open **full detail**; quick view is a secondary action.
- Catalog grid columns adapt from 2 to 5 based on width (`ScentifyBreakpoints`).

---

## 8. Admin surface map

Entry: role-gated `AdminPage` in `lib/main.dart`.

| Module | Actual behavior | State |
| --- | --- | --- |
| Overview | KPI cards, fulfillment monitor, recent orders, module grid | Live from `orders` stream |
| Orders | List every order; approve payment; advance one status at a time | **Active** |
| Products | Preview loaded catalog products | Read-only |
| Inventory | Out-of-stock count, low-stock count (≤5 units) | Read-only |
| Customers | Count of distinct user IDs with orders | Read-only |
| Notifications | Explains order/payment/fulfillment channels | Informational |
| Settings | Account email, role, payment mode, loaded product count | Read-only |
| Admin access | Superadmin-only role display | Read-only, only for `superadmin` |

### Admin order transitions

Fixed sequence enforced by `OrderStatusMachine`:

```text
pending_payment → confirmed → processing → packed → shipped → delivered
```

- `pending_payment → confirmed` is surfaced as **“Approve payment”**.
- No skipping, no backward transitions, no cancellation.
- `AdminOrderService` requires `UserProfile.isAdmin`.
- Firestore rules independently allow updates only to admins.
- `PayMongo` normally performs `pending_payment → confirmed` itself through the webhook; manual approval covers sandbox/manual payment review.

---

## 9. Module reference

### 9.1 `core` modules

| Path | Responsibility |
| --- | --- |
| `core/models/money.dart` | Integer-centavo `Money` value object; arithmetic, comparison, formatting |
| `core/errors/app_exception.dart` | Sealed exceptions: validation, not found, authorization, conflict, stock, transition, payment |
| `core/firebase/firestore_codecs.dart` | Bidirectional map codecs for Perfume, Cart, Order, Address, Delivery, Events |
| `core/firebase/firestore_settings.dart` | Bounded offline persistence (100 MiB), idempotent |
| `core/inventory/inventory_service.dart` | `InventoryPort`; in-memory reserve/release; `NoOpInventoryService` for Firestore |
| `core/security/app_check.dart` | App Check provider selection per platform |
| `core/notifications/notification_service.dart` | FCM permission, token registration, foreground local notifications, in-app stream |
| `core/orders/order_review_api.dart` | Calls `getOrderReview`; validates quote identity/pricing/expiry |
| `core/orders/my_purchases_api.dart` | Calls `listMyPurchases` (currently unused by UI) |
| `core/ratings/product_rating_api.dart` | Calls `submitProductRating` |
| `core/addresses/address_autocomplete_api.dart` | Calls `addressAutocomplete` and `addressPlaceDetails` |
| `core/cart/add_to_cart_api.dart` | Calls `addToCart` (currently unused by UI) |
| `core/payments/payment_method.dart` | Payment method enum and payment snapshot |
| `core/network/client_rate_limiter.dart` | UX-only rate limiter (not a security boundary) |
| `core/network/debouncer.dart` | Cancels stale type-ahead work |
| `core/cache/firestore_read_cache.dart` | Generic TTL read cache (currently unused) |

### 9.2 `features/auth`

| File | Responsibility |
| --- | --- |
| `data/firebase_auth_repository.dart` | Email/password, Google, reset, restore, claim-role resolution |
| `data/firestore_user_profile_repository.dart` | `users/{uid}` read/watch/write |
| `data/in_memory_user_profile_repository.dart` | Test/demo adapter |
| `domain/models/user_profile.dart` | `UserRole { customer, admin, superadmin }`, profile |
| `domain/auth_error_messages.dart` | Maps Firebase error codes to user-safe copy |

Role resolution merges claims and profile; admin wins. Profile writes are restricted by rules so users cannot change their own role.

### 9.3 `features/catalog`

| File | Responsibility |
| --- | --- |
| `domain/models/perfume.dart` | Perfume, variant, gender, family, vibe, occasion, concentration |
| `domain/models/brand.dart` | Brand metadata |
| `domain/models/product_review.dart` | Verified review |
| `domain/repositories/catalog_repository.dart` | List/watch/find/save/delete + `CatalogFilter` |
| `data/firestore_catalog_repository.dart` | Live `perfumes` where `isPublished == true`; client-side filtering |
| `data/firestore_product_review_repository.dart` | Watch `perfumes/{id}/ratings`; submit through callable |
| `data/catalog_seed.dart` | 40 additional seed perfumes for demo/in-memory mode |
| `data/in_memory_*.dart` | Deterministic test/demo adapters |

### 9.4 `features/cart`

| File | Responsibility |
| --- | --- |
| `domain/models/cart.dart` | `Cart`, `CartItem` snapshots (display price) |
| `domain/services/cart_service.dart` | Add/set/remove; validates current variant and stock |
| `domain/repositories/cart_repository.dart` | Persistence contract |
| `data/firestore_cart_repository.dart` | `carts/{uid}` document |
| `data/in_memory_cart_repository.dart` | Test/demo adapter |

Important: cart line prices are **display data only**. Checkout reprices from the server-reviewed catalog.

### 9.5 `features/checkout`

| File | Responsibility |
| --- | --- |
| `domain/services/checkout_service.dart` | Orchestrates quote → inventory → payment → order → cart cleanup |
| `domain/services/checkout_review_provider.dart` | Quote port |
| `domain/services/payment_gateway.dart` | Payment gateway contract, request/session |
| `domain/models/*` | Shipping address, saved address, delivery option, quote |
| `data/sandbox_payment_gateway.dart` | Generates `sandbox-<method>-<orderId>-<n>` references |
| `data/paymongo_payment_gateway.dart` | Calls `createPayMongoCheckoutSession`; opens hosted URL |
| `data/firestore_saved_address_repository.dart` | `users/{uid}/addresses/primary` |
| `data/in_memory_saved_address_repository.dart` | Session/test adapter |

### 9.6 `features/orders`

| File | Responsibility |
| --- | --- |
| `domain/models/order.dart` | Immutable order, item snapshots, status events, status enum |
| `domain/services/order_status_machine.dart` | The only legal transition graph |
| `domain/services/order_service.dart` | Applies transitions and appends events |
| `domain/services/admin_order_service.dart` | Role-guarded admin transitions |
| `data/firestore_order_repository.dart` | `orders` read/watch/write; `watchAll()` for admin |
| `data/in_memory_order_repository.dart` | Test/demo adapter |

### 9.7 `features/wishlist`

Single `wishlists/{uid}` document holding `productIds` (max 100). `WishlistService` toggles membership. Rules restrict access to the owner.

### 9.8 `features/admin`

`AdminCatalogService` exposes role-guarded product save/delete, but **the admin UI does not call it**. Product editing remains unavailable.

### 9.9 `ui`

| File | Responsibility |
| --- | --- |
| `scentify_design_system.dart` | Palette, spacing, radii, shadows, typography, light/dark themes, shared widgets |
| `scentify_breakpoints.dart` | `compact < 600`, `medium 600–839`, `expanded ≥ 840`; max content 1360; catalog grid math |

`WireframeShell` is the shared customer layout boundary:
- Content max width 1360.
- Safe-area handling.
- Bottom `NavigationBar` on compact/medium.
- `NavigationRail` on expanded.
- Optional sticky bottom action bar (checkout/purchase).

---

## 10. Domain model contracts

### Money

- Integer **centavos**. `₱1,234.50` is `Money(123450)`.
- No doubles for stored or calculated money.
- Order, cart, variants, delivery fees, and PayMongo amounts all use centavos.

### Perfume

```text
Perfume
  id, brandId, brandName, name, description
  gender: men | women | unisex
  family: citrus | floral | woody | oriental | fresh | gourmand |
          chypre | aquatic | leather | aromatic
  concentration: edt | edp | parfum | extrait | cologne
  occasions: everyday | office | dateNight | formal | travel | evening | special
  vibes: clean | romantic | bold | elegant | playful | calming |
         mysterious | energetic
  topNotes[], heartNotes[], baseNotes[]
  variants[]: { id, label, volumeMl, price (Money), stock }
  imageUrls[], tags[], authenticityNote, isPublished
```

- `lowestPrice` = cheapest variant.
- `hasAvailableStock` = any variant stock > 0.
- `isPublished` gates storefront visibility in Firestore queries.

### Cart

```text
Cart { userId, items[], updatedAt }
CartItem { productId, variantId, productName, variantLabel, unitPrice, quantity }
```

### Order

```text
Order {
  id, userId,
  items[]: { productId, variantId, productName, variantLabel, unitPrice, quantity },
  shippingAddress, deliveryOption,
  subtotal, deliveryFee, total,
  status, paymentReference,
  createdAt, updatedAt,
  events[]: { from, to, changedAt, actorId }
}
```

- Items/address/delivery are immutable snapshots at purchase time.
- `events` is append-only.
- `delivered` is terminal.

### Delivery options (client and server must agree)

| ID | Label | Fee | Estimate |
| --- | --- | --- | --- |
| `standard` | Standard Delivery | ₱80 | 3–5 business days |
| `express` | Express Delivery | ₱150 | 1–2 business days |
| `same-day` | Same day delivery | ₱250 | Metro Manila only |

### Payment methods

Wire values: `gcash`, `maya`, `card`. Display labels: GCash, Maya, Credit / Debit Card.

---

## 11. Firestore data model

### Client-readable/writable collections

| Collection | Doc ID | Purpose | Access |
| --- | --- | --- | --- |
| `perfumes/{productId}` | product ID | Catalog + review aggregates | Read if `isPublished` or admin; write admin only |
| `perfumes/{productId}/ratings/{ratingId}` | deterministic review ID | Verified reviews | Read if product published (or owner/admin); write denied to clients |
| `users/{uid}` | Auth UID | Profile | Owner or admin read; owner create/update with fixed role/email |
| `users/{uid}/addresses/primary` | `primary` | Saved delivery address | Owner only; shape-validated |
| `users/{uid}/notificationTokens/{tokenId}` | sanitized token | FCM tokens | Owner only |
| `wishlists/{uid}` | Auth UID | `productIds[]` | Owner only |
| `carts/{uid}` | Auth UID | Cart items | Owner only; shape-validated |
| `orders/{orderId}` | order ID | Order snapshots | Owner or admin read; create only with valid review+intent/sandbox proof; update admin only |

### Server-only collections (rules deny all client access)

| Collection | Doc ID | Purpose |
| --- | --- | --- |
| `checkoutIntents/{orderId}` | order ID | PayMongo checkout session, pending/paid, 30-min TTL |
| `orderReviews/{orderId}` | order ID | Server-calculated quote, 10-min TTL |
| `paymongoWebhookEvents/{sha256(eventId)}` | hash | Webhook idempotency ledger |
| `rateLimits/{limitId}` | scoped key | Server rate-limit ledger |
| `addressSuggestions/{placeId}` | place ID | Curated autocomplete dataset |

### `perfumes` document shape (codec)

```json
{
  "brandId": "chanel",
  "brandName": "Chanel",
  "name": "Coco Mademoiselle",
  "description": "...",
  "gender": "women",
  "family": "floral",
  "concentration": "edp",
  "occasions": ["evening", "dateNight"],
  "vibes": ["elegant", "romantic"],
  "topNotes": ["Orange", "Bergamot"],
  "heartNotes": ["Rose", "Jasmine"],
  "baseNotes": ["Patchouli", "Vetiver"],
  "variants": [
    { "id": "50ml", "label": "50ml", "volumeMl": 50, "priceCentavos": 890000, "stock": 5 }
  ],
  "imageUrls": ["https://..."],
  "tags": ["...", "..."],
  "authenticityNote": "...",
  "isPublished": true,
  "reviewCount": 12,
  "ratingSum": 58,
  "ratingAverage": 4.83,
  "ratingDistribution": { "1": 0, "2": 1, "3": 1, "4": 2, "5": 8 }
}
```

Review aggregates are maintained by `submitProductRating`, never by the client.

### `orders` document shape

Includes `id`, `userId`, `items`, `shippingAddress`, `deliveryOption`, `subtotalCentavos`, `deliveryFeeCentavos`, `totalCentavos`, `status`, `paymentReference`, `createdAt`, `updatedAt`, `events`. Optional `paymentMethod`, `paymentStatus`, `paymentProvider` are added by the payment path.

### `users` document shape

`email`, `displayName`, `role` (`customer|admin|superadmin`), `createdAt`, `updatedAt`.

### Saved address shape

`fullName`, `phoneNumber`, `addressLine1`, `barangay`, `city`, `province`, `postalCode`, `label`, `isDefault`, optional `latitude`, `longitude`, `placeId`, `addressSource`, `notes`, `createdAt`, `updatedAt`.

### `addressSuggestions` shape

Required for autocomplete:
`searchKey` (lowercase prefix key), `primaryText`, `secondaryText`, `addressLine1`, `barangay`, `city`, `province`, four-digit `postalCode`, `latitude`, `longitude`. Document ID is `placeId`. No importer exists in the repo.

---

## 12. Checkout and payment pipeline

### 12.1 Normal place-order flow

`CheckoutService.placeOrder()` in `lib/features/checkout/domain/services/checkout_service.dart`:

1. Load the user's cart; reject empty cart.
2. Validate selected items still exist and belong to the cart.
3. Generate a client order ID (`order-<microseconds>` by default).
4. If Firestore-backed, request a **server quote** via `getOrderReview`:
   - Server reads the cart, product variants, and saved/manual address.
   - Server recalculates unit prices, stock availability, subtotal, delivery fee, total.
   - Server writes `orderReviews/{orderId}` with a 10-minute expiry.
   - Client verifies order ID, user ID, payment method, delivery ID, expiry, and cart quantities.
5. Reserve inventory:
   - In-memory/demo: decrements catalog stock; failures release the reservation.
   - Firestore: `NoOpInventoryService`; authoritative stock mutation happens only in the PayMongo webhook.
6. Create payment:
   - **Sandbox:** returns `sandbox-<method>-<orderId>-<n>` locally.
   - **PayMongo:** calls `createPayMongoCheckoutSession`, stores `checkoutIntents/{orderId}`, returns hosted `checkoutUrl`, and opens it.
7. Build the immutable order with `status = pending_payment` and save it to `orders/{orderId}`.
   - Firestore rules accept creation only if `validOrderReview` matches and either:
     - `validCheckoutIntent` is present (PayMongo), or
     - `paymentReference` matches `sandbox-...` (sandbox).
8. Clear the purchased items from the cart (or only selected items).
9. Return the order; UI shows Confirmation and Tracking.

### 12.2 PayMongo webhook flow

`paymongoWebhook` (HTTP, region `asia-southeast1`):

1. Accept POST only; reject body over 1 MB.
2. Verify `Paymongo-Signature` HMAC-SHA256 using `PAYMONGO_WEBHOOK_SECRET`; reject timestamps older than 10 minutes.
3. Accept only `checkout_session.payment.paid`.
4. Enforce IP rate limit and idempotency via `paymongoWebhookEvents`.
5. In a Firestore transaction:
   - Load order, intent, review; verify they match each other and the provider reference/amount.
   - Verify review items/address/delivery exactly match the order.
   - Validate every order line and shipping address.
   - Decrement each variant's stock; fail if any would go negative.
   - Set order to `confirmed`, `paymentStatus = paid`, `paymentProvider = paymongo`, append event `pending_payment → confirmed`.
   - Mark intent and review `paid`.
6. Return non-2xx on transient failure so PayMongo retries.

### 12.3 Sandbox vs PayMongo

| Concern | Sandbox (default) | PayMongo |
| --- | --- | --- |
| Enable | Default / `SCENTIFY_PAYMONGO_ENABLED` false | `--dart-define=SCENTIFY_PAYMONGO_ENABLED=true` |
| Server quote | Required (Firestore mode) | Required |
| Payment reference | `sandbox-...` | PayMongo session ID |
| Hosted checkout | No | Yes, via `url_launcher` |
| Auto-confirm | No; admin approves | Webhook confirms |
| Stock decrement | **Not automatic** in Firestore mode | Webhook decrements |
| Secrets | None | `PAYMONGO_SECRET_KEY`, `PAYMONGO_WEBHOOK_SECRET` |

> **Sharp edge:** with the default sandbox gateway and Firestore mode, `NoOpInventoryService` is used and no webhook runs, so stock does not decrease automatically. Only PayMongo webhook fulfillment decrements Firestore stock. Do not describe sandbox checkout as inventory-complete.

---

## 13. Cloud Functions reference

All code in `functions/index.js`; Node 22; region `asia-southeast1`.

| Function | Type | Auth / App Check | Purpose |
| --- | --- | --- | --- |
| `createPayMongoCheckoutSession` | Callable | Auth + App Check + rate limit 5/min | Validates review/intent, creates PayMongo session, returns checkout URL |
| `sessionCookie` | HTTP | Bearer ID token + rate limit | Optional web session-cookie bridge; not used by the Flutter app |
| `listMyPurchases` | Callable | Auth + App Check + 30/min | Returns mapped purchases; client exists but UI currently uses Firestore streams |
| `submitProductRating` | Callable | Auth + App Check + 10/hour | Verifies delivered purchase, prevents duplicates, updates product aggregates |
| `addressAutocomplete` | Callable | Auth + App Check + 20/min | Prefix search over `addressSuggestions` |
| `addressPlaceDetails` | Callable | Auth + App Check + 20/min | Returns validated address details for a `placeId` |
| `addToCart` | Callable | Auth + App Check + 30/min | Transactional server cart add; client exists but UI currently writes cart directly |
| `getOrderReview` | Callable | Auth + App Check + 30/min | Produces authoritative quote and writes `orderReviews` |
| `paymongoWebhook` | HTTP | Signature + IP rate limit | Confirms paid orders and decrements stock |
| `notifyOrderCreated` | Firestore trigger | Admin SDK | Normalizes payment/timeline fields, sends “order placed” push |
| `notifyOrderStatusChanged` | Firestore trigger | Admin SDK | Appends timeline, sends status push |

### Server-side helpers worth knowing

- `assertAllowedKeys` rejects unknown fields.
- `readId` enforces `^[A-Za-z0-9][A-Za-z0-9_-]*$` and ≤128 chars.
- `readString`, `readInteger`, `readEnum` enforce types/lengths.
- `enforceRateLimit` writes to `rateLimits`.
- `validateOrderForPayment` recomputes subtotal and validates address/postal code/delivery.
- `notifyUser` sends multicast FCM and deletes invalid tokens.
- `normalizeReviewAddress` resolves either `addressId` or inline `shippingAddress`, never both.

### Function secrets (Firebase environment / Secret Manager)

```
PAYMONGO_SECRET_KEY
PAYMONGO_WEBHOOK_SECRET
PAYMONGO_SUCCESS_URL
PAYMONGO_CANCEL_URL
```

Never place these in Flutter, `firebase_options.dart`, or public config.

---

## 14. Authentication, roles, and sessions

### Providers

- Email/password.
- Google Sign-In (web popup; Android Google Sign-In with optional server client ID).
- Password reset email.

### Role sources

1. Firebase custom claims: `superadmin == true`, `admin == true`.
2. `users/{uid}.role` in Firestore.

Role merge rules:
- `superadmin` beats `admin`.
- Either beats `customer`.
- Admin claims are refreshed before destination routing.
- Profile document is the normal source when token claims are unavailable.

### Session rules

- Customer sessions may persist between launches.
- Admin/superadmin sessions are **never restored**; the bootstrap signs them out.
- Signing out clears local notification registration and routes to Auth.
- The UI also reacts to live profile changes: an admin profile on Home is moved to Admin, and a demoted admin on Admin is moved to Home.

### Authorization layers

| Layer | Enforcement |
| --- | --- |
| UI | Role-gated routing and admin module visibility |
| Domain | `AdminOrderService`, `AdminCatalogService` check `isAdmin` |
| Firestore rules | `isAdmin()` via claims or profile role; order updates admin-only |
| Cloud Functions | Auth UID checks, ownership checks, App Check |
| Admin SDK | Webhook/triggers bypass rules but validate intent/review matching |

---

## 15. Security model

### Firestore rules (`firestore.rules`)

Key patterns:

- `signedIn()` and `validId()` helpers.
- `perfumes`: public read only when published; admin read all; admin write.
- `users`: owner/admin read; self-create forced to `customer`; self-update cannot change `role` or `email`.
- Addresses: owner-only, strict shape validation, timestamps/labels/source/coordinates.
- Wishlists/carts: owner-only, bounded list size and allowed keys.
- Orders:
  - Owner/admin read.
  - Create requires `validOrderReview` plus `validCheckoutIntent` or sandbox reference.
  - Update only admin.
  - Delete denied.
- Trusted collections (`checkoutIntents`, `orderReviews`, `paymongoWebhookEvents`, `rateLimits`, `addressSuggestions`): all client access denied.
- Ratings: client write denied; read only for published products or owner/admin.

### Client trust boundary

The client is **not** authoritative for:
- final price, delivery fee, or total,
- stock availability,
- payment status,
- admin role,
- review eligibility.

The client **is** currently authoritative for:
- cart contents/quantities (server revalidates at checkout),
- address text (server normalizes and validates at review),
- display-only cart line prices.

### App Check

- Callables use `enforceAppCheck: true`.
- Web debug uses `WebDebugProvider`; release needs reCAPTCHA v3 site key.
- Android release uses Play Integrity; Apple uses App Attest/DeviceCheck fallback.

### Secret handling

- PayMongo and webhook secrets live only in Functions environment.
- Firestore/Storage access is mediated by rules.
- Admin provisioning uses scripts under `functions/scripts/` with the Firebase CLI, not the app.

---

## 16. Notifications

- Android only in practice; `NotificationService.initialize()` no-ops on web.
- Requests FCM permission, creates the `scentify_orders` high-importance channel.
- Stores tokens at `users/{uid}/notificationTokens/{sanitizedToken}` with platform and server timestamp.
- Foreground messages are displayed locally and also pushed into an in-app broadcast stream.
- In-app notification center keeps read IDs in memory (not persisted across launches).
- Backend triggers:
  - `notifyOrderCreated` → “Order placed / waiting for payment confirmation”.
  - `notifyOrderStatusChanged` → status label update.
- Invalid/expired FCM tokens are deleted by the backend.
- Admin Notifications module does not compose or send campaigns.

---

## 17. UI and design system

### Visual tokens

| Token | Value / role |
| --- | --- |
| `background` | `#F6F2EC` warm paper |
| `surface` | `#FFFFFF` |
| `surfaceMuted` | `#F1EEE8` |
| `ink` | `#111114` |
| `muted` | `#6B6760` |
| `brassInk` | `#6A5A46` |
| `border` | `#E8E2D8` |
| `champagne` | `#B79A5B` |
| `champagneSoft` | `#F6EEDC` |
| `success` / `danger` | `#397258` / `#9B433D` |

Typography:
- Display: `DMSerifDisplay` (36/28/24).
- Utility/body: `Montserrat` (14 body, 12 caption/metadata).
- Material 3 theme with semantic roles, light + dark (`ThemeMode.system`).
- No dynamic color; brand palette is preserved.

### Responsive rules

| Width | Class | Navigation |
| --- | --- | --- |
| `< 600` | compact | Bottom navigation bar |
| `600–839` | medium | Bottom navigation bar |
| `≥ 840` | expanded | Navigation rail |

- Max content width: `1360`.
- Catalog columns: 2–5, derived from width, min tile 200, max tile 280.
- Layout is constraint-driven, not device-model-driven.
- Interactive targets target ≥48×48 dp.
- Text scaling must remain enabled.
- Hero carousel is manual: swipe + dot paging, no arrows, no auto-advance.

### Shared widgets

`ScentifyCard`, `ScentifySectionHeader`, `ScentifySelectableChip`, `ScentifyPrimaryButton`, `ScentifySecondaryButton`, `ScentifyRatingRow`, `ScentifyPriceText`, `ScentifyProductCard`, `ScentifyEmptyState`, `ScentifySkeleton`, `ScentifySizeSelectorCard`, `ScentifyIconButton`, `ScentifyPressScale`.

Legacy `Wire*` widgets and `WireframeColors` remain in `main.dart` for the existing pages; new work should prefer the `Scentify*` design system.

---

## 18. Testing map

### Flutter tests

| Area | Files | What they prove |
| --- | --- | --- |
| Domain/backend | `test/backend/*.dart` | Money, catalog filters, cart stock, inventory, checkout selection, order transitions, admin guards, codecs, auth errors, saved address, reviews |
| Widget/integration-style | `test/widget_test.dart`, `test/*_test.dart` | Splash/onboarding/auth, navigation, catalog, product detail, cart, checkout, purchases, profile, notifications, dark theme, text scaling, responsive widths |
| Scope guards | `test/admin_management_scope_test.dart` | Admin modules stay within documented scope |
| Design polish | `test/apple_design_polish_test.dart` | Press feedback, reduced motion, dark theme, large text |

Important: widget tests inject in-memory repositories. They do not exercise real Firebase, rules, Functions, App Check, FCM, or PayMongo.

### Rules tests

`functions/test/firestore_rules.test.mjs` runs against the Firestore emulator with the real rules file. It validates:
- address privacy/schema,
- catalog/order access,
- cart/order creation constraints,
- review write denial,
- trusted collection denial,
- admin-only updates,
- ownership boundaries.

### Commands

```bash
# From repository root
flutter analyze
flutter test

# Firestore rules tests (requires emulator + Java)
firebase emulators:exec --only firestore \
  --project demo-scentify-rules \
  "npm --prefix functions run test:rules"

# Function syntax check
(cd functions && npm run check)
```

Deployment:

```bash
firebase deploy --only firestore:rules,functions
```

Cloud Functions require the Blaze plan. Firestore rules can deploy independently.

---

## 19. Configuration and local setup

### Required for a live Firebase run

1. `lib/firebase_options.dart` and native Firebase config must point to the intended project.
2. App Check providers registered per platform.
3. Firestore rules + Functions deployed.
4. Address suggestions loaded if autocomplete is desired; otherwise use manual entry.
5. For PayMongo:
   - Set `PAYMONGO_SECRET_KEY`, `PAYMONGO_WEBHOOK_SECRET`, success/cancel URLs.
   - Deploy Functions.
   - Register webhook for `checkout_session.payment.paid`.
   - Build with `--dart-define=SCENTIFY_PAYMONGO_ENABLED=true`.
6. FCM configured + device permission granted.
7. Google provider + OAuth config for Google Sign-In.

### Seeded/demo behavior

When Firebase is unavailable (non-web/Android) or no repositories are injected:
- catalog uses `topPicksProducts` + 40 seed perfumes,
- cart starts with demo items,
- wishlist starts with three favorites,
- profile is a demo customer,
- all data is in-memory and resets on restart.

### Assets

- Fonts: `assets/fonts/` (Montserrat, DM Serif Display).
- Product/brand/editorial imagery: `assets/images/`.
- `PlaceholderImage` paints a stable fallback when assets/URLs are missing.

---

## 20. Known limitations and sharp edges

Read this before estimating work.

1. **`lib/main.dart` is a monolith.** Navigation, state, customer UI, checkout, and admin UI share one file. Refactors should be incremental; do not rewrite routing or move domain code casually.
2. **Admin product/inventory/customer/settings/access modules are read-only.** The README documents this; tests enforce the scope.
3. **Address autocomplete is static.** No live geocoder, no importer, and an empty collection means no suggestions. Manual address entry must remain available.
4. **Sandbox checkout does not decrement Firestore stock.** `NoOpInventoryService` is used for Firestore, and only the PayMongo webhook mutates stock.
5. **Cart writes are client-authoritative.** The `addToCart` callable exists but the UI does not use it. Server review revalidates price/stock at checkout, but cart contents themselves are not server-controlled.
6. **`listMyPurchases` and `AddToCartApi` are unused.** Orders are read via Firestore `watchForUser`; cart writes go through `FirestoreCartRepository`.
7. **Admin sessions are deliberately not restored.** Testing admin flows requires re-authentication each launch.
8. **One saved address only** (`addresses/primary`). No address list.
9. **No cancellation/refund flow.** `delivered` is terminal; no reverse transitions.
10. **No tax, coupon, or discount engine.** `getOrderReview` always reports `discountCentavos: 0`.
11. **Delivery fees are fixed** in both client and server; keep them in sync.
12. **Push notifications are Android-centric.** Web notifications are not initialized. In-app read state is memory-only.
13. **Platform coverage is narrow.** Firebase bootstraps only web and Android; iOS/Linux are unverified.
14. **Live configuration is not proven by tests.** Tests use in-memory adapters; verify App Check, FCM, PayMongo, rules deployment, and address data separately.
15. **`FirestoreReadCache`, `ClientRateLimiter`, and `Debouncer` are utilities without current call sites.** Do not assume they are active.
16. **Rating aggregates live on the product document.** If products are edited manually, keep `reviewCount`/`ratingSum`/`ratingAverage`/`ratingDistribution` consistent or regenerate via the function path.
17. **Product images may be remote URLs.** Firestore rules do not validate image hosts; rendering falls back to a placeholder on failure.
18. **Admin can only advance one status at a time.** There is no bulk transition.
19. **PayMongo success/cancel URLs point to `scentify.app` by default.** They must be configured for the real deployment.
20. **`firestore-debug.log` and build artifacts are present in the workspace.** Do not treat them as source.

---

## 21. Where to make common changes

| Task | Files to touch |
| --- | --- |
| Add a customer screen | `ScentifyPage` enum, `_ScentifyAppState.build()` switch, page widget in `main.dart`, nav/entry points |
| Add a reusable UI component | `lib/ui/scentify_design_system.dart` (or a focused `lib/ui/` file) |
| Change responsive layout | `scentify_breakpoints.dart`, `WireframeShell`, page `LayoutBuilder`s |
| Add a catalog field | `Perfume` model, `FirestoreCodecs`, seed/fixtures, affected UI, rules/tests if validated |
| Add a repository | Interface under `features/<x>/domain/repositories`, Firestore + in-memory adapters, wire in `main()` and `_ScentifyAppState` |
| Change cart rules | `CartService`, `CartRepository`, `firestore.rules`, backend `addToCart` if used, tests |
| Change checkout pricing | `CheckoutService`, `getOrderReview`, `firestore.rules`, backend validation, money tests |
| Add a payment provider | `PaymentGateway` implementation, callable/HTTP function, webhook handler, rules, secrets, tests |
| Change order statuses | `OrderStatus`, `OrderStatusMachine`, admin UI, `functions` status labels/triggers, rules/tests |
| Change admin permissions | `AdminOrderService`/`AdminCatalogService`, `firestore.rules` `isAdmin()`, auth claim resolution, admin UI gating |
| Change notification content | `NotificationService`, `notifyOrderCreated`/`notifyOrderStatusChanged`, FCM channel config |
| Add a Cloud Function | `functions/index.js`, `functions/.env.example` if secrets, client API under `lib/core/`, tests |
| Change security rules | `firestore.rules` + `functions/test/firestore_rules.test.mjs` (always together) |
| Update setup docs | `README.md` and this file |

---

## 22. Invariants checklist

Before merging any change, confirm:

- [ ] Money is still integer centavos.
- [ ] Checkout still gets a server quote before creating a Firestore order.
- [ ] Order item/address/delivery snapshots remain immutable.
- [ ] Status transitions still follow `pending_payment → confirmed → processing → packed → shipped → delivered`.
- [ ] Admin checks exist in domain, rules, and UI where relevant.
- [ ] No secret entered Flutter code or public config.
- [ ] Firestore rules and rules tests changed together for data-shape changes.
- [ ] Cart/checkout/wishlist/order/profile state is not discarded by navigation changes.
- [ ] Empty, loading, error, and disabled states still come from real data.
- [ ] Dark theme, text scaling, 48 dp targets, and reduced motion still hold for touched UI.
- [ ] `flutter analyze`, `flutter test`, rules tests, and `npm run check` pass (or failures are reported honestly).

---

## 23. Glossary

| Term | Meaning |
| --- | --- |
| **Variant** | A purchasable bottle size (e.g., 50ml) with its own ID, price, and stock |
| **Quote / review** | Server-calculated checkout snapshot in `orderReviews`, valid for 10 minutes |
| **Intent** | PayMongo checkout session record in `checkoutIntents`, valid for 30 minutes |
| **Snapshot** | Immutable order copy of item/address/delivery data at purchase time |
| **Verified review** | Rating submitted only for a delivered order owned by the user |
| **Sandbox** | Local fake payment gateway used by default |
| **Hosted checkout** | PayMongo page opened via URL; Scentify never sees card data |
| **App Check** | Firebase attestation required by callable functions |
| **Admin claim** | Firebase custom claim `admin` or `superadmin` |
| **Primary address** | The single saved address at `users/{uid}/addresses/primary` |

---

*Last updated: 2026-10-24. If the code and this document diverge, inspect the code and update this file as part of the same change.*
