# Scentify UI Modernization Implementation Plan

> **For agentic workers:** Execute inline, one phase at a time. Stop after each phase, summarize the changed files and remaining limits, and wait for the user to review before beginning the next phase.

**Goal:** Modernize Scentify's customer and admin presentation for legibility, accessibility, responsive use, and predictable product discovery without replacing its visual identity or changing commerce behavior.

**Architecture:** Keep `ScentifyApp` as the route/state composition boundary and preserve all repositories, domain services, models, and commerce invariants. Strengthen the existing Material 3 design system, introduce shared responsive breakpoints, and extract only reusable presentation units that have a clean dependency boundary.

**Tech Stack:** Existing Flutter/Dart app, Material 3, existing `ScentifyColors`/`ScentifyTypography`; no new runtime packages.

## Global Constraints

- Keep the existing Scentify identity: ivory/paper, espresso ink, restrained champagne/brass, Montserrat utility type, DM Serif Display headings, and current product imagery.
- Use Material 3 components and semantic roles; do not use Android Dynamic Color because it can displace the brand palette.
- Preserve the five customer destinations, admin/customer separation, Android system Back, checkout/cart/payment behavior, and existing data contracts.
- Use width constraints rather than device-model checks; begin with compact `<600 dp`, medium `600–839 dp`, and expanded `>=840 dp`.
- Essential body copy is at least 14 logical pixels; caption/overline roles are at least 12; preserve system text scaling.
- Meet WCAG AA text contrast (4.5:1 normal, 3:1 large), 3:1 for meaningful controls/icons/focus, and use 48×48 dp interactive targets with 8 dp separation where practical.
- Honor system light/dark appearance and reduce/disable-animations preferences; do not add decorative motion.
- No backend/schema/router rewrite, new package, asset conversion, or marketing-copy changes.
- Automated tests and builds are not part of this pass unless separately requested; use source/diff review at each checkpoint.
- The checkout has no usable Git metadata; do not attempt commits.

## File Map

- `lib/ui/scentify_design_system.dart` — semantic Scentify colors, typography roles, and light/dark Material 3 themes.
- `lib/ui/scentify_breakpoints.dart` — shared compact/medium/expanded width thresholds used by app layouts.
- `lib/ui/wireframe_shell.dart` — extracted shared responsive shell and customer navigation components.
- `lib/ui/placeholder_image.dart` — extracted image wrapper and painted fallback, including decode-size behavior.
- `lib/main.dart` — existing root state/router and feature widgets; only targeted UI behavior and call-site updates remain here.
- `docs/superpowers/specs/2026-10-13-scentify-ui-modernization-design.md` — approved design authority; update only if implementation requires an approved scope change.
- `test/` — unchanged in this pass.

Each numbered task below is a user-review phase. Do not start the next task until the user approves the prior phase's result.

---

### Phase 1: Readability and accessibility foundation

**Files:**
- Modify: `lib/ui/scentify_design_system.dart`
- Modify: `lib/main.dart`

**Consumes:** Current `ScentifyTypography`, `ScentifyColors`, `WireframeColors`, and existing shared controls.

**Produces:** Named, consistent typography roles; an accessible deep-brass text role; corrected high-impact tiny labels; controls meeting the 48 dp minimum without visually enlarging their glyphs.

- [x] Map display, title, section, body, supporting, label, and metadata text to existing `TextTheme` roles. Keep Montserrat and DM Serif Display.
- [x] Raise essential body/caption/overline styles to the specified floors and replace tiny product-card brand, gender, volume, price, and action-label styles with legible roles. Keep only non-essential decorative exceptions below 12 logical pixels.
- [x] Replace pale champagne on light surfaces where it carries essential text or state with a darker branded brass/olive role; preserve champagne for decorative fills and borders.
- [x] Update quick-view close and other undersized high-use icon controls to 48×48 dp hit regions, preserving their visible icon size and accessible tooltip/label.
- [x] Review the changed style/control call sites against the contrast and target-size criteria; summarize any remaining source-level exceptions.

**Phase gate:** Show the token/type/accessibility changes and ask whether to continue to Phase 2.

---

### Phase 2: Adaptive navigation and layouts

**Files:**
- Create: `lib/ui/scentify_breakpoints.dart`
- Modify: `lib/main.dart`

**Consumes:** Phase 1 typography/contrast roles and the existing five-item customer navigation.

**Produces:** Constraint-driven compact and expanded app layouts; responsive customer/admin navigation; catalog and skeleton grids that share one column rule.

- [x] Add `ScentifyBreakpoints` with `compactMaxWidth = 600.0` and `expandedMinWidth = 840.0`; classify `600–839 dp` as medium.
- [x] Update `WireframeShell` to use a Material 3 bottom `NavigationBar` on compact windows and a `NavigationRail` on expanded windows, preserving destination labels/order and selected state.
- [x] Keep the admin workspace distinct; adapt its navigation to available width rather than stretching its phone-only arrangement.
- [x] Set a readable maximum content width on wide windows and use safe-area/window insets so page content, bottom actions, and keyboard-focused fields remain reachable.
- [x] Derive catalog column count from available content width; apply the same count to `CatalogSkeletonGrid` and keep tile width capped on wide windows.
- [x] Review narrow, medium, and expanded layout calculations and confirm the checkout bottom action and wide summary remain in their existing roles.

**Phase gate:** Show the breakpoint and navigation/layout diff; wait for approval before Phase 3.

---

### Phase 3: Product discovery and detail-flow consistency

**Files:**
- Modify: `lib/main.dart`

**Consumes:** Existing `CatalogFilters`, family matching, `HomePage` shortcuts, `CatalogPage`, `ProductQuickView`, and product-detail routing.

