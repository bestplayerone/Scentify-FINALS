import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scentify/main.dart';
import 'package:scentify/ui/scentify_design_system.dart';

Widget _reviewHost(
  Widget child, {
  bool dark = false,
  double textScale = 1,
  double width = 358,
}) {
  final theme = dark ? ScentifyTheme.dark() : ScentifyTheme.light();
  return MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            widthFactor: 1,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('section heading uses the active theme ink', (tester) async {
    await tester.pumpWidget(
      _reviewHost(
        const ScentifySectionHeader(title: 'Featured brands'),
        dark: true,
      ),
    );
    final context = tester.element(find.text('Featured brands'));
    final text = tester.widget<Text>(find.text('Featured brands'));
    final effectiveColor = DefaultTextStyle.of(context).style
        .merge(text.style)
        .color;
    expect(effectiveColor, ScentifyThemeColors.of(context).ink);
  });

  testWidgets('category labels use the active theme ink', (tester) async {
    await tester.pumpWidget(
      _reviewHost(
        const CategoryShortcut(label: 'For Her', onTap: _noop),
        dark: true,
        width: 78,
      ),
    );
    final context = tester.element(find.text('For Her'));
    final text = tester.widget<Text>(find.text('For Her'));
    expect(text.style?.color, ScentifyThemeColors.of(context).ink);
  });

  testWidgets('featured brand logos retain their aspect ratio', (tester) async {
    const logoSizes = {
      'Chanel': Size(42, 24),
      'Dior': Size(44, 20),
      'YSL': Size(30, 28),
      'Gucci': Size(44, 18),
      'Versace': Size(34, 28),
    };
    const logoAssets = {
      'Chanel': 'assets/images/brands/chanel.png',
      'Dior': 'assets/images/brands/dior_display.png',
      'YSL': 'assets/images/brands/ysl.png',
      'Gucci': 'assets/images/brands/gucci_display.png',
      'Versace': 'assets/images/brands/versace_display.png',
    };
    for (final entry in logoSizes.entries) {
      final label = entry.key;
      await tester.pumpWidget(_reviewHost(BrandTile(label: label), width: 160));
      await tester.pumpAndSettle(const Duration(milliseconds: 20));

      final logoFinder = find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == '$label logo',
      );
      final logo = tester.widget<Image>(logoFinder);
      expect(logo.fit, BoxFit.contain);
      expect(logo.width, entry.value.width);
      expect(logo.height, entry.value.height);
      expect((logo.image as AssetImage).assetName, logoAssets[label]);
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  testWidgets('featured brand carousel peeks, scrolls, and fits phones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0, 430.0]) {
      await tester.binding.setSurfaceSize(Size(width, 844));
      await tester.pumpWidget(
        _reviewHost(
          SizedBox(
            height: 112,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                BrandTile(label: 'Chanel'),
                BrandTile(label: 'Dior'),
                BrandTile(label: 'YSL'),
                BrandTile(label: 'Gucci'),
                BrandTile(label: 'Versace'),
              ],
            ),
          ),
          width: width - 32,
        ),
      );

      if (width == 320) {
        final viewport = tester.getRect(find.byType(ListView));
        final lastCard = tester.getRect(find.byType(BrandTile).at(4));
        expect(lastCard.left, lessThan(viewport.right));
        expect(lastCard.right, greaterThan(viewport.right));

        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final offset = scrollable.position.pixels;
        await tester.drag(find.byType(ListView), const Offset(-120, 0));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(offset));
      }
      expect(tester.takeException(), isNull, reason: '$width logical pixels');
    }
  });

  testWidgets('featured brand logo marks adapt to dark mode', (tester) async {
    await tester.pumpWidget(
      _reviewHost(const BrandTile(label: 'YSL'), dark: true, width: 160),
    );
    final context = tester.element(find.byType(BrandTile));
    final logo = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'YSL logo',
      ),
    );
    expect(logo.color, ScentifyThemeColors.of(context).ink);
    expect(logo.colorBlendMode, BlendMode.srcIn);
  });

  testWidgets('search has one themed boundary in light and dark modes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _reviewHost(
          WireSearchInput(
            key: const Key('wire-search-input'),
            inputKey: const Key('search-field'),
            controller: controller,
            hint: 'Search scents',
            onChanged: _noopText,
          ),
          dark: dark,
          width: 358,
        ),
      );
      final context = tester.element(find.byKey(const Key('search-field')));
      final colors = ScentifyThemeColors.of(context);
      final decoration = tester
          .widget<TextField>(find.byKey(const Key('search-field')))
          .decoration!
          .applyDefaults(Theme.of(context).inputDecorationTheme);

      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.disabledBorder, InputBorder.none);
      expect(decoration.errorBorder, InputBorder.none);
      expect(decoration.focusedErrorBorder, InputBorder.none);
      expect(
        (tester
                    .widget<AnimatedContainer>(
                      find.byKey(const Key('wire-search-input-shell')),
                    )
                    .decoration
                as BoxDecoration)
            .border
            ?.top
            .color,
        colors.border,
      );

      await tester.tap(find.byKey(const Key('search-field')));
      await tester.pump();
      final focusedShell = tester.widget<AnimatedContainer>(
        find.byKey(const Key('wire-search-input-shell')),
      );
      expect(
        (focusedShell.decoration as BoxDecoration).border?.top.color,
        colors.primaryAction,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('category imagery has room to breathe without an inner tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _reviewHost(const CategoryShortcut(label: 'For Her', onTap: _noop)),
    );

    expect(
      tester
          .getSize(find.byKey(const Key('home-category-image-for-her')))
          .width,
      greaterThanOrEqualTo(64),
    );
  });

  testWidgets('service labels stay legible at larger text sizes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _reviewHost(const HomeServiceStrip(), textScale: 2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero artwork stays in the right side on phone widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeHeroCarousel(
            cartCount: 0,
            notificationCount: 0,
            onCart: _noop,
            onNotifications: _noop,
            onBrowse: _noop,
            onTopPicks: _noop,
            showChrome: false,
          ),
        ),
      ),
    );
    final pageWidth = tester
        .getSize(find.byKey(const Key('home-hero-carousel')))
        .width;
    final artworkWidth = tester
        .getSize(find.byKey(const Key('home-hero-artwork-0')))
        .width;
    expect(artworkWidth, lessThan(pageWidth * 0.5));
  });

  testWidgets('hero layers editorial campaign imagery behind its content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeHeroCarousel(
            cartCount: 0,
            notificationCount: 0,
            onCart: _noop,
            onNotifications: _noop,
            onBrowse: _noop,
            onTopPicks: _noop,
            showChrome: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('home-hero-backdrop-0')), findsOneWidget);
  });

  testWidgets('home hero uses a compact campaign-banner height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeHeroCarousel(
            cartCount: 0,
            notificationCount: 0,
            onCart: _noop,
            onNotifications: _noop,
            onBrowse: _noop,
            onTopPicks: _noop,
            showChrome: false,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('home-hero-carousel'))).height,
      lessThanOrEqualTo(280),
    );
  });

  testWidgets('hero grows to honor larger text without clipping', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _reviewHost(
        const HomeHeroCarousel(
          cartCount: 0,
          notificationCount: 0,
          onCart: _noop,
          onNotifications: _noop,
          onBrowse: _noop,
          onTopPicks: _noop,
          showChrome: false,
        ),
        textScale: 2,
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('home-hero-carousel'))).height,
      lessThanOrEqualTo(400),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('header icon actions remain legible in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _reviewHost(
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            CartIconButton(count: 2, onPressed: _noop),
            NotificationIconButton(count: 1, onPressed: _noop),
          ],
        ),
        dark: true,
      ),
    );
    final cartContext = tester.element(find.byType(CartIconButton));
    final darkColors = ScentifyThemeColors.of(cartContext);
    final cartControl = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(CartIconButton),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(cartControl.decoration, isNull);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.shopping_bag_outlined)).color,
      darkColors.ink,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.notifications_none)).color,
      darkColors.ink,
    );
  });

  testWidgets('rating text follows the active dark theme', (tester) async {
    await tester.pumpWidget(
      _reviewHost(
        const ScentifyRatingRow(rating: 4.8, reviewCount: 12),
        dark: true,
      ),
    );

    final context = tester.element(find.text('4.8'));
    expect(
      tester.widget<Text>(find.text('4.8')).style?.color,
      ScentifyThemeColors.of(context).ink,
    );
  });
}

void _noop() {}

void _noopText(String _) {}
