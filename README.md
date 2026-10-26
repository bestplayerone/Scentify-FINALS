# Scentify

Scentify is a Flutter shopping app for browsing and ordering fragrances. Customers can browse products, search and filter the catalog, save favorites, manage a cart, create an account, and place orders. The app also includes admin screens for order management.

## How the app works

- Flutter renders the Android app and manages navigation, forms, cart state, and checkout screens.
- Supabase Auth handles customer email/password and Google sign-in. New email accounts must confirm their email before signing in.
- Supabase Postgres stores the catalog, customer profiles, carts, wishlists, and orders. Row Level Security and database functions protect customer data and trusted checkout operations.
- Supabase Edge Functions connect trusted server-side operations to Xendit. Payment credentials and webhook secrets belong in backend secrets, never in the app.
- Firebase packages remain in the project for legacy and platform integrations. Some admin, review, address, and notification features still use Firebase services and need their corresponding configuration and deployed backend resources.

## Tech stack

| Area | Technology |
| --- | --- |
| Mobile app | Flutter, Dart, Material |
| Authentication and primary backend | Supabase Auth, Postgres, Row Level Security, RPC, Edge Functions |
| Online payments | Xendit hosted checkout and webhooks |
| Legacy/platform integrations | Firebase Auth, Cloud Firestore, Cloud Functions, App Check, Firebase Cloud Messaging |
| Local preferences | `shared_preferences` |
| Tests | Flutter widget tests and Dart tests |

## Install and run

### Requirements

- Flutter SDK compatible with the Dart SDK constraint in `pubspec.yaml`
- Android Studio/Android SDK for an Android build, or Chrome for a web run
- Network access to the configured Supabase project

### Setup

```bash
git clone <repository-url>
cd scentify
flutter pub get
```

The app has a default Supabase project URL and publishable key in `lib/core/supabase/supabase_bootstrap.dart`. To use another project, pass its public client values at build/run time:

```bash
flutter run \
  --dart-define=SCENTIFY_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SCENTIFY_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Run on a connected Android device/emulator with `flutter run`, or on Chrome with `flutter run -d chrome`.

Build an Android APK:

```bash
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. A release APK requires the project's Android signing configuration.

## Backend setup

For a new or updated Supabase environment, configure email/password and any desired OAuth providers, apply the migrations, and deploy the Edge Functions. See [supabase/README.md](supabase/README.md) and `scripts/deploy_supabase.sh` for backend details. Xendit checkout also requires its server-side secrets and webhook configuration.

Firebase-backed legacy features need the appropriate Firebase project configuration, App Check setup, rules, functions, and notification settings. Those services are not configured by the Supabase setup alone.

## Checks

```bash
flutter analyze
flutter test
```

These checks validate source and automated test behavior. They do not verify live authentication, email delivery, deployed backend configuration, payment processing, or device behavior.
