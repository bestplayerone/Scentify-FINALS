# Scentify UI Modernization Design

## Status

Approved implementation scope. The six-phase sequence is in `docs/superpowers/plans/2026-10-13-scentify-ui-modernization.md`. No UI code has been changed yet. Preserve the existing Scentify visual identity and commerce behavior while making the presentation more legible, adaptive, accessible, and consistent.

## Goals

- Make product discovery and purchase paths clear and predictable on phones, tablets, and wide windows.
- Improve readability, contrast, touch targets, and system text scaling across customer and admin surfaces.
- Keep the warm editorial Scentify identity: paper/ivory surfaces, espresso ink, restrained champagne/brass accents, Montserrat utility type, DM Serif Display headings, and the existing product imagery.
- Reduce unnecessary image decoding and motion without adding dependencies or changing catalog/payment data contracts.
- Reduce presentation code concentration incrementally; keep routing and domain services stable.

## Current Evidence

- `lib/main.dart` owns the root page switch and a large share of customer/admin presentation code; domain models and services already have feature boundaries under `lib/core/` and `lib/features/`.
- `lib/ui/scentify_design_system.dart` defines the primary palette, spacing, shape, typography, and a light Material 3 theme. The app currently sets only `theme` on `MaterialApp`.
- `WireframeShell` currently uses the same custom floating bottom navigation wherever it is shown. The customer hierarchy has five destinations; admin is intended to remain a separate workspace.
- The customer catalog fixes its product grid at two columns. The home Floral, Fresh, and Woody shortcuts currently open the unfiltered catalog even though matching fragrance-family filters already exist.
- A source scan found many explicit type sizes below 12 logical pixels, a 32×32 quick-view close control, and champagne text on the light canvas with insufficient contrast for small text.
- The home hero auto-advances every five seconds without an explicit pause or reduced-motion path. `PlaceholderImage` does not currently pass its rendered dimensions to image decoders.
- Product-card taps use quick view in several discovery surfaces while the wishlist opens the full detail page. The existing wireframe hierarchy treats full product detail as the primary product-evaluation destination and quick view as a separate preview step.

## Design Direction

This is a refinement, not a rebrand. Keep the existing palette intent, logo, imagery, content claims, and restrained editorial tone. Use color and type with stronger semantic roles rather than adding decoration. Avoid marketplace conventions, card-heavy layouts, new product claims, gratuitous gradients, or a new icon family.

Material 3 remains the interaction and adaptive-layout foundation. Scentify colors and typography are mapped into Material roles; system appearance and text scaling are respected. Android Dynamic Color is not used because wallpaper-derived colors could undermine the brand palette.

## Architecture and Components

1. Keep `ScentifyApp` responsible for route/state composition and leave repositories, services, models, authentication, checkout, and payment flows unchanged.
2. Treat `WireframeShell` as the shared customer layout boundary: compact navigation on narrow windows, a Material navigation rail on expanded windows, safe-area/inset handling, and a content max-width on wide layouts. Preserve the five customer destinations and keep admin navigation distinct.
3. Use constraint-driven layout classes rather than device-model checks. Start with compact `<600 dp`, medium `600–839 dp`, and expanded `>=840 dp`; adjust a threshold only if rendered evidence shows a real fit issue.
4. Keep a two-column catalog on compact widths and increase columns as width permits, with a sensible maximum tile width so cards do not stretch. Rework the skeleton grid with the same column rule.
5. Extract or relocate only the presentation units touched by this work into focused `lib/ui/` or feature `presentation/` files. Do this incrementally; do not move or rewrite domain code as part of the UI pass.

## Interaction and Information Architecture

- Map `For Her`, `For Him`, and `Unisex` to the existing gender filter. Map `Floral`, `Fresh`, and `Woody` to the existing fragrance-family filter. Opening a shortcut should show the selected filter as active and preserve other non-conflicting filters; `Top Picks` and `Bestsellers` continue to open their existing recommendation surface.
- Make a product's primary card/row tap open the full product-detail page consistently. Keep quick view as an explicit secondary preview action where it is available, with a clear route to full details. Add-to-cart and favorite actions remain distinct and retain their current behavior.
- Preserve customer navigation labels/order, Android system Back, cart selection and quantity behavior, checkout steps and payment state, mobile checkout action dock, wide checkout summary, order tracking, and admin/customer separation.
- Keep loading, empty, error, disabled, and success states connected to their existing data/state sources; do not fabricate content when data is unavailable.

