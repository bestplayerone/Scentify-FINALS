import 'package:flutter/material.dart';
import 'package:scentify/main.dart' as scentify;
import 'package:scentify/ui/scentify_design_system.dart' as design;

const _reviewPageName = String.fromEnvironment('SCENTIFY_REVIEW_PAGE');
const _reviewTextScale = String.fromEnvironment('SCENTIFY_REVIEW_TEXT_SCALE');

void main() {
  final reviewPage = switch (_reviewPageName) {
    'checkout' => scentify.ScentifyPage.checkoutAddress,
    'tracking' => scentify.ScentifyPage.tracking,
    'product' => scentify.ScentifyPage.product,
    _ => scentify.ScentifyPage.home,
  };
  final textScale = double.tryParse(_reviewTextScale) ?? 1;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: design.ScentifyTheme.light(),
      darkTheme: design.ScentifyTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: scentify.ScentifyApp(initialPage: reviewPage),
    ),
  );
}