**Produces:** Working scent-family shortcuts and one predictable primary product-selection path, with quick view as an explicit secondary preview.

- [x] Add `CatalogFilters.copyWith({Set<String>? brands, Set<String>? families, String? gender, RangeValues? priceRange})` while preserving immutable defaults.
- [x] Map `For Her`, `For Him`, and `Unisex` shortcuts to gender; map `Floral`, `Fresh`, and `Woody` to the matching family. Preserve unrelated active filters and show the selected shortcut/filter in Catalog.
- [x] Route primary product card/row taps from Home, Catalog, Top Picks, and Wishlist through `_selectProduct` to the full detail page.
- [x] Add a clearly labeled, accessible Quick View action to Home `ProductCard`, Catalog `CatalogProductTile`, and the Top Picks row pattern, with a 48×48 dp hit region. Keep its “View full details,” size selection, stock state, add-to-cart, and close actions intact.
- [x] Review the callback wiring and filter-state transitions to confirm add-to-cart/favorite behavior and repository state are unchanged.

**Phase gate:** Reviewed and approved after source review; Phase 4 authorized by the user's instruction.

---

### Phase 4: Complete system appearance

**Files:**
- Modify: `lib/ui/scentify_design_system.dart`
- Modify: `lib/main.dart`

**Consumes:** Phase 1 semantic type/color roles and the existing light Material 3 theme.

**Produces:** A deliberately designed dark Scentify palette and system-following theme selection, not a quick inversion.

- [x] Add `ScentifyThemeColors extends ThemeExtension<ScentifyThemeColors>` in `lib/ui/scentify_design_system.dart`, with light/dark roles for canvas, paper, ink, muted, faint, field, placeholder, placeholder line, border, primary action, dark surface, tobacco, readable brass, soft gold, olive, success, danger, selected state, and cart surfaces.
- [x] Implement `copyWith`, `lerp`, and `ScentifyThemeColors.of(BuildContext)`; register matching light/dark extension values from `ScentifyTheme.light()` and `ScentifyTheme.dark()`.
- [ ] Define light and dark values that preserve the warm Scentify palette and meet contrast targets.
- [x] Add `ScentifyTheme.dark()` using the same typography/component conventions as light mode.
- [x] Set `darkTheme` and `ThemeMode.system` on `MaterialApp`.
- [ ] Replace fixed light-only `WireframeColors` use across customer/admin surfaces with the corresponding theme role or Scentify `ThemeExtension`; keep only intentionally fixed artwork colors.
- [ ] Review selected, disabled, focus, loading, error, and empty-state colors in both schemes from source; list any runtime appearance checks still outstanding.

**Progress checkpoint:** The semantic theme extension, dark theme, system mode, shared shell/navigation colors, image fallback colors, and key product surfaces are theme-aware. A source scan still finds 437 `WireframeColors` references in `lib/main.dart`; the broader customer/admin migration and two-scheme state review are not complete. No runtime/device appearance review has been performed.

**Phase gate:** Show both semantic palettes and the converted call-site scope; wait for approval before Phase 5.

---

### Phase 5: Motion and image rendering

**Files:**
- Modify: `lib/main.dart`

**Consumes:** Existing `HomeHeroCarousel`, its timer and `PageController`, and `PlaceholderImage` asset/network/fallback behavior.

**Produces:** User-controlled, lifecycle-aware hero rotation and size-appropriate image decoding with stable fallbacks.

- [ ] Give `HomeHeroCarousel` explicit pause/resume state and an accessible control; reset the timer on manual page changes.
- [ ] Stop the auto-advance timer when the app is inactive or animations are disabled; allow immediate manual swipes/page changes in reduced-motion mode.
- [ ] Derive `cacheWidth`/`cacheHeight` for asset and network images from rendered logical dimensions and `MediaQuery.devicePixelRatio`; leave unknown-size images uncropped and preserve current fallback/loading builders.
- [ ] Review timer disposal/resumption paths, repeated taps, and image sizing/fallback branches from source without changing slide copy or source assets.

**Phase gate:** Show the motion/image changes and report source-level checks; wait for approval before Phase 6.

---

### Phase 6: Presentation separation and final consistency pass

**Files:**
- Create: `lib/ui/wireframe_shell.dart`
- Create: `lib/ui/placeholder_image.dart`
- Modify: `lib/main.dart`
- Modify: `lib/ui/scentify_design_system.dart` only if a shared color alias belongs there

**Consumes:** Final shell, navigation, image, and semantic theme behavior from Phases 1–5.

**Produces:** A smaller route/composition file and two reusable UI modules with explicit imports, without moving domain or route state.

- [ ] Move `WireframeShell` and `WireBottomNav` from `lib/main.dart` into `lib/ui/wireframe_shell.dart`; use `ScentifyThemeColors`/Material roles and preserve their public callback API.
- [ ] Move `PlaceholderImage` and `_PlaceholderPainter` into `lib/ui/placeholder_image.dart`; resolve default fallback colors from `ScentifyThemeColors`, retain explicit per-product tones, and preserve asset/network loading and error behavior.
- [ ] Update `lib/main.dart` imports and remove the moved declarations without renaming product/domain types or changing route ownership.
- [ ] Review the final changed-file list and diff for unrelated churn, duplicate tokens, missing imports, accidental copy changes, or altered commerce state paths.

**Phase gate:** Present the completed source diff and the limits of verification. Do not claim runtime/device validation unless it was performed.

## Execution Notes

- Execute inline, sequentially, with a review checkpoint after every phase, as requested.
- Do not add or run automated tests/builds unless the user separately asks. The Flutter SDK cache is currently read-only, so runtime rendering may also require a later writable toolchain.
- No commit steps are included because `.git` is empty in this workspace mount.