## Type, Color, Accessibility, and Theme

- Map display, page title, section title, body, supporting copy, label, and metadata to named `TextTheme` roles. Keep DM Serif Display for editorial headings and Montserrat for utility copy.
- Set ordinary body copy to at least 14 logical pixels and caption/overline roles to at least 12. Do not disable Flutter text scaling. Any smaller decorative exception must not carry essential meaning and must have an accessible equivalent.
- Do not use the current light champagne token as small text on pale surfaces. Introduce or select a deeper branded brass/olive text role that meets contrast, and reserve pale gold for fills, borders, or decorative accents.
- Meet WCAG AA contrast for text (4.5:1 normal, 3:1 large) and 3:1 for meaningful controls/icons and focus indicators. Ensure focus and selected states remain distinguishable without color alone.
- Provide at least 48×48 dp interactive targets with 8 dp separation where practical, including quick-view close, favorite, cart, and notification controls; preserve the visible icon scale where the layout is tight.
- Add a deliberate dark Material 3 color scheme that preserves Scentify's warm brand character; use `ThemeMode.system` and semantic theme roles rather than inverting the light palette. No separate in-app theme preference is added in this scope.

## Motion and Image Performance

- Keep the existing hero content and swipe behavior. Provide an obvious pause/resume affordance for automatic rotation, stop rotation when the app is not active, and honor the platform's reduce/disable-animations setting. With animations disabled, do not auto-advance; allow immediate manual page changes.
- Use short, interruptible Material transitions for routine state changes. Do not add decorative parallax, scroll reveals, or new motion dependencies.
- In `PlaceholderImage`, derive decoder cache dimensions from the rendered logical size and device pixel ratio, while retaining the current aspect ratio, loading state, and fallback behavior. Leave source assets and catalog image URLs unchanged in this pass.

## Failure and Recovery Behavior

- Failed or missing product images retain the existing painted placeholder and stable layout dimensions.
- Empty catalog results preserve query/filter context and provide a clear reset/browse route.
- Navigation changes must not discard cart, checkout, wishlist, order, or profile state.
- Reduced motion, large text, narrow windows, and the on-screen keyboard must not hide primary actions or block Back navigation.

## Out of Scope

- Rebrand, new font or imagery acquisition, changed marketing copy/claims, or a marketplace-style visual treatment.
- Backend/API/schema, catalog family taxonomy, authentication, cart rules, checkout/payment providers, notifications, and admin permissions.
- Rewriting the router or replacing the repository/service architecture.
- Image format conversion, CDN work, persistent network-cache policy, new packages, or an admin product redesign beyond shared system/adaptivity/accessibility fixes.
- Adding or running automated tests/builds in this pass unless separately requested.

## Acceptance Criteria

- Customer navigation remains five destinations; it adapts to available width rather than stretching the phone navigation across a tablet/desktop window. Admin remains visually and structurally separate.
- Catalog and skeleton grids use matching adaptive columns; product tiles remain readable and do not exceed the chosen max width.
- Every home fragrance-family shortcut opens the catalog with the matching family visibly selected and matching products shown; gender shortcuts continue to work.
- Product primary taps lead to full product detail consistently; quick view is clearly secondary and offers a path to full details.
- No essential visible text is below the agreed type-role floor; body/supporting type respects the user's text scale; contrast and interactive target criteria above are met.
- Light and dark appearance both use semantic Scentify roles with legible controls, selected states, and system surfaces.
- Hero rotation can be paused, stops when the app is inactive, and is disabled under reduced motion; manual navigation remains available.
- Images decode near their displayed pixel dimensions and preserve stable fallback/layout behavior.
- Cart, checkout, payment, order, auth, profile, wishlist persistence, and admin data behavior remain unchanged.
- Presentation extraction is incremental and produces no broad domain/router churn.

## Verification Plan

Review the changed source paths and diffs for scope and state preservation. Where a runnable Flutter environment is available and explicitly authorized, inspect the key customer/admin paths at compact, medium, and expanded widths, with increased text scale, light/dark appearance, keyboard open, and reduced motion. Automated tests and builds are intentionally not part of this approved scope.
