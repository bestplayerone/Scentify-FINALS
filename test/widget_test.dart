import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scentify/main.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/core/notifications/notification_service.dart';
import 'package:scentify/features/auth/data/in_memory_user_profile_repository.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/cart/data/in_memory_cart_repository.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/catalog/data/catalog_seed.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/orders/data/in_memory_order_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/wishlist/data/in_memory_wishlist_repository.dart';
import 'package:scentify/ui/scentify_design_system.dart';

void main() {
  test('overlong provider names fall back before profile persistence', () {
    expect(
      resolveProfileDisplayName(
        displayName: List.filled(121, 'A').join(),
        existingName: null,
        userId: 'user-1',
        fallbackName: 'juan',
      ),
      'juan',
    );
  });

  testWidgets('splash advances to the onboarding screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(ScentifyLogo), findsOneWidget);
    expect(find.byKey(const Key('splash-progress')), findsOneWidget);
    expect(find.text('Discover fragrances for every you.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1000));

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('splash-progress')),
    );
    expect(progress.value, greaterThan(0.2));
    expect(progress.value, lessThan(1));
    expect(find.text('Discover fragrances for every you.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2000));

    expect(find.text('Discover fragrances for every you.'), findsOneWidget);
  });

  testWidgets('splash places its brand above the loading bar', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp());

    final logoRect = tester.getRect(find.byType(ScentifyLogo));
    final progressRect = tester.getRect(
      find.byKey(const Key('splash-progress')),
    );

    expect(logoRect.center.dy, lessThan(300));
    expect(progressRect.top, greaterThan(logoRect.bottom));
  });

  testWidgets('onboarding next advances through all four stages before login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 3000));

    expect(find.text('Discover fragrances for every you.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Find your next favorite.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Make fragrance feel personal.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Keep the scents you love close.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('auth uses the minimal Scentify login shell', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));

    expect(find.byKey(const Key('auth-page')), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Scentify'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with phone'), findsNothing);
    expect(find.byKey(const Key('auth-back')), findsNothing);
  });

  testWidgets('onboarding skip goes directly to login', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.onboarding));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Discover fragrances for every you.'), findsNothing);
  });

  testWidgets('onboarding is skipped after it is completed once', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(MyApp(launchPreferences: preferences));
    await tester.pump(const Duration(milliseconds: 3000));

    expect(find.byKey(const Key('onboarding-next')), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-page')), findsOneWidget);

    await tester.pumpWidget(MyApp(launchPreferences: preferences));
    await tester.pump(const Duration(milliseconds: 3000));

    expect(find.byKey(const Key('onboarding-next')), findsNothing);
    expect(find.byKey(const Key('auth-page')), findsOneWidget);
  });

  testWidgets('a restored auth session skips login after onboarding', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'scentify.has_seen_onboarding': true,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MyApp(
        launchPreferences: preferences,
        initialAuthenticatedUserId: 'restored-user',
      ),
    );
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-page')), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('restored admin session opens the admin dashboard', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'scentify.has_seen_onboarding': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final admin = UserProfile(
      id: 'admin-1',
      email: 'admin@example.com',
      displayName: 'Scentify Admin',
      role: UserRole.admin,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MyApp(
        launchPreferences: preferences,
        initialAuthenticatedUserId: admin.id,
        initialUserProfile: admin,
        customerId: admin.id,
        orderRepository: InMemoryOrderRepository(),
        userProfileRepository: InMemoryUserProfileRepository(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin-page')), findsOneWidget);
    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.byKey(const Key('auth-page')), findsNothing);
  });

  testWidgets('superadmin dashboard exposes its protected management modules', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'scentify.has_seen_onboarding': true,
    });
    final preferences = await SharedPreferences.getInstance();
    final superadmin = UserProfile(
      id: 'superadmin-1',
      email: 'superadmin@example.com',
      displayName: 'Scentify Superadmin',
      role: UserRole.superadmin,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MyApp(
        launchPreferences: preferences,
        initialAuthenticatedUserId: superadmin.id,
        initialUserProfile: superadmin,
        customerId: superadmin.id,
        orderRepository: InMemoryOrderRepository(),
        userProfileRepository: InMemoryUserProfileRepository(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();

    expect(find.text('Superadmin dashboard'), findsOneWidget);
    expect(find.byKey(const Key('admin-module-access')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-module-access')));
    await tester.pumpAndSettle();
    expect(find.text('Superadmin access'), findsOneWidget);
  });

  testWidgets('customer screens omit the custom status bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));

    expect(find.text('9:41'), findsNothing);
  });

  testWidgets('top bar Cart action opens the cart with its item count', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));

    expect(find.text('Top Picks'), findsWidgets);
    expect(find.text('Cart'), findsNothing);
    expect(find.byTooltip('Cart'), findsOneWidget);
    expect(find.byKey(const Key('cart-count-badge')), findsOneWidget);

    await tester.tap(find.byTooltip('Cart'));
    await tester.pumpAndSettle();

    expect(find.text('My Cart (3)'), findsOneWidget);
    expect(find.text('Top Picks'), findsNothing);
  });

  testWidgets('Shop tab opens product discovery', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));

    await tester.tap(find.byKey(const ValueKey('bottom-nav-item-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-product-grid')), findsOneWidget);
    expect(find.text('Shop all scents'), findsOneWidget);
    expect(find.text('Top 10 Perfumes'), findsNothing);
  });

  testWidgets('home header fits narrow phone widths with cart actions', (
    WidgetTester tester,
  ) async {
    final phoneSizes = [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
    ];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in phoneSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));
      await tester.pump();

      expect(find.byTooltip('Cart'), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Overflow at $size');
    }
  });

  testWidgets('home hero carousel uses gesture and dot paging without arrows', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));

    expect(find.byKey(const Key('home-hero-carousel')), findsOneWidget);
    expect(find.byKey(const Key('home-hero-next')), findsNothing);
    expect(find.byKey(const Key('home-hero-previous')), findsNothing);

    await tester.drag(
      find.byKey(const Key('home-hero-carousel')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-hero-dot-0')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home categories are separate interactive tiles', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));

    expect(find.byKey(const Key('home-category-panel')), findsNothing);
    expect(find.text('For Her'), findsOneWidget);
    expect(find.text('For Him'), findsOneWidget);
    expect(find.text('Unisex'), findsOneWidget);
    expect(find.byKey(const Key('home-top-picks-section')), findsOneWidget);
    expect(find.text('Women'), findsNothing);
    expect(find.text('Men'), findsNothing);
    expect(find.text('Best Sellers'), findsNothing);

    final categoryImage = tester.getSize(
      find.byKey(const Key('home-category-image-for-her')),
    );
    expect(categoryImage.width, greaterThan(45));
    expect(categoryImage.height, greaterThan(45));

    final searchHint = tester.widget<Text>(
      find.text('Search scents, brands, or notes'),
    );
    expect(searchHint.style?.color, WireframeColors.muted);
  });

  testWidgets(
    'product cards keep the favorite control free of a circular fill',
    (WidgetTester tester) async {
      const product = Product(
        id: 'favorite-style-test',
        name: 'Favorite Style Test',
        brand: 'Scentify',
        price: 1500,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: product,
              onTap: () {},
              onAddToCart: () {},
              isFavorite: false,
              onFavorite: () {},
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ProductCard),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('section headings and body use modern sans typography', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.textTheme.bodyMedium?.fontFamily, 'Montserrat');
    expect(
      tester.widget<Text>(find.text('Shop by Category')).style?.fontFamily,
      'Montserrat',
    );
    expect(
      tester
          .widget<Text>(find.text('Search scents, brands, or notes'))
          .style
          ?.fontFamily,
      'Montserrat',
    );
  });

  test('Scentify themes provide distinct semantic light and dark roles', () {
    final light = ScentifyTheme.light().extension<ScentifyThemeColors>()!;
    final dark = ScentifyTheme.dark().extension<ScentifyThemeColors>()!;

    expect(light.canvas, ScentifyColors.background);
    expect(light.ink, ScentifyColors.ink);
    expect(dark.canvas, isNot(light.canvas));
    expect(dark.paper, isNot(light.paper));
    expect(dark.ink, isNot(light.ink));
    expect(dark.border, isNot(light.border));
    expect(light.copyWith(canvas: Colors.amber).canvas, Colors.amber);
    expect(light.lerp(dark, 0).canvas, light.canvas);
    expect(light.lerp(dark, 1).canvas, dark.canvas);
  });

  testWidgets('app defaults to light mode even when the system is dark', (
    WidgetTester tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.themeMode, ThemeMode.light);
    expect(app.darkTheme, isNotNull);
    final homeContext = tester.element(find.byType(HomePage));
    final darkColors = ScentifyThemeColors.of(homeContext);
    expect(Theme.of(homeContext).brightness, Brightness.light);
    expect(
      tester
          .widget<Scaffold>(
            find
                .descendant(
                  of: find.byType(HomePage),
                  matching: find.byType(Scaffold),
                )
                .first,
          )
          .backgroundColor,
      darkColors.canvas,
    );
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.backgroundColor, darkColors.paper);
    expect(navigation.indicatorColor, darkColors.selected);
    final productCard = find.byType(ProductCard).first;
    final cardContainer = tester.widget<Container>(
      find.descendant(of: productCard, matching: find.byType(Container)).first,
    );
    expect(
      (cardContainer.decoration as BoxDecoration).color,
      darkColors.canvas,
    );
  });

  testWidgets('saved theme mode is restored on the next launch', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'scentify.theme_mode': 'dark'});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MyApp(initialPage: ScentifyPage.home, launchPreferences: preferences),
    );

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('profile settings switch saves the selected theme', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MyApp(initialPage: ScentifyPage.profile, launchPreferences: preferences),
    );
    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-mode-switch')));
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(preferences.getString('scentify.theme_mode'), 'dark');
  });

  testWidgets('account settings screen opens and saves theme preference', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MyApp(initialPage: ScentifyPage.profile, launchPreferences: preferences),
    );
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-dark-mode')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(preferences.getString('scentify.theme_mode'), 'dark');
  });

  testWidgets('home category shortcuts open matching catalog filters', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> expectCategory({
      required String label,
      required String gender,
      required int count,
    }) async {
      await tester.pumpWidget(
        MyApp(key: ValueKey(label), initialPage: ScentifyPage.home),
      );
      await tester.pumpAndSettle();
      final category = find.text(label);
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();

      final filterFinder = find.descendant(
        of: find.byType(ScentifySelectableChip),
        matching: find.text(gender),
      );
      final filter = tester.widget<Text>(filterFinder);
      final filterContext = tester.element(filterFinder);
      expect(filter.style?.color, ScentifyThemeColors.of(filterContext).ink);
      expect(find.text('$count scents'), findsOneWidget);
    }

    await expectCategory(label: 'For Her', gender: 'Women', count: 22);
    await expectCategory(label: 'For Him', gender: 'Men', count: 15);
    await expectCategory(label: 'Unisex', gender: 'Unisex', count: 13);
  });

  testWidgets('home presents the full catalog as a discovery module', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-browse-catalog')), findsOneWidget);
    expect(find.text('Browse every scent'), findsOneWidget);
    expect(
      find.text('Explore all products with search, filters, and sorting.'),
      findsOneWidget,
    );
    expect(find.text('Shop all products'), findsOneWidget);
    expect(find.text('Find a scent that feels like you →'), findsNothing);

    tester
        .widget<WireButton>(find.byKey(const Key('home-browse-catalog-cta')))
        .onPressed!
        .call();
    await tester.pumpAndSettle();

    expect(find.text('Shop all scents'), findsOneWidget);
  });

  testWidgets('catalog search filters the product grid', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.catalog));

    await tester.enterText(
      find.byKey(const Key('catalog-search-input')),
      'Chanel',
    );
    await tester.pump();

    expect(find.text('Coco Mademoiselle Eau de Parfum'), findsOneWidget);
    expect(find.text('Product Name'), findsNothing);
    expect(find.byTooltip('Filters'), findsOneWidget);
    expect(find.text('Filters ▾'), findsNothing);
  });

  testWidgets('home search opens shop without a trailing arrow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));
    final homeSearch = find.byKey(const Key('home-search-bar'));

    expect(
      find.descendant(
        of: homeSearch,
        matching: find.byIcon(Icons.arrow_forward_rounded),
      ),
      findsNothing,
    );

    await tester.tap(homeSearch);
    await tester.pumpAndSettle();

    expect(find.text('Shop all scents'), findsOneWidget);
  });

  testWidgets('catalog refreshes when the live repository changes', (
    WidgetTester tester,
  ) async {
    final initial = additionalCatalogSeed.first.copyWith(
      id: 'live-initial',
      name: 'Live Initial Scent',
    );
    final repository = InMemoryCatalogRepository([initial]);

    await tester.pumpWidget(
      MyApp(
        initialPage: ScentifyPage.catalog,
        catalogRepository: repository,
        initialCatalogProducts: [Product.fromPerfume(initial)],
      ),
    );
    await tester.pump();

    expect(find.text('Live Initial Scent'), findsOneWidget);

    final added = additionalCatalogSeed[1].copyWith(
      id: 'live-added',
      name: 'Live Added Scent',
    );
    await repository.save(added);
    await tester.pumpAndSettle();

    expect(find.text('Live Added Scent'), findsOneWidget);
  });

  testWidgets('cart quantity changes persist through the cart repository', (
    WidgetTester tester,
  ) async {
    final perfume = additionalCatalogSeed.first;
    final variant = perfume.variants.first;
    final cart = Cart(
      userId: 'customer-1',
      updatedAt: DateTime.utc(2026, 1, 1),
      items: [
        CartItem(
          productId: perfume.id,
          variantId: variant.id,
          productName: perfume.name,
          variantLabel: variant.label,
          unitPrice: Money(variant.price.centavos),
          quantity: 1,
        ),
      ],
    );
    final carts = InMemoryCartRepository();
    await carts.save(cart);

    await tester.pumpWidget(
      MyApp(
        initialPage: ScentifyPage.cart,
        customerId: 'customer-1',
        catalogRepository: InMemoryCatalogRepository([perfume]),
        cartRepository: carts,
        initialCatalogProducts: [Product.fromPerfume(perfume)],
        initialCart: cart,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pumpAndSettle();

    expect((await carts.findByUserId('customer-1'))!.items.single.quantity, 2);
  });

  testWidgets('product favorite persists in the customer wishlist', (
    WidgetTester tester,
  ) async {
    final perfume = additionalCatalogSeed.first;
    final wishlists = InMemoryWishlistRepository();

    await tester.pumpWidget(
      MyApp(
        initialPage: ScentifyPage.product,
        customerId: 'customer-1',
        catalogRepository: InMemoryCatalogRepository([perfume]),
        initialCatalogProducts: [Product.fromPerfume(perfume)],
        wishlistRepository: wishlists,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Wishlist'));
    await tester.pumpAndSettle();

    expect(await wishlists.findByUserId('customer-1'), {perfume.id});
  });

  testWidgets('wishlist renders the persisted live catalog item', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final perfume = additionalCatalogSeed.first;
    final wishlists = InMemoryWishlistRepository();
    await wishlists.save('customer-1', {perfume.id});

    await tester.pumpWidget(
      MyApp(
        initialPage: ScentifyPage.wishlist,
        customerId: 'customer-1',
        catalogRepository: InMemoryCatalogRepository([perfume]),
        initialCatalogProducts: [Product.fromPerfume(perfume)],
        wishlistRepository: wishlists,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    expect(find.text(perfume.name), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('account tab and edit dialog cancel safely', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(
        key: ValueKey('profile-back-button-check'),
        initialPage: ScentifyPage.profile,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My account'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('My account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile edit retains invalid input and saves a corrected name on done',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = InMemoryUserProfileRepository();
      final profile = UserProfile(
        id: 'customer-profile-name-limit',
        email: 'ava@example.com',
        displayName: 'Ava Santos',
        role: UserRole.customer,
        createdAt: DateTime(2026, 10, 1),
      );
      await tester.pumpWidget(
        MyApp(
          initialPage: ScentifyPage.profile,
          customerId: profile.id,
          initialUserProfile: profile,
          userProfileRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      final originalProfile = await repository.findById(profile.id);

      await tester.tap(find.byKey(const Key('profile-edit-button')));
      await tester.pumpAndSettle();
      final nameField = find.byKey(const Key('profile-display-name-input'));
      final controller = tester.widget<TextField>(nameField).controller!;
      final overlongName = List.filled(121, 'A').join();
      controller.text = overlongName;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Name must be 120 characters or fewer.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(controller.text, overlongName);
      expect(await repository.findById(profile.id), originalProfile);

      await tester.enterText(nameField, 'Ava Rivera');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        (await repository.findById(profile.id))?.displayName,
        'Ava Rivera',
      );
    },
  );

  testWidgets('profile reflects real-time repository updates', (
    WidgetTester tester,
  ) async {
    final repository = InMemoryUserProfileRepository();
    final profile = UserProfile(
      id: 'customer-1',
      email: 'ava@example.com',
      displayName: 'Ava Santos',
      role: UserRole.customer,
      createdAt: DateTime(2026, 10, 1),
    );

    await tester.pumpWidget(
      MyApp(
        initialPage: ScentifyPage.profile,
        customerId: profile.id,
        initialUserProfile: profile,
        userProfileRepository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ava Santos'), findsOneWidget);

    await repository.save(profile.copyWith(displayName: 'Ava Rivera'));
    await tester.pump();

    expect(find.text('Ava Rivera'), findsOneWidget);
    expect(find.text('Ava Santos'), findsNothing);
  });

  testWidgets('cancelling profile edit closes cleanly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.profile));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center marks updates read and opens an order', (
    WidgetTester tester,
  ) async {
    final notification = ScentifyNotification(
      id: 'notification-order-1',
      title: 'Order on the way',
      body: 'Your order is moving to your address.',
      createdAt: DateTime(2026, 1, 1, 12),
      orderId: 'order-1',
    );
    final readIds = <String>{};
    String? openedId;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => NotificationsPage(
            notifications: [notification],
            readNotificationIds: readIds,
            onBack: () {},
            onMarkAllRead: () => setState(() => readIds.add(notification.id)),
            onOpen: (value) => openedId = value.id,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('notifications-page')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('notifications-mark-all')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('notifications-mark-all')))
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('notification-notification-order-1')),
    );
    expect(openedId, 'notification-order-1');
  });

  testWidgets('order monitor shows progress, items, and delivery details', (
    WidgetTester tester,
  ) async {
    final order = Order(
      id: 'order-monitor-1',
      userId: 'customer-1',
      items: [
        OrderItemSnapshot(
          productId: 'seed-001',
          variantId: 'seed-001-50',
          productName: 'Chance Eau Tendre',
          variantLabel: '50ml',
          unitPrice: Money(8600),
          quantity: 1,
        ),
      ],
      shippingAddress: ShippingAddress(
        fullName: 'Juan Dela Cruz',
        phoneNumber: '09171234567',
        addressLine1: '123 Mabini Street',
        barangay: 'Barangay 1',
        city: 'Quezon City',
        province: 'Metro Manila',
        postalCode: '1100',
      ),
      deliveryOption: DeliveryOption(
        id: 'standard',
        name: 'Standard Delivery',
        fee: Money(8000),
        estimatedDays: '3-5 business days',
      ),
      subtotal: Money(8600),
      deliveryFee: Money(8000),
      total: Money(16600),
      status: OrderStatus.shipped,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: TrackingPage(order: order, onBack: () {}),
      ),
    );

    expect(find.byKey(const Key('tracking-page')), findsOneWidget);
    expect(find.byKey(const Key('tracking-status-card')), findsOneWidget);
    expect(find.byKey(const Key('order-status-shipped')), findsOneWidget);
    expect(find.text('Order progress'), findsOneWidget);
    expect(find.text('Items (1)'), findsOneWidget);
    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('Invoice number'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Quezon City'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('order-monitor-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('Quezon City'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout requires a complete shipping address', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(initialPage: ScentifyPage.checkoutAddress),
    );

    final action = find.text('Continue to Delivery');
    final actionRect = tester.getRect(action);
    final pageRect = tester.getRect(find.byType(Scaffold).first);
    expect(actionRect.bottom, lessThanOrEqualTo(pageRect.bottom));

    await tester.tap(action);
    await tester.pump();

    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Select Delivery Option'), findsNothing);
  });

  testWidgets('checkout creates an order and clears the cart', (
    WidgetTester tester,
  ) async {
    final perfume = additionalCatalogSeed.first;
    final variant = perfume.variants.first;
    final cart = Cart(
      userId: 'customer-1',
      updatedAt: DateTime.utc(2026, 1, 1),
      items: [
        CartItem(
          productId: perfume.id,
          variantId: variant.id,
          productName: perfume.name,
          variantLabel: variant.label,
          unitPrice: variant.price,
          quantity: 1,
        ),
      ],
    );
    final carts = InMemoryCartRepository();
    final orders = InMemoryOrderRepository();
    await carts.save(cart);

    await tester.pumpWidget(
      MyApp(
        initialPage: ScentifyPage.cart,
        customerId: 'customer-1',
        catalogRepository: InMemoryCatalogRepository([perfume]),
        initialCatalogProducts: [Product.fromPerfume(perfume)],
        cartRepository: carts,
        initialCart: cart,
        orderRepository: orders,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Select ${perfume.name}'));
    await tester.pump();
    await tester.tap(find.text('Checkout (1)'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    const values = [
      'Juan Dela Cruz',
      '09171234567',
      '123 Mabini Street',
      'Metro Manila',
      'Quezon City',
      'Barangay 1',
      '1100',
    ];
    for (var index = 0; index < values.length; index++) {
      await tester.enterText(fields.at(index), values[index]);
    }
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    expect(find.text('Continue to Review'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('address-form')), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Juan Dela Cruz',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
      '123 Mabini Street',
    );
    await tester.tap(find.text('Continue to Delivery'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue to Review'));
    await tester.pumpAndSettle();
    expect(find.text('GCash'), findsNothing);
    expect(find.text('Maya'), findsNothing);
    expect(find.text('Credit / Debit Card'), findsNothing);
    await tester.scrollUntilVisible(
      find.byTooltip('Agree to Terms and Conditions'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Cash on Delivery'), findsOneWidget);
    await tester.tap(find.byTooltip('Agree to Terms and Conditions'));
    await tester.pump();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    expect(find.text('Order Request Sent'), findsOneWidget);
    final placedOrders = await orders.forUser('customer-1');
    expect(placedOrders, hasLength(1));
    expect(placedOrders.single.status, OrderStatus.pendingConfirmation);
    expect(placedOrders.single.paymentMethod, 'cod');
    expect(await carts.findByUserId('customer-1'), isNull);
  });

  testWidgets('catalog search aligns its hint and icon vertically', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.catalog));

    final fieldRect = tester.getRect(
      find.byKey(const Key('catalog-search-input')),
    );
    final hintRect = tester.getRect(
      find.text('Search scents, brands, or notes'),
    );
    final iconRect = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('catalog-search-input')),
        matching: find.byIcon(Icons.search_rounded),
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('catalog-search-input')),
        matching: find.byIcon(Icons.arrow_forward_rounded),
      ),
      findsNothing,
    );

    expect(fieldRect.height, 46);
    expect((hintRect.center.dy - fieldRect.center.dy).abs(), lessThan(5));
    expect((iconRect.center.dy - fieldRect.center.dy).abs(), lessThan(5));
    expect((hintRect.center.dy - iconRect.center.dy).abs(), lessThan(5));
  });

  testWidgets('catalog category chips filter products', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.catalog));
    await tester.tap(find.text('Women'));
    await tester.pump();

    expect(find.text('Coco Mademoiselle Eau de Parfum'), findsOneWidget);
    expect(find.text('Flora Gorgeous Gardenia'), findsOneWidget);
    expect(find.text('Sauvage Eau de Toilette'), findsNothing);
  });

  testWidgets('catalog sort control changes product order', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.catalog));
    await tester.tap(find.byKey(const Key('catalog-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price: high to low'));
    await tester.pumpAndSettle();

    final mostExpensive = tester.getRect(
      find.text('Baccarat Rouge 540 Eau de Parfum'),
    );
    final firstProduct = tester.getRect(find.text('Santal 33 Eau de Parfum'));
    expect(mostExpensive.top, lessThan(firstProduct.top));
  });

  testWidgets('catalog product rows keep a compact visual rhythm', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.catalog));

    final firstPrice = tester.getRect(
      find.byKey(const Key('catalog-product-price-0')),
    );
    final thirdImage = tester.getRect(
      find.byKey(const Key('catalog-product-image-2')),
    );

    expect(thirdImage.top - firstPrice.bottom, lessThan(120));
  });

  testWidgets('catalog product tap opens its variant-aware quick view', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.catalog));
    await tester.tap(find.text('Coco Mademoiselle Eau de Parfum'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-quick-view')), findsOneWidget);
    expect(find.byKey(const Key('product-detail-page')), findsNothing);
    expect(find.text('Quick view'), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Choose a size'), findsOneWidget);
  });

  testWidgets(
    'quick view add to cart stays on home and updates the cart count',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.home));
      await tester.scrollUntilVisible(
        find.text('Coco Mademoiselle Eau de Parfum'),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      await tester.tap(find.text('Coco Mademoiselle Eau de Parfum'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-view-add-to-cart')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('product-quick-view')), findsNothing);
      expect(find.byKey(const Key('home-browse-catalog')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('cart-count-badge')),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
      expect(find.text('Added to cart'), findsOneWidget);
      expect(find.text('My Cart (4)'), findsNothing);
    },
  );

  testWidgets('Top Picks cart action asks for a variant before adding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.topPicks));

    await tester.tap(
      find.byTooltip('Add Coco Mademoiselle Eau de Parfum to cart'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-quick-view')), findsOneWidget);
    expect(find.text('Choose a size'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quick-view-add-to-cart')));
    await tester.pumpAndSettle();

    expect(find.text('Added to cart'), findsOneWidget);
  });

  testWidgets('quick view uses the selected available variant', (
    WidgetTester tester,
  ) async {
    String? addedVolume;
    const product = Product(
      id: 'variant-product',
      name: 'Variant Test Scent',
      brand: 'Scentify',
      price: 1500,
      volume: '50ml',
      availableVolumes: ['50ml', '100ml', '150ml'],
      pricesByVolume: {'50ml': 1500, '100ml': 2500, '150ml': 3500},
      variantIdsByVolume: {
        '50ml': 'variant-50',
        '100ml': 'variant-100',
        '150ml': 'variant-150',
      },
      stockByVolume: {'50ml': 0, '100ml': 4, '150ml': 0},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductQuickView(
            product: product,
            onAddToCart: (volume) => addedVolume = volume,
            onViewDetails: () {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const Key('quick-view-selected-price')))
          .data,
      '₱2,500',
    );
    expect(find.text('Out of stock'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('product-quick-size-50ml')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('quick-view-selected-price')))
          .data,
      '₱2,500',
    );

    await tester.tap(find.byKey(const Key('quick-view-add-to-cart')));
    expect(addedVolume, '100ml');
  });

  testWidgets('out-of-stock product variants disable purchase actions', (
    WidgetTester tester,
  ) async {
    const product = Product(
      id: 'sold-out-product',
      name: 'Sold Out Test Scent',
      brand: 'Scentify',
      price: 1500,
      volume: '50ml',
      availableVolumes: ['50ml'],
      stockByVolume: {'50ml': 0},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProductPage(
          product: product,
          isFavorite: false,
          onBack: () {},
          onFavorite: () {},
          onAddToCart: (_, _) {},
        ),
      ),
    );

    expect(find.text('Out of stock'), findsOneWidget);
    expect(
      tester
          .widget<WireButton>(find.byKey(const Key('product-add-to-cart')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('product image carousel supports multiple catalog images', (
    WidgetTester tester,
  ) async {
    const product = Product(
      id: 'gallery-product',
      name: 'Coco Mademoiselle Eau de Parfum',
      brand: 'Chanel',
      price: 8900,
      imageUrls: ['https://example.com/coco-side.png'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductImageCarousel(product: product, imageSize: 204),
        ),
      ),
    );

    expect(find.byKey(const Key('product-image-carousel')), findsOneWidget);
    expect(find.byKey(const Key('product-image-dot-1')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('product-image-next')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('product-image-next')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PlaceholderImage>(
            find.byKey(const ValueKey('product-image-page-1')),
          )
          .assetPath,
      isNull,
      reason: 'A remote gallery page must not repeat the local cover image.',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('product-image-next')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('product detail prioritizes purchase controls and clear details', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int? addedQuantity;
    String? addedVolume;

    const detailedProduct = Product(
      id: 'detail-product',
      name: 'Coco Mademoiselle Eau de Parfum',
      brand: 'Chanel',
      price: 8900,
      volume: '50ml',
      description: 'A bright amber floral with citrus, rose, and a warm patchouli finish.',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProductPage(
          product: detailedProduct,
          isFavorite: false,
          onBack: () {},
          onFavorite: () {},
          onAddToCart: (quantity, volume) {
            addedQuantity = quantity;
            addedVolume = volume;
          },
        ),
      ),
    );

    expect(find.byKey(const Key('product-detail-page')), findsOneWidget);
    expect(find.byKey(const Key('product-purchase-bar')), findsOneWidget);
    expect(find.text('Choose a size'), findsOneWidget);
    expect(find.text('Top Notes'), findsOneWidget);
    expect(find.text('Bergamot · Mandarin'), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-size-100ml')));
    await tester.tap(find.byKey(const Key('product-quantity-increment')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('product-quantity-value'))).data,
      '2',
    );

    await tester.drag(find.byType(ListView).last, const Offset(0, -360));
    await tester.pump();
    await tester.tap(find.byKey(const Key('product-about-toggle')));
    await tester.pump();
    expect(
      find.text(
        'A bright amber floral with citrus, rose, and a warm patchouli finish.',
      ),
      findsNWidgets(2),
    );

    await tester.drag(find.byType(ListView).last, const Offset(0, -260));
    await tester.pump();
    await tester.tap(find.byKey(const Key('product-reviews-toggle')));
    await tester.pump();
    expect(find.text('No verified reviews yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('product-add-to-cart')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('product-detail-page')), findsOneWidget);
    expect(addedQuantity, 2);
    expect(addedVolume, '100ml');
  });

  testWidgets('product detail fits common phone heights without overflow', (
    WidgetTester tester,
  ) async {
    final phoneSizes = [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
      const Size(412, 915),
    ];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in phoneSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.product));
      await tester.pump();

      expect(find.byKey(const Key('product-purchase-bar')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Overflow at $size');
    }
  });

  testWidgets('onboarding anchors skip and next actions around the artwork', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.onboarding));

    final nextRect = tester.getRect(find.byKey(const Key('onboarding-next')));
    final skipRect = tester.getRect(find.text('Skip'));
    final imageCenter = tester
        .getCenter(find.byKey(const Key('onboarding-hero-art')))
        .dy;

    expect(skipRect.bottom, lessThan(nextRect.top));
    expect(imageCenter, lessThan(500));
  });

  testWidgets('login fits common phone heights without scrolling', (
    WidgetTester tester,
  ) async {
    final phoneSizes = [
      const Size(320, 568),
      const Size(360, 640),
      const Size(390, 844),
      const Size(412, 915),
    ];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in phoneSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));
      await tester.pump();

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Overflow at $size');
    }
  });

  testWidgets(
    'login does not become scrollable when the keyboard reduces the viewport',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));
      await tester.pump();

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard keeps the focused login field active without scrolling',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));
      await tester.tap(find.byKey(const Key('auth-email')));
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      await tester.pump();

      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard does not compress the login layout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2700);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));
    await tester.pump();

    final initialFormRect = tester.getRect(find.byKey(const Key('auth-form')));
    await tester.tap(find.byKey(const Key('auth-email')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pump();

    final keyboardFormRect = tester.getRect(find.byKey(const Key('auth-form')));
    expect(keyboardFormRect.height, closeTo(initialFormRect.height, 0.1));
    expect(keyboardFormRect.width, closeTo(initialFormRect.width, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login uses the bottom create account action for registration', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));

    expect(find.text('Register'), findsNothing);
    expect(find.text('Create account'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('password visibility control reveals and hides the password', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));

    final passwordField = find.byType(TextField).last;
    await tester.enterText(passwordField, 'secret123');
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(tester.widget<TextField>(passwordField).obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);
  });

  testWidgets(
    'register rejects names above 120 characters before auth submit',
    (WidgetTester tester) async {
      var submitted = false;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AuthPage(
            onSubmit:
                ({
                  required bool register,
                  String? displayName,
                  required String email,
                  required String password,
                }) async {
                  submitted = true;
                },
            onGoogleSignIn: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        List.filled(121, 'A').join(),
      );
      await tester.enterText(find.byType(TextField).at(1), 'juan@example.com');
      await tester.enterText(find.byType(TextField).at(2), 'secret123');
      await tester.enterText(find.byType(TextField).at(3), 'secret123');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('Full name must be 120 characters or fewer.'),
        findsOneWidget,
      );
      expect(submitted, isFalse);
    },
  );

  testWidgets('register validates matching confirmation password', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Confirm Password'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Ian Gabriel Tongol');
    await tester.enterText(find.byType(TextField).at(1), 'ian@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'secret123');
    await tester.enterText(find.byType(TextField).at(3), 'different123');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('register fits short phones with scrolling', (
    WidgetTester tester,
  ) async {
    final phoneSizes = [const Size(320, 568), const Size(390, 844)];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in phoneSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MyApp(initialPage: ScentifyPage.auth));
      await tester.tap(find.text('Create account'));
      await tester.pump();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pump();

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Overflow at $size');
    }
  });
}
