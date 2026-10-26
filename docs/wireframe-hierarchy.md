# Scentify wireframe hierarchy

This is the structure to lock before applying visual design. The wireframe should
answer one question per screen: what is the user here to decide or do next?

## Global rules

- Use one primary action per screen. Secondary actions stay text-only or move into
  an overflow/contextual area.
- Use the order `context → content → decision → action`.
- Reserve the strongest text weight and darkest control for the current decision.
- Group related controls in one surface. Do not turn every section into a card.
- Keep the grayscale wireframe neutral: placeholders communicate layout, not
  final brand styling.
- Keep bottom navigation limited to the five customer destinations: Home, Top
  Picks, Shop, Wishlist, and Profile.

## Customer flow

| Area | Primary job | Hierarchy |
| --- | --- | --- |
| Splash | Establish the brand while loading | Logo → descriptor → progress |
| Onboarding | Explain the value of discovery | Image → title → short explanation → progress → Next |
| Login / Register | Get the user into the product | Mode switch → heading → fields → submit → alternate sign-in |
| Home | Start discovery | Brand/actions → search → campaign hero → categories → Best Sellers → brands |
| Catalog | Browse and narrow | Page title → search → category filters → sort/result count → product grid |
| Filters | Make a narrower choice | Brand → gender → price → fragrance family → notes → Apply Filters |
| Top Picks | Scan trusted recommendations | Title/context → ranked rows → product detail |
| Quick View | Decide whether to inspect or add | Product image → identity/price → size → Add to Cart → View full details |
| Product Detail | Evaluate before purchase | Image → identity/price/reviews → size → notes → expandable details → sticky Add to Cart |
| Wishlist | Revisit saved products | Title/context → product rows → product detail |
| Cart | Confirm what will be bought | Cart header → select/items → quantities → total → Checkout |
| Checkout | Complete one step at a time | Step indicator → step content → Back / Continue or Pay Now |
| Confirmation / Tracking | Reassure and provide status | Confirmation → order reference → View Order → timeline |
| Profile | Manage the account | Identity → account stats → latest order → account actions → support/settings → logout |

## Admin boundary

Admin should read as a separate workspace, not as another customer tab. Keep
Dashboard, Products, Brands, Categories, Orders, Customers, Inventory, Media,
Reports, Settings, and Logout in an admin menu with Dashboard as the only visible
content area in the first wireframe pass.

## Current implementation pass

The Flutter wireframe now reflects the most important hierarchy changes in
`lib/main.dart`:

- Home has a brand header, a dedicated search row, a clearer hero, and a more
  intentional discovery order.
- Catalog has a page-level title before search and filters.
- Top Picks gives rank the strongest visual anchor in each row.
- Product Detail groups product identity, sizes, and fragrance notes into clear
  decision blocks while keeping the purchase bar sticky.
- Profile now works as an account hub: identity header → quick stats → latest
  order status → grouped account actions → logout.
- Wishlist rows prioritize brand, product name, volume, and price instead of
  showing selection controls that do not serve the screen's job.
- Filters only contain filter concerns; unrelated About and Reviews rows were
  removed.
- Cart and checkout surfaces use the same restrained corner radius and spacing
  language as the rest of the wireframe.

Before visual styling, review the remaining product decisions: final bottom-nav
labels, whether Top Picks is a primary destination, and whether Admin ships as a
separate app/workspace.

## Visual direction draft

The first high-fidelity direction is saved as
`scentify-design-draft.html`. It uses warm paper, tobacco ink, aged gold, and
olive/tobacco product studies with Cormorant Garamond for display type and
Manrope for utility copy. Product bottles are inline SVG studies, so the draft
does not depend on generated imagery or stock photography.

Open a specific screen directly with a hash:

- `#home`
- `#catalog`
- `#product`
- `#cart`
- `#checkout`
- `#profile`
