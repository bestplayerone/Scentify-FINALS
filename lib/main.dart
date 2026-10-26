import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scentify/core/addresses/address_autocomplete_api.dart';
import 'package:scentify/core/errors/app_exception.dart';
import 'package:scentify/core/supabase/supabase_bootstrap.dart';
import 'package:scentify/core/inventory/inventory_service.dart';
import 'package:scentify/core/inventory/admin_inventory_service.dart';
import 'package:scentify/core/orders/order_review_api.dart';
import 'package:scentify/core/models/money.dart';
import 'package:scentify/core/notifications/notification_service.dart';
import 'package:scentify/features/auth/data/supabase_auth_repository.dart';
import 'package:scentify/features/auth/data/supabase_user_profile_repository.dart';
import 'package:scentify/features/auth/data/firebase_auth_repository.dart';
import 'package:scentify/features/auth/data/in_memory_user_profile_repository.dart';
import 'package:scentify/features/auth/domain/auth_error_messages.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/auth/domain/repositories/user_profile_repository.dart';
import 'package:scentify/features/cart/data/supabase_cart_repository.dart';
import 'package:scentify/features/cart/data/firestore_cart_repository.dart';
import 'package:scentify/features/cart/data/in_memory_cart_repository.dart';
import 'package:scentify/features/cart/domain/models/cart.dart';
import 'package:scentify/features/cart/domain/repositories/cart_repository.dart';
import 'package:scentify/features/cart/domain/services/cart_service.dart';
import 'package:scentify/features/catalog/data/catalog_seed.dart';
import 'package:scentify/features/catalog/data/firestore_product_review_repository.dart';
import 'package:scentify/features/catalog/data/in_memory_product_review_repository.dart';
import 'package:scentify/features/catalog/data/firestore_catalog_repository.dart';
import 'package:scentify/features/catalog/data/in_memory_catalog_repository.dart';
import 'package:scentify/features/catalog/data/supabase_catalog_repository.dart';
import 'package:scentify/features/catalog/data/firestore_catalog_repository.dart';
import 'package:scentify/features/catalog/data/firestore_product_review_repository.dart';
import 'package:scentify/features/catalog/domain/models/perfume.dart';
import 'package:scentify/features/catalog/domain/models/product_review.dart';
import 'package:scentify/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:scentify/features/catalog/domain/repositories/product_review_repository.dart';
import 'package:scentify/features/checkout/data/firestore_saved_address_repository.dart';
import 'package:scentify/features/checkout/data/in_memory_saved_address_repository.dart';
import 'package:scentify/features/checkout/data/sandbox_payment_gateway.dart';
import 'package:scentify/features/checkout/data/paymongo_payment_gateway.dart';
import 'package:scentify/features/checkout/data/supabase_checkout.dart';
import 'package:scentify/features/checkout/data/firestore_saved_address_repository.dart';
import 'package:scentify/features/checkout/domain/models/delivery_option.dart';
import 'package:scentify/features/checkout/domain/models/saved_address.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/repositories/saved_address_repository.dart';
import 'package:scentify/features/checkout/domain/services/checkout_service.dart';
import 'package:scentify/features/orders/data/supabase_order_repository.dart';
import 'package:scentify/features/orders/data/firestore_order_repository.dart';
import 'package:scentify/features/orders/data/in_memory_order_repository.dart';
import 'package:scentify/features/orders/domain/models/order.dart';
import 'package:scentify/features/orders/domain/repositories/order_repository.dart';
import 'package:scentify/features/orders/domain/services/admin_order_service.dart';
import 'package:scentify/features/wishlist/data/firestore_wishlist_repository.dart';
import 'package:scentify/features/wishlist/data/in_memory_wishlist_repository.dart';
import 'package:scentify/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:scentify/features/wishlist/domain/services/wishlist_service.dart';
import 'package:scentify/ui/scentify_breakpoints.dart';
import 'package:scentify/ui/scentify_design_system.dart';

const _hasSeenOnboardingPreferenceKey = 'scentify.has_seen_onboarding';
const _themeModePreferenceKey = 'scentify.theme_mode';
const _modernFontFamily = ScentifyTypography.fontFamily;
const _maxProfileNameLength = 120;
const _useXendit = bool.fromEnvironment('SCENTIFY_XENDIT_ENABLED');
const _useSupabase = bool.fromEnvironment(
  'SCENTIFY_SUPABASE_ENABLED',
  defaultValue: true,
);
String resolveProfileDisplayName({
  String? displayName,
  String? existingName,
  required String userId,
  required String fallbackName,
}) {
  final candidate = displayName?.trim();
  if (candidate != null &&
      candidate.isNotEmpty &&
      candidate.length <= _maxProfileNameLength) {
    return candidate;
  }
  final existing = existingName?.trim();
  if (existing != null &&
      existing.isNotEmpty &&
      existing != userId &&
      existing.length <= _maxProfileNameLength) {
    return existing;
  }
  final fallback = fallbackName.trim();
  return fallback.isNotEmpty && fallback.length <= _maxProfileNameLength
      ? fallback
      : 'Scentify Customer';
}

String? normalizePhilippineMobileNumber(String value) {
  final phoneNumber = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^09\d{9}$').hasMatch(phoneNumber)) {
    return '+63${phoneNumber.substring(1)}';
  }
  if (RegExp(r'^\+639\d{9}$').hasMatch(phoneNumber)) {
    return phoneNumber;
  }
  return null;
}

String savedAddressErrorMessage(Object error) {
  if (error is AppException) return error.message;
  if (error is FirebaseException) {
    return switch (error.code) {
      'unauthenticated' => 'Sign in again to save to My Addresses. You can still continue checkout.',
      'permission-denied' => 'Your account could not save this address. You can still continue checkout and retry later.',
      'unavailable' || 'deadline-exceeded' => 'My Addresses is temporarily unavailable. You can still continue checkout and retry later.',
      'invalid-argument' || 'failed-precondition' => 'My Addresses rejected some details. Review the address and try saving again; you can still continue checkout.',
      _ => 'We could not save to My Addresses. You can still continue checkout and retry later.',
    };
  }
  return 'We could not save to My Addresses. You can still continue checkout and retry later.';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeScentifySupabase();
  final launchPreferences = await SharedPreferences.getInstance();
  final authRepository = SupabaseAuthRepository();
  var restoredUser = await authRepository.restoredUser;
  var restoredClaimRole = UserRole.customer;
  if (restoredUser != null) {
    try {
      restoredClaimRole = await authRepository.claimRole(
        user: restoredUser,
        forceRefresh: true,
      );
    } on Object {
      // The profile document remains the normal role source if the token is
      // temporarily unavailable during app startup.
    }
  }
  final UserProfileRepository? userProfileRepository = SupabaseUserProfileRepository();
  final SavedAddressRepository? savedAddressRepository = null;
  final AddressAutocompleteProvider? addressAutocompleteProvider = null;
  final ProductReviewRepository? productReviewRepository = null;
  UserProfile? restoredProfile;
  if (restoredUser != null && userProfileRepository != null) {
    try {
      restoredProfile = await userProfileRepository.findById(restoredUser.id);
    } on Object {
      // A profile lookup must not prevent a restored Auth session from opening.
    }
  }
  final restoredRole =
      restoredClaimRole == UserRole.superadmin ||
          restoredProfile?.role == UserRole.superadmin
      ? UserRole.superadmin
      : restoredClaimRole == UserRole.admin ||
            restoredProfile?.role == UserRole.admin
      ? UserRole.admin
      : UserRole.customer;

  // Customer sessions may be restored between launches. Admin sessions are
  // intentionally session-only so closing the app can never silently reopen a
  // privileged dashboard; the admin must authenticate again with Firebase.
  if (restoredUser != null && restoredRole.isAdmin) {
    restoredUser = null;
    try {
      await authRepository.signOut();
    } on Object {
      // The local launch gate still prevents the privileged route from being
      // restored if Firebase sign-out is temporarily unavailable.
    }
  }
  final initialAuthenticatedUserId = restoredUser?.id;
  final initialUserProfile = restoredUser == null
      ? null
      : restoredProfile?.copyWith(role: restoredRole) ??
            UserProfile(
              id: restoredUser.id,
              email: restoredUser.email ?? '',
              displayName: restoredUser.displayName ?? '',
              role: restoredRole,
              createdAt: DateTime.tryParse(restoredUser.createdAt) ?? DateTime.now(),
            );
  final CatalogRepository? catalogRepository = SupabaseCatalogRepository();
  final CartRepository? cartRepository = SupabaseCartRepository();
  final WishlistRepository? wishlistRepository = null;
  final OrderRepository? orderRepository = SupabaseOrderRepository();
  final notificationService = null;
  if (notificationService != null) {
    try {
      await notificationService.initialize();
    } on Object {
      // Notification setup must never prevent the app from starting.
    }
  }
  runApp(
    MyApp(
      launchPreferences: launchPreferences,
      initialAuthenticatedUserId: initialAuthenticatedUserId,
      initialUserProfile: initialUserProfile,
      catalogRepository: catalogRepository,
      cartRepository: cartRepository,
      wishlistRepository: wishlistRepository,
      orderRepository: orderRepository,
      userProfileRepository: userProfileRepository,
      notificationService: notificationService,
      savedAddressRepository: savedAddressRepository,
      addressAutocompleteProvider: addressAutocompleteProvider,
      productReviewRepository: productReviewRepository,
    ),
  );
}

enum ScentifyPage {
  splash,
  onboarding,
  auth,
  home,
  catalog,
  topPicks,
  filters,
  product,
  wishlist,
  cart,
  checkoutAddress,
  checkoutDelivery,
  checkoutPayment,
  confirmation,
  tracking,
  notifications,
  profile,
  settings,
  purchases,
  helpCentre,
  about,
  admin,
}

class WireframeColors {
  static const canvas = ScentifyColors.background;
  static const paper = ScentifyColors.surface;
  static const ink = ScentifyColors.ink;
  static const muted = ScentifyColors.muted;
  static const faint = ScentifyColors.faint;
  static const field = ScentifyColors.surfaceMuted;
  static const placeholder = Color(0xFFE9E8E2);
  static const placeholderLine = Color(0xFFD5D4CE);
  static const border = ScentifyColors.border;
  static const darkButton = ScentifyColors.ink;
  static const darkSurface = Color(0xFF202A33);
  static const tobacco = ScentifyColors.brassInk;
  static const brassInk = ScentifyColors.brassInk;
  static const gold = ScentifyColors.champagne;
  static const goldSoft = ScentifyColors.gold;
  static const olive = Color(0xFF5E6651);
  static const selected = ScentifyColors.champagneSoft;
  static const cartBackground = ScentifyColors.background;
  static const cartSurface = ScentifyColors.surface;
  static const cartAccent = ScentifyColors.brassInk;
}

class ScentifyAssets {
  static const mark = 'assets/images/scentify-mark.png';
  static const appIcon = 'assets/images/scentify-app-icon.png';
  static const hero = 'assets/images/hero-evening-edit-wide.png';
  static const heroEvening = 'assets/images/hero-evening-edit.png';
  static const onboardingSignatureScent =
      'assets/images/onboarding/onboarding-editorial-hero-transparent.png';
  static const authEditorialHero = 'assets/images/auth-editorial-hero.png';
  static const googleLogo = 'assets/images/google-g-logo.png';
  static const onboardingRecommendations =
      'assets/images/onboarding/onboarding-curated-recommendations.png';
  static const onboardingFavorites =
      'assets/images/onboarding/onboarding-favorites-collection.png';
  static const onboardingAuthenticShopping =
      'assets/images/onboarding/onboarding-authentic-shopping.png';
  static const cocoMademoiselle =
      'assets/images/product-chanel-coco-mademoiselle.png';
  static const sauvage = 'assets/images/product-dior-sauvage.png';
  static const libre = 'assets/images/product-ysl-libre.png';
  static const floraGorgeousGardenia =
      'assets/images/product-gucci-flora-gorgeous-gardenia.png';
  static const eros = 'assets/images/product-versace-eros.png';
  static const oudWood = 'assets/images/product-tom-ford-oud-wood.png';
  static const englishPearFreesia =
      'assets/images/product-jo-malone-english-pear.png';
  static const santal33 = 'assets/images/product-le-labo-santal-33.png';
  static const forHer = 'assets/images/product-narciso-for-her.png';
  static const baccaratRouge540 =
      'assets/images/product-mfk-baccarat-rouge-540.png';
  static const chanelLogo = 'assets/images/brands/chanel.png';
  static const diorLogo = 'assets/images/brands/dior_display.png';
  static const yslLogo = 'assets/images/brands/ysl.png';
  static const gucciLogo = 'assets/images/brands/gucci_display.png';
  static const versaceLogo = 'assets/images/brands/versace_display.png';
  static const superadminDashboardHero =
      'assets/images/superadmin-dashboard-hero.png';
}

class Product {
  const Product({
    this.id = '',
    required this.name,
    required this.brand,
    required this.price,
    this.volume = '50ml',
    this.gender = 'Unisex',
    this.description = '',
    this.topNotes = const ['Bergamot', 'Mandarin'],
    this.heartNotes = const ['Jasmine', 'Rose'],
    this.baseNotes = const ['Musk', 'Sandalwood'],
    this.availableVolumes = const ['50ml', '100ml', '150ml'],
    this.pricesByVolume = const {},
    this.variantIdsByVolume = const {},
    this.stockByVolume = const {},
    this.imageUrls = const [],
    this.stock = 0,
    this.isPublished = true,
  });

  factory Product.fromPerfume(Perfume perfume) {
    final variants = [...perfume.variants]
      ..sort((left, right) => left.volumeMl.compareTo(right.volumeMl));
    final firstVariant = variants.isEmpty ? null : variants.first;
    final availableVolumes = variants.isEmpty
        ? const ['50ml']
        : variants.map((variant) => variant.label).toList();

    return Product(
      id: perfume.id,
      name: perfume.name,
      brand: perfume.brandName,
      price: firstVariant == null ? 0 : firstVariant.price.centavos ~/ 100,
      volume: firstVariant?.label ?? '50ml',
      gender: switch (perfume.gender) {
        GenderPreference.women => 'Women',
        GenderPreference.men => 'Men',
        GenderPreference.unisex => 'Unisex',
      },
      description: perfume.description,
      topNotes: perfume.topNotes,
      heartNotes: perfume.heartNotes,
      baseNotes: perfume.baseNotes,
      availableVolumes: availableVolumes,
      pricesByVolume: {
        for (final variant in variants)
          variant.label: variant.price.centavos ~/ 100,
      },
      variantIdsByVolume: {
        for (final variant in variants) variant.label: variant.id,
      },
      stockByVolume: variants.isEmpty
          ? {'50ml': 0}
          : {for (final variant in variants) variant.label: variant.stock},
      imageUrls: perfume.imageUrls,
      stock: variants.fold<int>(0, (total, variant) => total + variant.stock),
      isPublished: perfume.isPublished,
    );
  }

  final String id;
  final String name;
  final String brand;
  final int price;
  final String volume;
  final String gender;
  final String description;
  final List<String> topNotes;
  final List<String> heartNotes;
  final List<String> baseNotes;
  final List<String> availableVolumes;
  final Map<String, int> pricesByVolume;
  final Map<String, String> variantIdsByVolume;
  final Map<String, int> stockByVolume;
  final List<String> imageUrls;
  final int stock;
  final bool isPublished;

  int priceFor(String selectedVolume) =>
      pricesByVolume[selectedVolume] ??
      (selectedVolume == volume ? price : price + 2000);

  String variantIdFor(String selectedVolume) =>
      variantIdsByVolume[selectedVolume] ??
      '$id-${selectedVolume.replaceAll('ml', '')}';

  bool get hasKnownStock => stockByVolume.isNotEmpty;

  bool get isAvailable => isPublished && (!hasKnownStock || stock > 0);

  int stockFor(String selectedVolume) {
    if (hasKnownStock) {
      return stockByVolume[selectedVolume] ?? 0;
    }
    return stock;
  }

  bool isVolumeAvailable(String selectedVolume) =>
      !hasKnownStock || stockFor(selectedVolume) > 0;

  Product copyWith({String? id, int? stock, bool? isPublished}) => Product(
    id: id ?? this.id,
    name: name,
    brand: brand,
    price: price,
    volume: volume,
    gender: gender,
    description: description,
    topNotes: topNotes,
    heartNotes: heartNotes,
    baseNotes: baseNotes,
    availableVolumes: availableVolumes,
    pricesByVolume: pricesByVolume,
    variantIdsByVolume: variantIdsByVolume,
    stockByVolume: stockByVolume,
    imageUrls: imageUrls,
    stock: stock ?? this.stock,
    isPublished: isPublished ?? this.isPublished,
  );
}

String _defaultProductVolume(Product product) {
  for (final volume in product.availableVolumes) {
    if (product.isVolumeAvailable(volume)) {
      return volume;
    }
  }
  return product.availableVolumes.isEmpty
      ? product.volume
      : product.availableVolumes.first;
}

const demoProducts = <Product>[
  Product(
    name: 'Coco Mademoiselle Eau de Parfum',
    brand: 'Chanel',
    price: 8900,
    volume: '100ml',
    gender: 'Women',
  ),
  Product(
    name: 'Sauvage Eau de Toilette',
    brand: 'Dior',
    price: 7900,
    volume: '100ml',
    gender: 'Men',
  ),
  Product(
    name: 'Libre Eau de Parfum',
    brand: 'YSL',
    price: 8500,
    volume: '90ml',
    gender: 'Women',
  ),
  Product(
    name: 'Flora Gorgeous Gardenia',
    brand: 'Gucci',
    price: 9200,
    volume: '100ml',
    gender: 'Women',
  ),
  Product(
    name: 'Eros Eau de Toilette',
    brand: 'Versace',
    price: 6500,
    volume: '100ml',
    gender: 'Men',
  ),
];

const topPicksProducts = <Product>[
  Product(
    name: 'Coco Mademoiselle Eau de Parfum',
    brand: 'Chanel',
    price: 8900,
    volume: '100ml',
    gender: 'Women',
  ),
  Product(
    name: 'Sauvage Eau de Toilette',
    brand: 'Dior',
    price: 7900,
    volume: '100ml',
    gender: 'Men',
  ),
  Product(
    name: 'Libre Eau de Parfum',
    brand: 'YSL',
    price: 8500,
    volume: '90ml',
    gender: 'Women',
  ),
  Product(
    name: 'Flora Gorgeous Gardenia',
    brand: 'Gucci',
    price: 9200,
    volume: '100ml',
    gender: 'Women',
  ),
  Product(
    name: 'Eros Eau de Toilette',
    brand: 'Versace',
    price: 6500,
    volume: '100ml',
    gender: 'Men',
  ),
  Product(
    name: 'Oud Wood Eau de Parfum',
    brand: 'Tom Ford',
    price: 17500,
    volume: '50ml',
    gender: 'Unisex',
  ),
  Product(
    name: 'English Pear & Freesia Cologne',
    brand: 'Jo Malone',
    price: 9500,
    volume: '100ml',
    gender: 'Women',
  ),
  Product(
    name: 'Santal 33 Eau de Parfum',
    brand: 'Le Labo',
    price: 18500,
    volume: '100ml',
    gender: 'Unisex',
  ),
  Product(
    name: 'For Her Eau de Parfum',
    brand: 'Narciso Rodriguez',
    price: 8200,
    volume: '50ml',
    gender: 'Women',
  ),
  Product(
    name: 'Baccarat Rouge 540 Eau de Parfum',
    brand: 'Maison Francis Kurkdjian',
    price: 28500,
    volume: '70ml',
    gender: 'Unisex',
  ),
];

List<Product> _fallbackCatalogProducts() {
  final products = <Product>[];
  final productIds = <String>{};
  final productKeys = <String>{};

  void addUnique(Product product, {required String fallbackId}) {
    final productId = product.id.isEmpty ? fallbackId : product.id;
    final productKey =
        '${product.brand.trim().toLowerCase()}::'
        '${product.name.trim().toLowerCase()}';
    if (productIds.contains(productId) || productKeys.contains(productKey)) {
      return;
    }

    productIds.add(productId);
    productKeys.add(productKey);
    products.add(
      product.id.isEmpty ? product.copyWith(id: productId) : product,
    );
  }

  for (var index = 0; index < topPicksProducts.length; index++) {
    addUnique(topPicksProducts[index], fallbackId: 'fallback-${index + 1}');
  }
  for (final product in additionalCatalogSeed) {
    addUnique(Product.fromPerfume(product), fallbackId: product.id);
  }
  return products;
}

List<Perfume> _fallbackCatalogPerfumes() {
  final products = _fallbackCatalogProducts();
  return [
    for (var index = 0; index < products.length; index++)
      _perfumeFromProduct(products[index], index),
  ];
}

Cart _fallbackCart() {
  final catalogProducts = _fallbackCatalogProducts();
  final products = _fallbackCatalogPerfumes();
  final cartIndexes = [0, 1, 3];
  return Cart(
    userId: 'demo-customer',
    items: [
      for (final index in cartIndexes)
        _fallbackCartItem(catalogProducts[index], products[index]),
    ],
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

CartItem _fallbackCartItem(Product catalogProduct, Perfume product) {
  var variant = product.variants.first;
  for (final candidate in product.variants) {
    if (candidate.label == catalogProduct.volume) {
      variant = candidate;
      break;
    }
  }
  return CartItem(
    productId: product.id,
    variantId: variant.id,
    productName: product.name,
    variantLabel: variant.label,
    unitPrice: variant.price,
    quantity: 1,
  );
}

Perfume _perfumeFromProduct(Product product, int index) {
  final gender = switch (product.gender) {
    'Women' => GenderPreference.women,
    'Men' => GenderPreference.men,
    _ => GenderPreference.unisex,
  };
  final family = switch (gender) {
    GenderPreference.women => FragranceFamily.floral,
    GenderPreference.men => FragranceFamily.woody,
    GenderPreference.unisex => FragranceFamily.fresh,
  };
  final volumes = product.availableVolumes.isEmpty
      ? [product.volume]
      : product.availableVolumes;
  final productId = product.id.isEmpty ? 'fallback-${index + 1}' : product.id;

  return Perfume(
    id: productId,
    brandId: product.brand.toLowerCase().replaceAll(' ', '-'),
    brandName: product.brand,
    name: product.name,
    description: product.description,
    gender: gender,
    family: family,
    concentration: Concentration.edp,
    occasions: const [Occasion.everyday],
    vibes: const [ScentVibe.elegant],
    topNotes: product.topNotes,
    heartNotes: product.heartNotes,
    baseNotes: product.baseNotes,
    variants: [
      for (var volumeIndex = 0; volumeIndex < volumes.length; volumeIndex++)
        PerfumeVariant(
          id: '$productId-${volumes[volumeIndex].replaceAll('ml', '')}',
          label: volumes[volumeIndex],
          volumeMl:
              int.tryParse(volumes[volumeIndex].replaceAll('ml', '')) ?? 50,
          price: Money(product.priceFor(volumes[volumeIndex]) * 100),
          stock: 10,
        ),
    ],
    tags: [product.brand.toLowerCase(), product.gender.toLowerCase()],
  );
}

Color productTone(Product product) {
  return switch (product.brand) {
    'Chanel' => WireframeColors.goldSoft,
    'Dior' => WireframeColors.olive,
    'YSL' => WireframeColors.tobacco,
    'Gucci' => const Color(0xFF8D6D55),
    'Versace' => const Color(0xFF8C7B55),
    'Tom Ford' => const Color(0xFF6F5B46),
    'Jo Malone' => const Color(0xFFB29473),
    'Le Labo' => const Color(0xFF716B5A),
    'Narciso Rodriguez' => const Color(0xFF9F8B87),
    'Maison Francis Kurkdjian' => const Color(0xFFB49A75),
    _ => WireframeColors.gold,
  };
}

/// A quiet, bottle-aware surface that keeps catalog imagery consistent without
/// introducing display-only product data.
Color productTileColor(Product product) {
  return switch (product.brand) {
    'Chanel' || 'Narciso Rodriguez' => ScentifyColors.blush,
    'Dior' || 'Jo Malone' || 'Le Labo' => ScentifyColors.sage,
    'YSL' => ScentifyColors.plum,
    'Gucci' || 'Versace' || 'Maison Francis Kurkdjian' => ScentifyColors.sand,
    'Tom Ford' => ScentifyColors.smoke,
    _ => ScentifyColors.surfaceMuted,
  };
}

String? productImageAsset(Product product) {
  if (product.id.startsWith('seed-')) {
    return 'assets/images/catalog/${product.id}.png';
  }

  return switch (product.name.trim().toLowerCase()) {
    'coco mademoiselle eau de parfum' => ScentifyAssets.cocoMademoiselle,
    'sauvage eau de toilette' => ScentifyAssets.sauvage,
    'libre eau de parfum' => ScentifyAssets.libre,
    'flora gorgeous gardenia' => ScentifyAssets.floraGorgeousGardenia,
    'eros eau de toilette' => ScentifyAssets.eros,
    'oud wood eau de parfum' => ScentifyAssets.oudWood,
    'english pear & freesia cologne' => ScentifyAssets.englishPearFreesia,
    'santal 33 eau de parfum' => ScentifyAssets.santal33,
    'for her eau de parfum' => ScentifyAssets.forHer,
    'baccarat rouge 540 eau de parfum' => ScentifyAssets.baccaratRouge540,
    _ => null,
  };
}

String? productImageUrl(Product product) {
  for (final value in product.imageUrls) {
    final url = value.trim();
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return url;
    }
  }
  return null;
}

enum _CatalogSort { featured, priceLowToHigh, priceHighToLow }

@immutable
class CatalogFilters {
  const CatalogFilters({
    this.brands = const {},
    this.families = const {},
    this.gender = 'All',
    this.priceRange = const RangeValues(0, 50000),
  });

  final Set<String> brands;
  final Set<String> families;
  final String gender;
  final RangeValues priceRange;

  CatalogFilters copyWith({
    Set<String>? brands,
    Set<String>? families,
    String? gender,
    RangeValues? priceRange,
  }) => CatalogFilters(
    brands: Set.unmodifiable(brands ?? this.brands),
    families: Set.unmodifiable(families ?? this.families),
    gender: gender ?? this.gender,
    priceRange: priceRange ?? this.priceRange,
  );

  int get activeCount =>
      brands.length +
      families.length +
      (gender == 'All' ? 0 : 1) +
      (priceRange.start > 0 || priceRange.end < 50000 ? 1 : 0);
}

String formatPrice(int value) {
  return formatPeso(value);
}

String _invoiceDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _orderStatusLabel(OrderStatus status) {
  return switch (status) {
    OrderStatus.pendingPayment => 'Pending Payment',
    OrderStatus.pendingConfirmation => 'Awaiting Confirmation',
    OrderStatus.confirmed => 'Confirmed',
    OrderStatus.processing => 'Processing',
    OrderStatus.packed => 'Packed',
    OrderStatus.shipped => 'Shipped',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
  };
}

List<OrderStatus> _orderProgressStatuses(Order order) {
  return [
    order.status == OrderStatus.pendingPayment || order.paymentMethod != 'cod'
        ? OrderStatus.pendingPayment
        : OrderStatus.pendingConfirmation,
    OrderStatus.confirmed,
    OrderStatus.processing,
    OrderStatus.packed,
    OrderStatus.shipped,
    OrderStatus.delivered,
  ];
}

String _orderNotificationTitle(Order order) =>
    'Order ${_orderStatusLabel(order.status).toLowerCase()}';

String _orderNotificationBody(Order order) {
  return switch (order.status) {
    OrderStatus.pendingPayment =>
      'We are checking the payment reference for order ${order.id}.',
    OrderStatus.pendingConfirmation =>
      'We are checking the price and availability for order ${order.id}.',
    OrderStatus.confirmed =>
      order.paymentMethod == 'cod'
          ? 'Order ${order.id} is confirmed. Payment is due on delivery.'
          : 'Payment confirmed. We are preparing order ${order.id}.',
    OrderStatus.processing =>
      'Our team is preparing the scents in order ${order.id}.',
    OrderStatus.packed => 'Order ${order.id} is packed and ready to ship.',
    OrderStatus.shipped => 'Order ${order.id} is on the way to you.',
    OrderStatus.delivered => 'Order ${order.id} has been delivered.',
    OrderStatus.cancelled => 'Order ${order.id} was cancelled.',
  };
}

Color _orderStatusColor(OrderStatus status) {
  return switch (status) {
    OrderStatus.pendingPayment => WireframeColors.tobacco,
    OrderStatus.pendingConfirmation => WireframeColors.tobacco,
    OrderStatus.confirmed => WireframeColors.brassInk,
    OrderStatus.processing => WireframeColors.olive,
    OrderStatus.packed => WireframeColors.brassInk,
    OrderStatus.shipped => WireframeColors.tobacco,
    OrderStatus.delivered => WireframeColors.darkButton,
    OrderStatus.cancelled => WireframeColors.muted,
  };
}

IconData _orderStatusIcon(OrderStatus status) {
  return switch (status) {
    OrderStatus.pendingPayment => Icons.schedule_outlined,
    OrderStatus.pendingConfirmation => Icons.schedule_outlined,
    OrderStatus.confirmed => Icons.verified_outlined,
    OrderStatus.processing => Icons.inventory_2_outlined,
    OrderStatus.packed => Icons.inventory_outlined,
    OrderStatus.shipped => Icons.local_shipping_outlined,
    OrderStatus.delivered => Icons.check_circle_outline,
    OrderStatus.cancelled => Icons.cancel_outlined,
  };
}

String _orderStatusDescription(OrderStatus status, {String? paymentStatus}) {
  return switch (status) {
    OrderStatus.pendingPayment => 'Payment is being reviewed.',
    OrderStatus.pendingConfirmation =>
      'The seller will confirm price and stock before preparing your order.',
    OrderStatus.confirmed =>
      paymentStatus == 'pending_collection' || paymentStatus == 'unpaid'
          ? 'Your order is confirmed. Payment is due on delivery.'
          : 'Your payment is confirmed.',
    OrderStatus.processing => 'Our team is preparing your scents.',
    OrderStatus.packed => 'Your order is packed and ready to leave.',
    OrderStatus.shipped => 'Your order is moving to your address.',
    OrderStatus.delivered => 'Your order has arrived.',
    OrderStatus.cancelled => 'This order was cancelled.',
  };
}

String _orderPaymentMethodLabel(String? method) => switch (method) {
  'gcash' => 'GCash',
  'maya' => 'Maya',
  'card' => 'Credit / Debit Card',
  'cod' => 'Cash on Delivery',
  _ => 'Payment method not recorded',
};

String _orderPaymentStatusLabel(String? status) => switch (status) {
  'pending' => 'Payment pending',
  'pending_collection' => 'Collection pending',
  'unpaid' => 'Unpaid',
  'paid' => 'Paid',
  _ => 'Status not recorded',
};

String _reviewFailureMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    if (kDebugMode) debugPrint('Review callable failed: ${error.code}');
    return switch (error.code) {
      'unauthenticated' => 'Sign in again to submit your review.',
      'already-exists' => 'This purchase item has already been reviewed.',
      'failed-precondition' || 'permission-denied' =>
        'This delivered purchase is not eligible for a review.',
      'resource-exhausted' => 'Too many review attempts. Try again later.',
      _ => 'Your review could not be saved. Your entries are still here; try again.',
    };
  }
  return 'Your review could not be saved. Your entries are still here; try again.';
}

String _orderPaymentSummary(Order order) =>
    '${_orderPaymentMethodLabel(order.paymentMethod)} · '
    '${_orderPaymentStatusLabel(order.paymentStatus)}';

String _checkoutFailureMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    if (kDebugMode) debugPrint('Checkout callable failed: ${error.code}');
    final backendMessage = error.message?.trim();
    return switch (error.code) {
      'unauthenticated' =>
        'Your session expired. Sign in again before placing your order.',
      'permission-denied' => 'We could not verify this checkout for your account. Sign in again and retry.',
      'not-found' => 'The selected saved address is no longer available. Choose or enter another address.',
      'invalid-argument' || 'failed-precondition' || 'resource-exhausted' =>
        backendMessage?.isNotEmpty == true
            ? backendMessage!
            : 'Review your delivery details and cart, then try again.',
      'unavailable' || 'deadline-exceeded' || 'internal' => 'Checkout is temporarily unavailable. Your cart and address are unchanged; retry shortly.',
      _ => 'We could not confirm your order. Your cart and address are unchanged; retry shortly.',
    };
  }
  if (error is FirebaseException) {
    if (kDebugMode) {
      debugPrint('Checkout Firebase request failed: ${error.code}');
    }
    return switch (error.code) {
      'permission-denied' => 'We could not save the order for this account. Sign in again and retry.',
      'unavailable' || 'deadline-exceeded' => 'Checkout is temporarily unavailable. Your cart and address are unchanged; retry shortly.',
      _ => 'We could not save your order. Your cart and address are unchanged; retry shortly.',
    };
  }
  if (error is AppException) return error.message;
  if (error is FormatException) {
    return 'We could not verify your checkout details. Review them and try again.';
  }
  if (kDebugMode) debugPrint('Checkout failed: ${error.runtimeType}');
  return 'We could not confirm your order. Your cart and address are unchanged; retry shortly.';
}

String _notificationTimeLabel(DateTime createdAt) {
  final elapsed = DateTime.now().difference(createdAt);
  if (elapsed.inMinutes < 1) {
    return 'Just now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes}m ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours}h ago';
  }
  return '${elapsed.inDays}d ago';
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.initialPage = ScentifyPage.splash,
    this.launchPreferences,
    this.initialAuthenticatedUserId,
    this.initialUserProfile,
    this.catalogRepository,
    this.initialCatalogProducts,
    this.cartRepository,
    this.customerId,
    this.initialCart,
    this.wishlistRepository,
    this.initialWishlistIds,
    this.orderRepository,
    this.userProfileRepository,
    this.notificationService,
    this.savedAddressRepository,
    this.addressAutocompleteProvider,
    this.productReviewRepository,
  });

  final ScentifyPage initialPage;
  final SharedPreferences? launchPreferences;
  final String? initialAuthenticatedUserId;
  final UserProfile? initialUserProfile;
  final CatalogRepository? catalogRepository;
  final List<Product>? initialCatalogProducts;
  final CartRepository? cartRepository;
  final String? customerId;
  final Cart? initialCart;
  final WishlistRepository? wishlistRepository;
  final Set<String>? initialWishlistIds;
  final OrderRepository? orderRepository;
  final UserProfileRepository? userProfileRepository;
  final NotificationService? notificationService;
  final SavedAddressRepository? savedAddressRepository;
  final AddressAutocompleteProvider? addressAutocompleteProvider;
  final ProductReviewRepository? productReviewRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = switch (widget.launchPreferences?.getString(
      _themeModePreferenceKey,
    )) {
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
  }

  void _setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    setState(() => _themeMode = mode);
    final preferences = widget.launchPreferences;
    if (preferences != null) {
      unawaited(
        preferences.setString(
          _themeModePreferenceKey,
          mode == ThemeMode.dark ? 'dark' : 'light',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scentify',
      debugShowCheckedModeBanner: false,
      theme: ScentifyTheme.light(),
      darkTheme: ScentifyTheme.dark(),
      themeMode: _themeMode,
      home: ScentifyApp(
        initialPage: widget.initialPage,
        launchPreferences: widget.launchPreferences,
        initialAuthenticatedUserId: widget.initialAuthenticatedUserId,
        initialUserProfile: widget.initialUserProfile,
        catalogRepository: widget.catalogRepository,
        initialCatalogProducts: widget.initialCatalogProducts,
        cartRepository: widget.cartRepository,
        customerId: widget.customerId,
        initialCart: widget.initialCart,
        wishlistRepository: widget.wishlistRepository,
        initialWishlistIds: widget.initialWishlistIds,
        orderRepository: widget.orderRepository,
        userProfileRepository: widget.userProfileRepository,
        notificationService: widget.notificationService,
        savedAddressRepository: widget.savedAddressRepository,
        addressAutocompleteProvider: widget.addressAutocompleteProvider,
        productReviewRepository: widget.productReviewRepository,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class ScentifyApp extends StatefulWidget {
  const ScentifyApp({
    super.key,
    this.initialPage = ScentifyPage.splash,
    this.launchPreferences,
    this.initialAuthenticatedUserId,
    this.initialUserProfile,
    this.catalogRepository,
    this.initialCatalogProducts,
    this.cartRepository,
    this.customerId,
    this.initialCart,
    this.wishlistRepository,
    this.initialWishlistIds,
    this.orderRepository,
    this.userProfileRepository,
    this.notificationService,
    this.savedAddressRepository,
    this.addressAutocompleteProvider,
    this.productReviewRepository,
    this.themeMode = ThemeMode.light,
    this.onThemeModeChanged,
  });

  final ScentifyPage initialPage;
  final SharedPreferences? launchPreferences;
  final String? initialAuthenticatedUserId;
  final UserProfile? initialUserProfile;
  final CatalogRepository? catalogRepository;
  final List<Product>? initialCatalogProducts;
  final CartRepository? cartRepository;
  final String? customerId;
  final Cart? initialCart;
  final WishlistRepository? wishlistRepository;
  final Set<String>? initialWishlistIds;
  final OrderRepository? orderRepository;
  final UserProfileRepository? userProfileRepository;
  final NotificationService? notificationService;
  final SavedAddressRepository? savedAddressRepository;
  final AddressAutocompleteProvider? addressAutocompleteProvider;
  final ProductReviewRepository? productReviewRepository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<ScentifyApp> createState() => _ScentifyAppState();
}

class _ScentifyAppState extends State<ScentifyApp> {
  late ScentifyPage _page = widget.initialPage;
  final _history = <ScentifyPage>[];
  Timer? _splashTimer;
  late final CatalogRepository _catalogRepository;
  StreamSubscription<List<Perfume>>? _catalogSubscription;
  late final CartRepository _cartRepository;
  late final CartService _cartService;
  StreamSubscription<Cart?>? _cartSubscription;
  late final WishlistRepository _wishlistRepository;
  late final WishlistService _wishlistService;
  StreamSubscription<Set<String>>? _wishlistSubscription;
  late final OrderRepository _orderRepository;
  late final CheckoutService _checkoutService;
  StreamSubscription<List<Order>>? _orderSubscription;
  StreamSubscription<ScentifyNotification>? _notificationSubscription;
  late final UserProfileRepository _userProfileRepository;
  StreamSubscription<UserProfile?>? _profileSubscription;
  late final SavedAddressRepository _savedAddressRepository;
  StreamSubscription<SavedAddress?>? _savedAddressSubscription;
  late final ProductReviewRepository _productReviewRepository;
  Timer? _profileRetryTimer;
  List<Product> _catalogProducts = const [];
  String? _catalogError;
  bool _catalogHasLoaded = false;
  int _onboardingStage = 0;
  bool _hasAuthenticatedSession = false;
  Product _selectedProduct = demoProducts.first;
  late String _customerId;
  Cart _cart = _fallbackCart();
  String? _cartError;
  Set<String> _wishlistIds = const {};
  String? _wishlistError;
  List<Order> _orders = const [];
  Order? _latestOrder;
  Order? _trackingOrder;
  String? _orderError;
  List<ScentifyNotification> _notifications = const [];
  Set<String> _readNotificationIds = const {};
  final _notifiedOrderIds = <String>{};
  var _hasReceivedOrderSnapshot = false;
  late UserProfile _profile;
  String? _profileError;
  SavedAddress? _savedAddress;
  String? _savedAddressError;
  ShippingAddress? _shippingAddress;
  String? _shippingAddressId;
  List<CartItem> _checkoutItems = const [];
  String _delivery = 'Standard Delivery';
  String _paymentMethod = 'cod';
  String? _checkoutCodOrderId;
  CatalogFilters _catalogFilters = const CatalogFilters();
  bool _returnToOrderReviewAfterAddress = false;
  bool _returnToProfileAfterAddress = false;
  bool _quickViewOpen = false;
  final _cartAddsInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    _hasAuthenticatedSession = widget.initialAuthenticatedUserId != null;
    final fallbackProducts = _fallbackCatalogProducts();
    _catalogRepository =
        widget.catalogRepository ??
        (_useSupabase
            ? SupabaseCatalogRepository()
            : InMemoryCatalogRepository(_fallbackCatalogPerfumes()));
    _catalogProducts =
        widget.initialCatalogProducts ??
        (widget.catalogRepository == null && !_useSupabase
            ? fallbackProducts
            : const []);
    _catalogHasLoaded =
        widget.initialCatalogProducts != null ||
        widget.catalogRepository == null && !_useSupabase;
    if (_catalogProducts.isNotEmpty) {
      _selectedProduct = _catalogProducts.first;
    }
    _catalogSubscription = _catalogRepository
        .watch(filter: const CatalogFilter(availableOnly: false))
        .listen(
          (products) {
            if (!mounted) {
              return;
            }
            final updatedProducts = _orderedCatalogProducts(
              products.map(Product.fromPerfume),
            );
            setState(() {
              _catalogProducts = updatedProducts;
              _catalogError = null;
              _catalogHasLoaded = true;
              final selectedId = _selectedProduct.id;
              final updatedSelected = updatedProducts.where(
                (product) =>
                    (selectedId.isNotEmpty && product.id == selectedId) ||
                    (selectedId.isEmpty &&
                        product.name == _selectedProduct.name &&
                        product.brand == _selectedProduct.brand),
              );
              if (selectedId.isNotEmpty && updatedSelected.isNotEmpty) {
                _selectedProduct = updatedSelected.first;
              } else if (selectedId.isEmpty &&
                  updatedSelected.isEmpty &&
                  updatedProducts.isNotEmpty) {
                _selectedProduct = updatedProducts.first;
              }
            });
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) {
              setState(() {
                _catalogHasLoaded = true;
                _catalogError = 'We could not load the catalog.';
              });
            }
          },
        );
    _customerId =
        widget.customerId ??
        widget.initialAuthenticatedUserId ??
        'demo-customer';
    _savedAddressRepository =
        widget.savedAddressRepository ?? InMemorySavedAddressRepository();
    _productReviewRepository =
        widget.productReviewRepository ?? InMemoryProductReviewRepository();
    _watchSavedAddress();
    if (_hasAuthenticatedSession) {
      unawaited(widget.notificationService?.registerForUser(_customerId));
    }
    _notificationSubscription = widget.notificationService?.notifications
        .listen(_receiveNotification);
    _userProfileRepository =
        widget.userProfileRepository ?? InMemoryUserProfileRepository();
    _profile = widget.initialUserProfile?.id == _customerId
        ? widget.initialUserProfile!
        : _fallbackUserProfile(_customerId);
    _watchProfile();
    _cartRepository =
        widget.cartRepository ??
        (InMemoryCartRepository()..save(_fallbackCart()));
    _cartService = CartService(
      cartRepository: _cartRepository,
      catalogRepository: _catalogRepository,
    );
    _cart =
        widget.initialCart ??
        (widget.cartRepository == null ? _fallbackCart() : _emptyCart());
    _watchCart();
    _wishlistRepository =
        widget.wishlistRepository ?? InMemoryWishlistRepository();
    _wishlistService = WishlistService(_wishlistRepository);
    _wishlistIds = Set.unmodifiable(
      widget.initialWishlistIds ??
          (widget.wishlistRepository == null
              ? fallbackProducts.take(3).map((product) => product.id).toSet()
              : const <String>{}),
    );
    if (widget.wishlistRepository == null && _wishlistIds.isNotEmpty) {
      unawaited(_wishlistRepository.save(_customerId, _wishlistIds));
    }
    _watchWishlist();
    _orderRepository = widget.orderRepository ?? InMemoryOrderRepository();
    final inventoryService = const NoOpInventoryService();
    final codProvider = SupabaseCashOnDeliveryOrderProvider();
    _checkoutService = CheckoutService(
      cartRepository: _cartRepository,
      catalogRepository: _catalogRepository,
      inventoryService: inventoryService,
      orderRepository: _orderRepository,
      paymentGateway: SupabaseXenditPaymentGateway(),
      cashOnDeliveryOrderProvider: codProvider,
    );
    _watchOrders();
    if (_page == ScentifyPage.splash) {
      _splashTimer = Timer(SplashPage.loadDuration, () {
        if (mounted) {
          final hasSeenOnboarding =
              widget.launchPreferences?.getBool(
                _hasSeenOnboardingPreferenceKey,
              ) ??
              false;
          final destination = hasSeenOnboarding
              ? (_hasAuthenticatedSession
                    ? (_profile.isAdmin
                          ? ScentifyPage.admin
                          : ScentifyPage.home)
                    : ScentifyPage.auth)
              : ScentifyPage.onboarding;
          _replace(destination);
        }
      });
    }
  }

  List<Product> _orderedCatalogProducts(Iterable<Product> products) {
    final available = products.toList();
    final ordered = <Product>[];
    for (final featured in topPicksProducts) {
      final match = available.where(
        (product) =>
            product.name == featured.name && product.brand == featured.brand,
      );
      if (match.isNotEmpty) {
        ordered.add(match.first);
        available.remove(match.first);
      }
    }
    ordered.addAll(available);
    return ordered;
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    unawaited(_catalogSubscription?.cancel());
    unawaited(_cartSubscription?.cancel());
    unawaited(_wishlistSubscription?.cancel());
    unawaited(_orderSubscription?.cancel());
    unawaited(_notificationSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    unawaited(_savedAddressSubscription?.cancel());
    _profileRetryTimer?.cancel();
    super.dispose();
  }

  Cart _emptyCart() =>
      Cart(userId: _customerId, items: const [], updatedAt: DateTime.now());

  UserProfile _fallbackUserProfile(String userId) {
    final email = userId == 'demo-customer'
        ? 'customer@example.com'
        : '$userId@example.com';
    final name = userId == 'demo-customer' ? 'Scentify customer' : userId;
    return UserProfile(
      id: userId,
      email: email,
      displayName: name,
      role: UserRole.customer,
      createdAt: DateTime.now(),
    );
  }

  void _watchProfile() {
    _profileRetryTimer?.cancel();
    _profileSubscription = _userProfileRepository
        .watch(_customerId)
        .listen(
          (profile) {
            if (!mounted) {
              return;
            }
            final nextProfile = profile == null
                ? _profile
                : profile.copyWith(
                    role: _profile.isSuperAdmin || profile.isSuperAdmin
                        ? UserRole.superadmin
                        : _profile.isAdmin || profile.isAdmin
                        ? UserRole.admin
                        : profile.role,
                  );
            setState(() {
              _profile = nextProfile;
              _profileError = null;
            });
            if (_hasAuthenticatedSession) {
              if (nextProfile.isAdmin && _page == ScentifyPage.home) {
                _replace(ScentifyPage.admin);
              } else if (!nextProfile.isAdmin && _page == ScentifyPage.admin) {
                _replace(ScentifyPage.home);
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) {
              setState(
                () =>
                    _profileError = 'Profile sync is temporarily unavailable.',
              );
              _profileRetryTimer?.cancel();
              _profileRetryTimer = Timer(const Duration(seconds: 3), () {
                if (!mounted) {
                  return;
                }
                unawaited(_profileSubscription?.cancel());
                _profileSubscription = null;
                _watchProfile();
              });
            }
          },
        );
  }

  void _watchSavedAddress() {
    _savedAddressSubscription = _savedAddressRepository
        .watchForUser(_customerId)
        .listen(
          (address) {
            if (!mounted) return;
            setState(() {
              _savedAddress = address;
              _savedAddressError = null;
            });
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) {
              setState(
                () => _savedAddressError =
                    'Saved address sync is temporarily unavailable.',
              );
            }
          },
        );
  }

  void _watchCart() {
    _cartSubscription = _cartRepository
        .watch(_customerId)
        .listen(
          (cart) {
            if (!mounted) {
              return;
            }
            setState(() {
              _cart = cart ?? _emptyCart();
              _cartError = null;
            });
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) {
              setState(() => _cartError = 'We could not load your cart.');
            }
          },
        );
  }

  void _watchWishlist() {
    _wishlistSubscription = _wishlistRepository
        .watch(_customerId)
        .listen(
          (productIds) {
            if (mounted) {
              setState(() {
                _wishlistIds = Set.unmodifiable(productIds);
                _wishlistError = null;
              });
            }
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) {
              setState(
                () => _wishlistError = 'We could not load your wishlist.',
              );
            }
          },
        );
  }

  void _watchOrders() {
    _orderSubscription = _orderRepository
        .watchForUser(_customerId)
        .listen(
          (orders) {
            if (mounted) {
              final previousOrders = {
                for (final order in _orders) order.id: order,
              };
              final shouldNotify = _hasReceivedOrderSnapshot;
              final createdOrders = <Order>[];
              final updatedOrders = <Order>[];
              if (shouldNotify) {
                for (final order in orders) {
                  final previous = previousOrders[order.id];
                  if (previous == null &&
                      !_notifiedOrderIds.contains(order.id)) {
                    createdOrders.add(order);
                  } else if (previous != null &&
                      previous.status != order.status) {
                    updatedOrders.add(order);
                  }
                }
              }
              _hasReceivedOrderSnapshot = true;
              setState(() {
                _orders = List.unmodifiable(orders);
                _latestOrder = orders.isEmpty ? _latestOrder : orders.first;
                final trackingId = _trackingOrder?.id;
                if (trackingId != null) {
                  final updatedTracking = orders.where(
                    (order) => order.id == trackingId,
                  );
                  if (updatedTracking.isNotEmpty) {
                    _trackingOrder = updatedTracking.first;
                  }
                }
                _orderError = null;
              });
              for (final order in createdOrders) {
                _publishOrderNotification(order, created: true);
              }
              for (final order in updatedOrders) {
                _publishOrderNotification(order, created: false);
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            if (mounted) {
              setState(() => _orderError = 'We could not load your orders.');
            }
          },
        );
  }

  void _publishOrderNotification(Order order, {required bool created}) {
    _notifiedOrderIds.add(order.id);
    final service = widget.notificationService;
    if (service != null) {
      unawaited(
        created
            ? service.showOrderCreated(order)
            : service.showOrderStatusChanged(order),
      );
      return;
    }

    _receiveNotification(
      ScentifyNotification(
        id: created
            ? 'order-created-${order.id}'
            : 'order-status-${order.id}-${order.status.name}',
        title: created ? 'Order placed' : _orderNotificationTitle(order),
        body: created
            ? order.paymentMethod == 'cod'
                  ? 'Order ${order.id} is confirmed. Payment is due on delivery.'
                  : 'Order ${order.id} is waiting for payment confirmation.'
            : _orderNotificationBody(order),
        createdAt: DateTime.now(),
        orderId: order.id,
      ),
    );
  }

  void _receiveNotification(ScentifyNotification notification) {
    if (!mounted || _notifications.any((item) => item.id == notification.id)) {
      return;
    }
    setState(() {
      _notifications = List.unmodifiable(
        [notification, ..._notifications].take(30),
      );
    });
  }

  void _markNotificationRead(String notificationId) {
    if (_readNotificationIds.contains(notificationId)) {
      return;
    }
    setState(() {
      _readNotificationIds = {..._readNotificationIds, notificationId};
    });
  }

  void _markAllNotificationsRead() {
    if (_notifications.isEmpty) {
      return;
    }
    setState(
      () => _readNotificationIds = {
        for (final notification in _notifications) notification.id,
      },
    );
  }

  int get _unreadNotificationCount => _notifications
      .where((notification) => !_readNotificationIds.contains(notification.id))
      .length;

  void _openNotifications() => _go(ScentifyPage.notifications);

  void _openTracking(Order? order, {bool replace = false}) {
    setState(() => _trackingOrder = order);
    if (replace) {
      _replace(ScentifyPage.tracking);
    } else {
      _go(ScentifyPage.tracking);
    }
  }

  void _openNotification(ScentifyNotification notification) {
    _markNotificationRead(notification.id);
    final orderId = notification.orderId;
    if (orderId == null) {
      return;
    }
    final order = _orders.where((item) => item.id == orderId);
    if (order.isNotEmpty) {
      _openTracking(order.first, replace: true);
    }
  }

  Future<void> _switchCustomer(String customerId) async {
    if (customerId == _customerId) {
      return;
    }
    await _cartSubscription?.cancel();
    await _wishlistSubscription?.cancel();
    await _orderSubscription?.cancel();
    await _profileSubscription?.cancel();
    await _savedAddressSubscription?.cancel();
    _profileRetryTimer?.cancel();
    _customerId = customerId;
    if (_hasAuthenticatedSession) {
      unawaited(widget.notificationService?.registerForUser(customerId));
    }
    if (mounted) {
      setState(() {
        _cart = _emptyCart();
        _cartError = null;
        _wishlistIds = const {};
        _wishlistError = null;
        _orders = const [];
        _latestOrder = null;
        _trackingOrder = null;
        _orderError = null;
        _notifications = const [];
        _readNotificationIds = const {};
        _profile = _fallbackUserProfile(customerId);
        _profileError = null;
        _savedAddress = null;
        _savedAddressError = null;
        _shippingAddress = null;
        _shippingAddressId = null;
        _checkoutCodOrderId = null;
      });
    }
    _notifiedOrderIds.clear();
    _hasReceivedOrderSnapshot = false;
    _watchCart();
    _watchWishlist();
    _watchOrders();
    _watchProfile();
    _watchSavedAddress();
  }

  void _go(ScentifyPage page, {bool replace = false}) {
    setState(() {
      if (replace) {
        _history.clear();
      } else {
        _history.add(_page);
      }
      _page = page;
    });
  }

  void _replace(ScentifyPage page) => _go(page, replace: true);

  void _openCatalog({String? gender, String? family}) {
    setState(() {
      if (gender != null || family != null) {
        _catalogFilters = _catalogFilters.copyWith(
          gender: gender,
          families: family == null ? null : {family},
        );
      }
      _history.clear();
      _page = ScentifyPage.catalog;
    });
  }

  void _back() {
    if (_history.isEmpty) {
      _replace(ScentifyPage.home);
      return;
    }
    setState(() {
      if (_page == ScentifyPage.checkoutAddress &&
          _returnToProfileAfterAddress) {
        _returnToProfileAfterAddress = false;
      }
      _page = _history.removeLast();
    });
  }

  void _handleAndroidSystemBack() {
    if (_history.isNotEmpty) {
      _back();
      return;
    }
    if (_hasAuthenticatedSession &&
        _page != ScentifyPage.home &&
        _page != ScentifyPage.admin) {
      _replace(ScentifyPage.home);
      return;
    }
    SystemNavigator.pop();
  }

  void _selectProduct(Product product) {
    setState(() => _selectedProduct = product);
    _go(ScentifyPage.product);
  }

  void _showProductQuickView(BuildContext context, Product product) {
    if (_quickViewOpen) {
      return;
    }
    _quickViewOpen = true;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => ProductQuickView(
          product: product,
          onAddToCart: (volume) {
            Navigator.of(sheetContext).pop();
            unawaited(_addToCart(product, volume, 1));
          },
          onViewDetails: () {
            Navigator.of(sheetContext).pop();
            _selectProduct(product);
          },
        ),
      ).whenComplete(() {
        if (mounted) {
          _quickViewOpen = false;
        }
      }),
    );
  }

  int get _cartCount =>
      _cart.items.fold(0, (total, item) => total + item.quantity);

  Future<void> _addToCart(Product product, String volume, int quantity) async {
    final variantId = product.variantIdFor(volume);
    final addKey = '${product.id}:$variantId';
    if (!_cartAddsInFlight.add(addKey)) {
      return;
    }
    try {
      await _cartService.addItem(
        userId: _customerId,
        productId: product.id,
        variantId: variantId,
        quantity: quantity,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Added to cart'),
              action: SnackBarAction(
                label: 'View cart',
                onPressed: () => _replace(ScentifyPage.cart),
              ),
            ),
          );
      }
    } catch (error) {
      if (mounted) {
        final message = error is AppException
            ? error.message
            : 'Unable to add this scent to your cart.';
        setState(() => _cartError = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      _cartAddsInFlight.remove(addKey);
    }
  }

  Future<void> _setCartQuantity(CartItem item, int quantity) async {
    try {
      await _cartService.setQuantity(
        userId: _customerId,
        productId: item.productId,
        variantId: item.variantId,
        quantity: quantity,
      );
    } catch (error) {
      if (mounted) {
        final message = error is AppException
            ? error.message
            : 'Unable to update your cart.';
        setState(() => _cartError = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _removeCartItem(CartItem item) async {
    try {
      await _cartService.removeItem(
        userId: _customerId,
        productId: item.productId,
        variantId: item.variantId,
      );
    } catch (error) {
      if (mounted) {
        final message = error is AppException
            ? error.message
            : 'Unable to remove this item.';
        setState(() => _cartError = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  Future<void> _toggleFavorite(Product product) async {
    try {
      await _wishlistService.toggle(userId: _customerId, productId: product.id);
    } catch (error) {
      if (mounted) {
        final message = error is AppException
            ? error.message
            : 'Unable to update your wishlist.';
        setState(() => _wishlistError = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  void _beginCheckout(List<CartItem> items) {
    if (items.isEmpty) {
      return;
    }
    setState(() {
      _checkoutItems = List.unmodifiable(items);
      _shippingAddress = _savedAddress?.address;
      _shippingAddressId = _savedAddress?.id;
      _orderError = null;
      _returnToOrderReviewAfterAddress = false;
    });
    _go(ScentifyPage.checkoutAddress);
  }

  Future<void> _saveAddress(SavedAddress address) async {
    try {
      await _savedAddressRepository.saveForUser(_customerId, address);
      if (mounted) {
        setState(() {
          _savedAddress = address;
          _savedAddressError = null;
        });
      }
    } on Object catch (error) {
      if (kDebugMode) {
        final failureCode = error is FirebaseException
            ? error.code
            : error.runtimeType;
        debugPrint('Address-book save failed ($failureCode).');
      }
      if (mounted) {
        setState(() => _savedAddressError = savedAddressErrorMessage(error));
      }
      rethrow;
    }
  }

  Future<void> _deleteSavedAddress() async {
    try {
      await _savedAddressRepository.deleteForUser(_customerId);
      if (mounted) {
        setState(() {
          _savedAddress = null;
          _shippingAddress = null;
          _shippingAddressId = null;
          _savedAddressError = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _savedAddressError = 'Unable to remove your saved address.',
        );
      }
      rethrow;
    }
  }

  void _selectSavedAddress(String? addressId) {
    setState(() => _shippingAddressId = addressId);
  }

  void _saveShippingAddress(ShippingAddress address) {
    final returnToReview = _returnToOrderReviewAfterAddress;
    final returnToProfile = _returnToProfileAfterAddress;
    setState(() {
      _shippingAddress = address;
      _orderError = null;
      _returnToOrderReviewAfterAddress = false;
      _returnToProfileAfterAddress = false;
    });
    if (returnToProfile) {
      _replace(ScentifyPage.profile);
      return;
    }
    _go(
      returnToReview
          ? ScentifyPage.checkoutPayment
          : ScentifyPage.checkoutDelivery,
    );
  }

  void _openAddressBook() {
    setState(() => _returnToProfileAfterAddress = true);
    _go(ScentifyPage.checkoutAddress);
  }

  void _changeCheckoutAddress() {
    setState(() => _returnToOrderReviewAfterAddress = true);
    _go(ScentifyPage.checkoutAddress);
  }

  DeliveryOption _selectedDeliveryOption() {
    return switch (_delivery) {
      'Express Delivery' => DeliveryOption(
        id: 'express',
        name: 'Express Delivery',
        fee: Money(150 * 100),
        estimatedDays: '1-2 business days',
      ),
      'Same day delivery' => DeliveryOption(
        id: 'same-day',
        name: 'Same day delivery',
        fee: Money(250 * 100),
        estimatedDays: 'Metro Manila only',
      ),
      _ => DeliveryOption(
        id: 'standard',
        name: 'Standard Delivery',
        fee: Money(80 * 100),
        estimatedDays: '3-5 business days',
      ),
    };
  }

  Future<void> _placeOrder() async {
    final address = _shippingAddress;
    if (address == null || _checkoutItems.isEmpty) {
      if (mounted) {
        setState(
          () => _orderError = 'Add a shipping address before placing order.',
        );
      }
      return;
    }
    try {
      final checkoutOrderId = _checkoutCodOrderId ??=
          'order-${DateTime.now().microsecondsSinceEpoch}';
      final order = await _checkoutService.placeOrder(
        userId: _customerId,
        selectedItems: _checkoutItems,
        shippingAddress: address,
        addressId: _shippingAddressId,
        deliveryOption: _selectedDeliveryOption(),
        paymentMethod: _paymentMethod,
        orderId: checkoutOrderId,
      );
      if (mounted) {
        _checkoutCodOrderId = null;
        _paymentMethod = 'cod';
        setState(() {
          _latestOrder = order;
          _trackingOrder = order;
          _orderError = null;
        });
        _publishOrderNotification(order, created: true);
        _replace(ScentifyPage.confirmation);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _orderError = _checkoutFailureMessage(error));
      }
    }
  }

  void _nextOnboarding() {
    if (_onboardingStage < OnboardingPage.stageCount - 1) {
      setState(() => _onboardingStage++);
      return;
    }

    _markOnboardingSeen();
    _replace(_hasAuthenticatedSession ? ScentifyPage.home : ScentifyPage.auth);
  }

  void _skipOnboarding() {
    _markOnboardingSeen();
    _replace(_hasAuthenticatedSession ? ScentifyPage.home : ScentifyPage.auth);
  }

  void _markOnboardingSeen() {
    final preferences = widget.launchPreferences;
    if (preferences != null) {
      unawaited(preferences.setBool(_hasSeenOnboardingPreferenceKey, true));
    }
  }

  Future<void> _submitAuth({
    required bool register,
    String? displayName,
    required String email,
    required String password,
  }) async {
    final repository = SupabaseAuthRepository();
    if (register) {
      await repository.register(
        displayName: displayName ?? '',
        email: email,
        password: password,
      );
    } else {
      await repository.signIn(email: email, password: password);
    }
    await _completeAuthenticatedSession(
      repository,
      fallbackEmail: email,
      displayName: displayName,
    );
  }

  Future<void> _submitGoogleAuth() async {
    final repository = SupabaseAuthRepository();
    await repository.signInWithGoogle();
    await _completeAuthenticatedSession(repository);
  }

  Future<void> _completeAuthenticatedSession(
    SupabaseAuthRepository repository, {
    String? fallbackEmail,
    String? displayName,
  }) async {
    final userId = repository.currentUserId;
    if (userId == null) {
      throw const SupabaseAuthFailure(
        'We could not complete sign-in. Please try again.',
      );
    }
    _hasAuthenticatedSession = true;
    await _switchCustomer(userId);
    final profile = await _saveAuthenticatedProfile(
      userId: userId,
      email: repository.currentUser?.email ?? fallbackEmail ?? '',
      displayName: repository.currentUser?.displayName ?? displayName,
      claimRole: await repository.claimRole(forceRefresh: true),
    );
    if (mounted) {
      _replace(profile.isAdmin ? ScentifyPage.admin : ScentifyPage.home);
    }
  }

  Future<void> _sendPasswordReset(String email) {
    return SupabaseAuthRepository().sendPasswordReset(email: email);
  }

  Future<UserProfile> _saveAuthenticatedProfile({
    required String userId,
    required String email,
    String? displayName,
    UserRole claimRole = UserRole.customer,
  }) async {
    final existing = await _userProfileRepository.findById(userId);
    final fallbackName = claimRole == UserRole.superadmin
        ? 'Scentify Superadmin'
        : claimRole.isAdmin
        ? 'Scentify Admin'
        : email.split('@').first;
    final resolvedName = resolveProfileDisplayName(
      displayName: displayName,
      existingName: existing?.displayName,
      userId: userId,
      fallbackName: fallbackName,
    );
    final profile =
        (existing ??
                UserProfile(
                  id: userId,
                  email: email.trim(),
                  displayName: resolvedName,
                  role: claimRole.isAdmin ? claimRole : UserRole.customer,
                  createdAt: DateTime.now(),
                ))
            .copyWith(
              email: email.trim(),
              displayName: resolvedName,
              role: claimRole.isAdmin ? claimRole : existing?.role,
            );
    await _userProfileRepository.save(profile);
    return profile;
  }

  Future<void> _editProfile(BuildContext context) async {
    final displayName = await showDialog<String>(
      context: context,
      builder: (_) => EditProfileDialog(
        initialDisplayName: _profile.displayName,
        isDarkMode: widget.themeMode == ThemeMode.dark,
        onThemeChanged: (isDarkMode) => widget.onThemeModeChanged?.call(
          isDarkMode ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );

    final trimmedName = displayName?.trim();
    if (!mounted ||
        trimmedName == null ||
        trimmedName.isEmpty ||
        trimmedName.length > _maxProfileNameLength) {
      return;
    }

    try {
      await _userProfileRepository.save(
        _profile.copyWith(displayName: trimmedName),
      );
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Unable to save your profile.')),
          );
      }
    }
  }

  Future<void> _submitProductReview(
    Order order,
    OrderItemSnapshot item,
    int rating,
    String title,
    String comment,
  ) async {
    await _productReviewRepository.submit(
      order: order,
      item: item,
      rating: rating,
      title: title,
      comment: comment,
    );
  }

  void _logout() {
    _hasAuthenticatedSession = false;
    widget.notificationService?.clearRegisteredUser();
    _notifications = const [];
    _readNotificationIds = const {};
    _notifiedOrderIds.clear();
    unawaited(SupabaseAuthRepository().signOut().catchError((_) {}));
    _replace(ScentifyPage.auth);
  }

  void _selectNav(int index) {
    final page = switch (index) {
      0 => ScentifyPage.home,
      1 => ScentifyPage.catalog,
      2 => ScentifyPage.wishlist,
      3 => ScentifyPage.purchases,
      _ => ScentifyPage.profile,
    };
    _replace(page);
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_page) {
      ScentifyPage.splash => const SplashPage(),
      ScentifyPage.onboarding => OnboardingPage(
        stage: _onboardingStage,
        onNext: _nextOnboarding,
        onSkip: _skipOnboarding,
      ),
      ScentifyPage.auth => AuthPage(
        onSubmit: _submitAuth,
        onGoogleSignIn: _submitGoogleAuth,
        onForgotPassword: _sendPasswordReset,
      ),
      ScentifyPage.home => HomePage(
        onNav: _selectNav,
        cartCount: _cartCount,
        products: _catalogProducts,
        catalogError: _catalogError,
        wishlistIds: _wishlistIds,
        notificationCount: _unreadNotificationCount,
        onCart: () => _replace(ScentifyPage.cart),
        onNotifications: _openNotifications,
        onCategory: (filter) => _openCatalog(
          gender: const {'Women', 'Men', 'Unisex'}.contains(filter)
              ? filter
              : null,
          family: const {'Floral', 'Fresh', 'Woody'}.contains(filter)
              ? filter
              : null,
        ),
        onBrowseCatalog: _openCatalog,
        onTopPicks: () => _replace(ScentifyPage.topPicks),
        onProduct: (product) => _showProductQuickView(context, product),
        onAddToCart: (product) =>
            unawaited(_addToCart(product, _defaultProductVolume(product), 1)),
        onFavorite: (product) => unawaited(_toggleFavorite(product)),
      ),
      ScentifyPage.catalog => CatalogPage(
        filters: _catalogFilters,
        products: _catalogProducts,
        catalogError: _catalogError,
        loading: !_catalogHasLoaded,
        wishlistIds: _wishlistIds,
        onNav: _selectNav,
        onAddToCart: (product) =>
            unawaited(_addToCart(product, _defaultProductVolume(product), 1)),
        onFilter: () => _go(ScentifyPage.filters),
        onProduct: (product) => _showProductQuickView(context, product),
        onGenderChanged: (gender) => setState(
          () => _catalogFilters = _catalogFilters.copyWith(gender: gender),
        ),
        onFavorite: (product) => unawaited(_toggleFavorite(product)),
      ),
      ScentifyPage.topPicks => TopPicksPage(
        products: _catalogProducts,
        catalogError: _catalogError,
        wishlistIds: _wishlistIds,
        onNav: _selectNav,
        onAddToCart: (product) => _showProductQuickView(context, product),
        onProduct: (product) => _showProductQuickView(context, product),
        onFavorite: (product) => unawaited(_toggleFavorite(product)),
      ),
      ScentifyPage.filters => FiltersPage(
        onBack: _back,
        products: _catalogProducts,
        initial: _catalogFilters,
        onApply: (filters) {
          setState(() => _catalogFilters = filters);
          _replace(ScentifyPage.catalog);
        },
      ),
      ScentifyPage.product => ProductPage(
        product: _selectedProduct,
        recommendations: _catalogProducts
            .where((product) => product.id != _selectedProduct.id)
            .take(6)
            .toList(growable: false),
        isFavorite: _wishlistIds.contains(_selectedProduct.id),
        onBack: _back,
        onFavorite: () => unawaited(_toggleFavorite(_selectedProduct)),
        onRecommendation: (product) =>
            setState(() => _selectedProduct = product),
        onAddToCart: (quantity, volume) =>
            unawaited(_addToCart(_selectedProduct, volume, quantity)),
        reviewRepository: _productReviewRepository,
      ),
      ScentifyPage.wishlist => WishlistPage(
        onNav: _selectNav,
        onProduct: _selectProduct,
        products: _catalogProducts,
        wishlistIds: _wishlistIds,
        error: _wishlistError,
        onToggle: (product) => unawaited(_toggleFavorite(product)),
        onAddToCart: (product) =>
            unawaited(_addToCart(product, _defaultProductVolume(product), 1)),
      ),
      ScentifyPage.cart => CartPage(
        cart: _cart,
        products: _catalogProducts,
        error: _cartError,
        onBack: _back,
        onSetQuantity: _setCartQuantity,
        onRemove: _removeCartItem,
        onCheckout: _beginCheckout,
      ),
      ScentifyPage.checkoutAddress => CheckoutAddressPage(
        onBack: _back,
        onNext: _saveShippingAddress,
        onSaveAddress: _saveAddress,
        onDeleteSavedAddress: _deleteSavedAddress,
        onSavedAddressSelected: _selectSavedAddress,
        initialAddress:
            !_returnToProfileAfterAddress && _shippingAddressId == null
            ? _shippingAddress
            : null,
        autocompleteProvider: widget.addressAutocompleteProvider,
        savedAddress: _savedAddress,
        error: _savedAddressError ?? _orderError,
        addressSaveMessage: _returnToProfileAfterAddress
            ? 'Add an address to use again from your account.'
            : widget.savedAddressRepository == null
            ? 'Save this address for this app session if you choose.'
            : 'Save this address to your account for future orders if you choose.',
        profileAddressBook: _returnToProfileAfterAddress,
      ),
      ScentifyPage.checkoutDelivery => CheckoutDeliveryPage(
        address: _shippingAddress,
        selected: _delivery,
        onBack: _back,
        onSelect: (value) => setState(() => _delivery = value),
        onNext: () => _go(ScentifyPage.checkoutPayment),
      ),
      ScentifyPage.checkoutPayment => CheckoutPaymentPage(
        address: _shippingAddress,
        items: _checkoutItems,
        products: _catalogProducts,
        delivery: _delivery,
        onBack: _back,
        onChangeAddress: _changeCheckoutAddress,
        onChangeDelivery: () => _go(ScentifyPage.checkoutDelivery),
        itemCount: _checkoutItems.fold(
          0,
          (total, item) => total + item.quantity,
        ),
        subtotal: _checkoutItems.fold(
          Money(0),
          (total, item) => total + item.lineTotal,
        ),
        shippingFee: _selectedDeliveryOption().fee,
        paymentMethod: _paymentMethod,
        showOnlinePayments: true,
        onPaymentMethodChanged: (value) =>
            setState(() => _paymentMethod = value),
        error: _orderError,
        onPay: _placeOrder,
      ),
      ScentifyPage.confirmation => ConfirmationPage(
        order: _latestOrder,
        onViewOrder: () => _openTracking(_latestOrder, replace: true),
      ),
      ScentifyPage.tracking => TrackingPage(
        order: _trackingOrder ?? _latestOrder,
        onBack: _back,
      ),
      ScentifyPage.notifications => NotificationsPage(
        notifications: _notifications,
        readNotificationIds: _readNotificationIds,
        onBack: _back,
        onMarkAllRead: _markAllNotificationsRead,
        onOpen: _openNotification,
      ),
      ScentifyPage.profile => ProfilePage(
        onNav: _selectNav,
        onSettings: () => _go(ScentifyPage.settings),
        onOrders: () => _go(ScentifyPage.purchases),
        onWishlist: () => _replace(ScentifyPage.wishlist),
        onAddresses: _openAddressBook,
        onHelp: () => _go(ScentifyPage.helpCentre),
        onAbout: () => _go(ScentifyPage.about),
        onLogout: _logout,
        orderCount: _orders.length,
        wishlistCount: _wishlistIds.length,
        profile: _profile,
        latestOrder: _latestOrder,
        products: _catalogProducts,
        onTrackOrder: () => _openTracking(_latestOrder),
        profileError: _profileError,
        onEditProfile: () => unawaited(_editProfile(context)),
      ),
      ScentifyPage.settings => SettingsPage(
        themeMode: widget.themeMode,
        onThemeChanged: (isDark) => widget.onThemeModeChanged?.call(
          isDark ? ThemeMode.dark : ThemeMode.light,
        ),
        onBack: _back,
        onEditProfile: () => unawaited(_editProfile(context)),
        onNotifications: _openNotifications,
        onAddresses: _openAddressBook,
        onHelp: () => _go(ScentifyPage.helpCentre),
        onAbout: () => _go(ScentifyPage.about),
      ),
      ScentifyPage.purchases => MyPurchasesPage(
        orders: _orders,
        products: _catalogProducts,
        onNav: _selectNav,
        error: _orderError,
        onBack: _back,
        onOrder: _openTracking,
        reviewRepository: _productReviewRepository,
        onSubmitReview: _submitProductReview,
      ),
      ScentifyPage.helpCentre => HelpCentrePage(
        onBack: _back,
        onPurchases: () => _go(ScentifyPage.purchases),
      ),
      ScentifyPage.about => AboutScentifyPage(onBack: _back),
      ScentifyPage.admin => AdminPage(
        orderRepository: _orderRepository,
        catalogRepository: _catalogRepository,
        profile: _profile,
        products: _catalogProducts,
        onLogout: _logout,
      ),
    };
    // Swap complete pages synchronously. Keeping outgoing pages alive during a
    // root-level transition can deactivate inherited widgets before all of
    // their dependents have been removed, which triggers Flutter's
    // `_dependents.isEmpty` assertion on fast navigation.
    final keyedPage = KeyedSubtree(key: ValueKey(_page), child: page);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return keyedPage;
    }
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleAndroidSystemBack();
      },
      child: keyedPage,
    );
  }
}

class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({
    super.key,
    required this.initialDisplayName,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  final String initialDisplayName;
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final TextEditingController _controller;
  bool _isClosing = false;
  late bool _isDarkMode = widget.isDarkMode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDisplayName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(value);
  }

  void _save() {
    if (_controller.text.trim().length > _maxProfileNameLength) {
      setState(() => _error = 'Name must be 120 characters or fewer.');
      return;
    }
    _close(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: WireframeColors.paper,
      title: const Text('Edit profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('profile-display-name-input'),
            controller: _controller,
            autofocus: false,
            textCapitalization: TextCapitalization.words,
            maxLength: _maxProfileNameLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            decoration: InputDecoration(
              labelText: 'Display name',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          SwitchListTile.adaptive(
            key: const Key('theme-mode-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark mode'),
            value: _isDarkMode,
            onChanged: (value) {
              setState(() => _isDarkMode = value);
              widget.onThemeChanged(value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class WireframeShell extends StatelessWidget {
  const WireframeShell({
    super.key,
    required this.child,
    this.selectedNav,
    this.onNav,
    this.showBottomNav = false,
    this.bottomBar,
    this.expandedNavigationRail,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final int? selectedNav;
  final ValueChanged<int>? onNav;
  final bool showBottomNav;
  final Widget? bottomBar;
  final Widget? expandedNavigationRail;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final hasCustomerNavigation =
        bottomBar == null &&
        (showBottomNav || selectedNav != null) &&
        onNav != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isExpanded =
            ScentifyBreakpoints.sizeClassForWidth(constraints.maxWidth) ==
            ScentifyWindowSizeClass.expanded;
        final navigationRail = isExpanded
            ? expandedNavigationRail ??
                  (hasCustomerNavigation
                      ? WireBottomNav(
                          currentIndex: selectedNav,
                          onSelect: onNav!,
                          expanded: true,
                        )
                      : null)
            : null;
        final navigationBar = navigationRail != null
            ? null
            : bottomBar ??
                  (hasCustomerNavigation
                      ? WireBottomNav(
                          currentIndex: selectedNav,
                          onSelect: onNav!,
                        )
                      : null);
        final content = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ScentifyBreakpoints.maxContentWidth,
            ),
            child: SizedBox(width: double.infinity, child: child),
          ),
        );
        final body = SafeArea(
          bottom: navigationBar == null,
          child: navigationRail == null
              ? content
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    navigationRail,
                    Expanded(child: content),
                  ],
                ),
        );

        return Scaffold(
          backgroundColor: backgroundColor ?? colors.canvas,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          body: body,
          bottomNavigationBar: navigationBar,
        );
      },
    );
  }
}

class WireBottomNav extends StatelessWidget {
  const WireBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.expanded = false,
  });

  final int? currentIndex;
  final ValueChanged<int> onSelect;
  final bool expanded;

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.search_outlined, Icons.search, 'Shop'),
    (Icons.favorite_border, Icons.favorite, 'Wishlist'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Orders'),
    (Icons.person_outline, Icons.person, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final safeIndex =
        currentIndex != null &&
            currentIndex! >= 0 &&
            currentIndex! < _items.length
        ? currentIndex!
        : 0;
    final destinations = [
      for (final (index, item) in _items.indexed)
        NavigationDestination(
          key: ValueKey('bottom-nav-item-$index'),
          icon: Icon(item.$1),
          selectedIcon: Icon(item.$2),
          label: item.$3,
          tooltip: item.$3 == 'Shop' ? 'Shop and search' : item.$3,
        ),
    ];

    if (expanded) {
      return NavigationRail(
        backgroundColor: ScentifyThemeColors.of(context).paper,
        indicatorColor: ScentifyThemeColors.of(context).selected,
        minWidth: 84,
        groupAlignment: -0.8,
        labelType: NavigationRailLabelType.all,
        scrollable: true,
        selectedIndex: safeIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final (index, item) in _items.indexed)
            NavigationRailDestination(
              icon: Icon(item.$1),
              selectedIcon: Icon(item.$2),
              label: Text(item.$3, key: ValueKey('bottom-nav-item-$index')),
            ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: NavigationBar(
        backgroundColor: ScentifyThemeColors.of(context).paper,
        indicatorColor: ScentifyThemeColors.of(context).selected,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: safeIndex,
        onDestinationSelected: onSelect,
        destinations: destinations,
      ),
    );
  }
}

class ScentifyLogo extends StatelessWidget {
  const ScentifyLogo({super.key, this.size = 25, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final logoColor = color ?? ScentifyThemeColors.of(context).ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          ScentifyAssets.mark,
          width: size * 0.82,
          height: size * 0.82,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        SizedBox(width: size * 0.22),
        Text(
          'Scentify',
          style: TextStyle(
            fontFamily: _modernFontFamily,
            fontSize: size,
            letterSpacing: -0.55,
            fontWeight: FontWeight.w700,
            color: logoColor,
          ),
        ),
      ],
    );
  }
}

class ScentifyMark extends StatelessWidget {
  const ScentifyMark({super.key, this.size = 48, this.rounded = false});

  final double size;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      ScentifyAssets.appIcon,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return rounded
        ? ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: image,
          )
        : image;
  }
}

class PlaceholderImage extends StatelessWidget {
  const PlaceholderImage({
    super.key,
    this.width,
    this.height,
    this.radius = 4,
    this.circle = false,
    this.tone,
    this.backgroundColor,
    this.fit = BoxFit.cover,
    this.assetPath,
    this.imageUrl,
  });

  final double? width;
  final double? height;
  final double radius;
  final bool circle;
  final Color? tone;
  final Color? backgroundColor;
  final BoxFit fit;
  final String? assetPath;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final backdrop = backgroundColor == null
        ? colors.field
        : colors.resolveLightColor(backgroundColor!);
    final fallback = Semantics(
      label: 'Image unavailable',
      child: ColoredBox(
        color: backdrop,
        child: Center(
          child: Icon(Icons.image_outlined, size: 28, color: colors.muted),
        ),
      ),
    );
    final assetImage = assetPath == null
        ? fallback
        : Image.asset(
            assetPath!,
            fit: fit,
            errorBuilder: (_, _, _) => fallback,
          );
    final image = imageUrl == null
        ? assetImage
        : Image.network(
            imageUrl!,
            fit: fit,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : assetImage,
            errorBuilder: (_, _, _) => assetImage,
          );
    return SizedBox(
      width: width,
      height: height,
      child: circle
          ? ClipOval(
              child: ColoredBox(color: backdrop, child: image),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: ColoredBox(color: backdrop, child: image),
            ),
    );
  }
}

class WireButton extends StatelessWidget {
  const WireButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.dark = true,
    this.accent = false,
    this.icon,
    this.height = 48,
    this.fontSize = 14,
    this.radius = 18,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool dark;
  final bool accent;
  final IconData? icon;
  final double height;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final darkForeground = Theme.of(context).brightness == Brightness.dark
        ? colors.canvas
        : colors.paper;
    final foreground = dark ? darkForeground : colors.ink;
    return ScentifyPressScale(
      enabled: onPressed != null,
      child: SizedBox(
        height: height < 48 ? 48 : height,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 17),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: dark ? colors.primaryAction : colors.paper,
            foregroundColor: foreground,
            disabledBackgroundColor: colors.field,
            disabledForegroundColor: colors.muted,
            side: dark ? BorderSide.none : BorderSide(color: colors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            textStyle: TextStyle(
              fontSize: fontSize,
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class WireTopBar extends StatelessWidget {
  const WireTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
    this.centerTitle = false,
  });

  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 17),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              tooltip: 'Back',
            )
          else
            const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              textAlign: centerTitle ? TextAlign.center : TextAlign.left,
              style: ScentifyTypography.sectionTitle.copyWith(
                color: ScentifyThemeColors.of(context).ink,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class WireSearchInput extends StatefulWidget {
  const WireSearchInput({
    super.key,
    required this.inputKey,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
    this.autofocus = false,
  });

  final Key inputKey;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final bool autofocus;

  @override
  State<WireSearchInput> createState() => _WireSearchInputState();
}

class _WireSearchInputState extends State<WireSearchInput> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    const height = 48.0;
    return Focus(
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: AnimatedContainer(
        key: const Key('wire-search-input-shell'),
        duration: const Duration(milliseconds: 140),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.field,
          border: Border.all(
            color: _hasFocus ? colors.primaryAction : colors.border,
            width: _hasFocus ? 1.2 : 1,
          ),
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
        ),
        child: TextField(
          key: widget.inputKey,
          controller: widget.controller,
          autofocus: widget.autofocus,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          style: ScentifyTypography.body.copyWith(color: colors.ink),
          cursorColor: colors.primaryAction,
          decoration: InputDecoration(
            filled: false,
            hintText: widget.hint,
            hintStyle: ScentifyTypography.supporting.copyWith(
              fontSize: 13,
              color: colors.muted,
            ),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: colors.ink),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: 24,
              height: height,
            ),
            suffixIcon: widget.onClear == null
                ? null
                : IconButton(
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: height,
                    ),
                    tooltip: 'Clear search',
                  ),
            suffixIconConstraints: widget.onClear == null
                ? const BoxConstraints()
                : const BoxConstraints.tightFor(width: 48, height: height),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.only(left: 8),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onViewAll,
    this.accentLetter,
  });

  final String title;
  final VoidCallback? onViewAll;
  final String? accentLetter;

  @override
  Widget build(BuildContext context) {
    return ScentifySectionHeader(
      title: title,
      onSeeAll: onViewAll,
      seeAllLabel: 'See all',
    );
  }
}

class CustomerSectionTitle extends StatelessWidget {
  const CustomerSectionTitle({super.key, required this.title, this.action});

  final String title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: _modernFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null)
          Text(
            action!,
            style: const TextStyle(
              fontSize: 12,
              color: WireframeColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// A low-noise label used to establish the reading order inside a wireframe.
/// It intentionally stays smaller and lighter than section titles so it can be
/// replaced by a final visual style later without changing the layout.
class WireEyebrow extends StatelessWidget {
  const WireEyebrow(
    this.label, {
    super.key,
    this.color = WireframeColors.muted,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 0.1,
        color: color == WireframeColors.gold ? WireframeColors.muted : color,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Groups related content without turning every element into a separate card.
/// The single surface is the main anti-slop rule for the wireframe: hierarchy
/// comes from grouping and spacing, not from decorative components.
class WireSurface extends StatelessWidget {
  const WireSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color = WireframeColors.paper,
    this.border = false,
    this.radius = 18,
    this.shadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool border;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return ScentifyCard(
      padding: padding,
      color: color,
      border: border,
      radius: radius,
      shadow: shadow,
      child: child,
    );
  }
}

class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScentifySelectableChip(
      label: label,
      selected: selected,
      onTap: onTap,
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  static const loadDuration = Duration(milliseconds: 2800);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: SplashPage.loadDuration,
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return WireframeShell(
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: constraints.maxHeight * 0.68,
                      child: Image.asset(
                        ScentifyAssets.onboardingSignatureScent,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, -0.72),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ScentifyLogo(size: 34),
                          const SizedBox(height: 8),
                          Text(
                            'More than fragrance. A more you.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.ink,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 112,
                height: 4,
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const Key('splash-progress'),
                      value: _progressController.value,
                      minHeight: 4,
                      backgroundColor: colors.field,
                      color: colors.primaryAction,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingContent {
  const OnboardingContent({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.assetPath,
    required this.buttonLabel,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String assetPath;
  final String buttonLabel;
}

const onboardingContents = <OnboardingContent>[
  OnboardingContent(
    eyebrow: 'Discover your signature',
    title: 'Discover fragrances for every you.',
    description: 'Explore a world of scents, from everyday favorites to new discoveries.',
    assetPath: ScentifyAssets.onboardingSignatureScent,
    buttonLabel: 'Get started',
  ),
  OnboardingContent(
    eyebrow: 'Shop with confidence',
    title: 'Find your next favorite.',
    description: 'Browse favorite brands and review every checkout detail before you pay.',
    assetPath: ScentifyAssets.onboardingRecommendations,
    buttonLabel: 'Next',
  ),
  OnboardingContent(
    eyebrow: 'A more you, every day',
    title: 'Make fragrance feel personal.',
    description:
        'Save your favorites and build a collection that feels personal.',
    assetPath: ScentifyAssets.onboardingFavorites,
    buttonLabel: 'Next',
  ),
  OnboardingContent(
    eyebrow: 'Your favorites, together',
    title: 'Keep the scents you love close.',
    description:
        'Find your bottle, check out simply, and enjoy the scent journey.',
    assetPath: ScentifyAssets.onboardingAuthenticShopping,
    buttonLabel: 'Create my account',
  ),
];

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.stage,
    required this.onNext,
    required this.onSkip,
  });

  static const stageCount = 4;

  final int stage;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final currentStage = stage < 0
        ? 0
        : stage >= stageCount
        ? stageCount - 1
        : stage;
    final content = onboardingContents[currentStage];
    final colors = ScentifyThemeColors.of(context);

    return WireframeShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 700;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 20 : 24,
              8,
              isCompact ? 20 : 24,
              16,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onSkip,
                      child: const Text('Skip'),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final offset = Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
                    child: _OnboardingStage(
                      key: ValueKey(currentStage),
                      content: content,
                      compact: isCompact,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            for (var index = 0; index < stageCount; index++)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _Dot(active: index == currentStage),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('onboarding-next'),
                        tooltip: content.buttonLabel,
                        onPressed: onNext,
                        style: IconButton.styleFrom(
                          fixedSize: const Size(56, 56),
                          backgroundColor: colors.primaryAction,
                          foregroundColor: Colors.white,
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OnboardingStage extends StatelessWidget {
  const _OnboardingStage({
    super.key,
    required this.content,
    required this.compact,
  });

  final OnboardingContent content;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        WireEyebrow(content.eyebrow, color: colors.primaryAction),
        const SizedBox(height: 8),
        Text(
          content.title,
          style: ScentifyTypography.title.copyWith(
            fontSize: compact ? 25 : 29,
            color: colors.ink,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            content.description,
            style: ScentifyTypography.body.copyWith(color: colors.muted),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Align(
            alignment: const Alignment(0, -0.2),
            child: Image.asset(
              content.assetPath,
              key: const Key('onboarding-hero-art'),
              fit: BoxFit.contain,
              semanticLabel: content.title,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Container(
      width: active ? 18 : 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: active ? colors.primaryAction : colors.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

typedef AuthSubmitCallback = Future<void> Function({
  required bool register,
  String? displayName,
  required String email,
  required String password,
});

typedef GoogleAuthCallback = Future<void> Function();

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.onSubmit,
    required this.onGoogleSignIn,
    this.onForgotPassword,
  });

  final AuthSubmitCallback onSubmit;
  final GoogleAuthCallback onGoogleSignIn;
  final Future<void> Function(String email)? onForgotPassword;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _register = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSubmitting = false;
  bool _isGoogleSubmitting = false;
  String? _errorMessage;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validationMessage() {
    if (_register && _nameController.text.trim().isEmpty) {
      return 'Enter your full name.';
    }
    if (_register &&
        _nameController.text.trim().length > _maxProfileNameLength) {
      return 'Full name must be 120 characters or fewer.';
    }
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return 'Enter your email address.';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (_passwordController.text.isEmpty) {
      return 'Enter your password.';
    }
    if (_passwordController.text.length < 6) {
      return 'Use a password with at least 6 characters.';
    }
    if (_register &&
        _passwordController.text != _confirmPasswordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submit() async {
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      setState(() => _errorMessage = validationMessage);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onSubmit(
        register: _register,
        displayName: _register ? _nameController.text.trim() : null,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on SupabaseAuthFailure catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Authentication failed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isSubmitting) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _isGoogleSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.onGoogleSignIn();
    } on SupabaseAuthFailure catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Google sign-in failed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isGoogleSubmitting = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Enter your email address first.');
      return;
    }
    final callback = widget.onForgotPassword;
    if (callback == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await callback(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on SupabaseAuthFailure catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Unable to send the reset email. Try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _toggleRegister() {
    setState(() {
      _register = !_register;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.height < 700;
    final colors = ScentifyThemeColors.of(context);
    const fieldHeight = 48.0;
    final title = _register ? 'Create your account' : 'Welcome back';
    final subtitle = _register
        ? 'Create an account to save your favorite scents.'
        : 'Sign in to save favorites and manage your orders.';

    return WireframeShell(
      key: const Key('auth-page'),
      resizeToAvoidBottomInset: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaleLoginToFit = !_register && constraints.maxHeight < 780;
          final form = Column(
            key: const Key('auth-form'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: ScentifyLogo(size: isCompact ? 24 : 30)),
              SizedBox(height: isCompact ? 16 : 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: _modernFontFamily,
                  fontSize: isCompact ? 24 : 30,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: WireframeColors.muted,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.danger),
                ),
              ],
              SizedBox(height: isCompact ? 18 : 28),
              if (_register) ...[
                WireTextField(
                  key: const Key('auth-name'),
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  height: fieldHeight,
                  labelFontSize: 12,
                  textFontSize: 14,
                  radius: 8,
                  outlined: true,
                ),
                SizedBox(height: isCompact ? 10 : 14),
              ],
              WireTextField(
                key: const Key('auth-email'),
                controller: _emailController,
                label: 'Email',
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                height: fieldHeight,
                labelFontSize: 12,
                textFontSize: 14,
                radius: 8,
                outlined: true,
              ),
              SizedBox(height: isCompact ? 10 : 14),
              WireTextField(
                key: const Key('auth-password'),
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                onSuffixTap: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                height: fieldHeight,
                labelFontSize: 12,
                textFontSize: 14,
                radius: 8,
                outlined: true,
              ),
              if (_register) ...[
                SizedBox(height: isCompact ? 10 : 14),
                WireTextField(
                  key: const Key('auth-confirm-password'),
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline,
                  obscure: _obscureConfirmPassword,
                  onSuffixTap: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                  height: fieldHeight,
                  labelFontSize: 12,
                  textFontSize: 14,
                  radius: 8,
                  outlined: true,
                ),
              ],
              if (!_register)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isSubmitting ? null : _resetPassword,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isCompact ? 4 : 8,
                      ),
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                  ),
                ),
              SizedBox(height: isCompact ? 4 : 8),
              WireButton(
                key: const Key('login-submit'),
                label: _isSubmitting
                    ? 'Please wait...'
                    : _register
                    ? 'Create account'
                    : 'Log in',
                onPressed: _isSubmitting ? null : _submit,
                height: isCompact ? 44 : 48,
                fontSize: 14,
                radius: 24,
              ),
              SizedBox(height: isCompact ? 14 : 20),
              const Row(
                children: [
                  Expanded(child: Divider(color: WireframeColors.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: WireframeColors.border)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('google-sign-in'),
                  onPressed: _isSubmitting ? null : _signInWithGoogle,
                  icon: Image.asset(
                    ScentifyAssets.googleLogo,
                    key: const Key('google-logo'),
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                    semanticLabel: 'Google logo',
                  ),
                  label: Text(
                    _isGoogleSubmitting
                        ? 'Connecting...'
                        : 'Continue with Google',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.ink,
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.transparent,
                    side: BorderSide(color: colors.border),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: isCompact ? 8 : 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _register
                          ? 'Already have an account?'
                          : 'New to Scentify?',
                      style: const TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                    TextButton(
                      key: Key(
                        _register ? 'auth-login-toggle' : 'auth-signup-toggle',
                      ),
                      onPressed: _isSubmitting ? null : _toggleRegister,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 8,
                        ),
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(
                        _register ? 'Log in' : 'Create account',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: WireframeColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Terms of Use · Privacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: WireframeColors.muted,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          );

          final content = Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              isCompact ? 10 : 18,
              24,
              isCompact ? 16 : 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: scaleLoginToFit
                    ? FittedBox(
                        alignment: Alignment.topCenter,
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: (constraints.maxWidth - 48).clamp(0.0, 380.0),
                          child: form,
                        ),
                      )
                    : form,
              ),
            ),
          );
          return _register
              ? SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: content,
                )
              : content;
        },
      ),
    );
  }
}

class WireTextField extends StatelessWidget {
  const WireTextField({
    super.key,
    required this.label,
    required this.icon,
    this.controller,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSuffixTap,
    this.obscure = false,
    this.maxLength,
    this.errorText,
    this.height = 48,
    this.labelFontSize = 12,
    this.textFontSize = 14,
    this.radius = 6,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSuffixTap;
  final bool obscure;
  final int? maxLength;
  final String? errorText;
  final double height;
  final double labelFontSize;
  final double textFontSize;
  final double radius;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final verticalPadding =
        Theme.of(context).inputDecorationTheme.contentPadding?.vertical ?? 24;
    final fieldHeight = textScaler.scale(textFontSize) + verticalPadding;
    final resolvedHeight = height > fieldHeight ? height : fieldHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!outlined) ...[
          Text(
            label,
            style: TextStyle(fontSize: labelFontSize, color: colors.muted),
          ),
          const SizedBox(height: 5),
        ],
        SizedBox(
          height: resolvedHeight,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onChanged: onChanged,
            obscureText: obscure,
            maxLength: maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            style: TextStyle(fontSize: textFontSize, color: colors.ink),
            decoration: InputDecoration(
              labelText: outlined ? label : null,
              labelStyle: TextStyle(fontSize: labelFontSize, color: colors.ink),
              counterText: maxLength == null ? null : '',
              prefixIcon: outlined
                  ? null
                  : Icon(icon, size: 15, color: colors.muted),
              suffixIcon: onSuffixTap == null
                  ? null
                  : IconButton(
                      onPressed: onSuffixTap,
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 17,
                      ),
                      splashRadius: 18,
                    ),
              filled: true,
              fillColor: outlined ? colors.paper : colors.field,
              contentPadding: const EdgeInsets.symmetric(horizontal: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: outlined
                    ? BorderSide(color: colors.border)
                    : BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: outlined
                    ? BorderSide(color: colors.border)
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: BorderSide(color: colors.primaryAction),
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: colors.danger),
            ),
          ),
      ],
    );
  }
}

class CartIconButton extends StatelessWidget {
  const CartIconButton({
    super.key,
    required this.count,
    required this.onPressed,
    this.onDark = false,
  });

  final int count;
  final VoidCallback onPressed;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Tooltip(
            message: 'Cart',
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: onDark
                    ? BoxDecoration(
                        color: colors.ink.withValues(alpha: 0.34),
                        border: Border.all(
                          color: colors.softGold.withValues(alpha: 0.7),
                        ),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Icon(
                  Icons.shopping_bag_outlined,
                  size: 20,
                  color: onDark ? colors.paper : colors.ink,
                ),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: 1,
              top: 1,
              child: AnimatedSwitcher(
                key: const Key('cart-count-badge'),
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: child,
                ),
                child: Container(
                  key: ValueKey('cart-count-badge-$count'),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryAction,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.paper, width: 1.5),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NotificationIconButton extends StatelessWidget {
  const NotificationIconButton({
    super.key,
    required this.count,
    required this.onPressed,
    this.onDark = false,
  });

  final int count;
  final VoidCallback onPressed;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Notifications',
      child: InkWell(
        key: const Key('notifications-button'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: onDark
                    ? BoxDecoration(
                        color: colors.ink.withValues(alpha: 0.34),
                        border: Border.all(
                          color: colors.softGold.withValues(alpha: 0.7),
                        ),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Icon(
                  Icons.notifications_none,
                  size: 21,
                  color: onDark ? colors.paper : colors.ink,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    key: const Key('notification-count-badge'),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.paper, width: 1.5),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onNav,
    required this.cartCount,
    required this.products,
    required this.wishlistIds,
    required this.notificationCount,
    this.catalogError,
    required this.onCart,
    required this.onNotifications,
    required this.onCategory,
    required this.onBrowseCatalog,
    required this.onTopPicks,
    required this.onProduct,
    required this.onAddToCart,
    required this.onFavorite,
  });

  final ValueChanged<int> onNav;
  final int cartCount;
  final List<Product> products;
  final Set<String> wishlistIds;
  final int notificationCount;
  final String? catalogError;
  final VoidCallback onCart;
  final VoidCallback onNotifications;
  final ValueChanged<String> onCategory;
  final VoidCallback onBrowseCatalog;
  final VoidCallback onTopPicks;
  final ValueChanged<Product> onProduct;
  final ValueChanged<Product> onAddToCart;
  final ValueChanged<Product> onFavorite;

  @override
  Widget build(BuildContext context) {
    final topPicks = products.take(3).toList(growable: false);
    return WireframeShell(
      selectedNav: 0,
      onNav: onNav,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: ScentifyLogo(size: 20)),
                CartIconButton(count: cartCount, onPressed: onCart),
                NotificationIconButton(
                  count: notificationCount,
                  onPressed: onNotifications,
                ),
              ],
            ),
            const SizedBox(height: 16),
            HomeSearchBar(onTap: onBrowseCatalog),
            const SizedBox(height: 24),
            HomeHeroCarousel(
              cartCount: cartCount,
              notificationCount: notificationCount,
              onCart: onCart,
              onNotifications: onNotifications,
              onBrowse: onBrowseCatalog,
              onTopPicks: onTopPicks,
              showChrome: false,
            ),
            const SizedBox(height: 24),
            const ScentifyCard(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              shadow: false,
              child: HomeServiceStrip(),
            ),
            const SizedBox(height: 30),
            const SectionHeader(title: 'Shop by Category', accentLetter: 'C'),
            const SizedBox(height: 12),
            GridView.count(
              key: const Key('home-category-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 4,
              mainAxisExtent:
                  100 +
                  ((MediaQuery.textScalerOf(context).scale(12) / 12 - 1).clamp(
                        0,
                        2,
                      ) *
                      32),
              children: [
                CategoryShortcut(
                  label: 'For Her',
                  onTap: () => onCategory('Women'),
                ),
                CategoryShortcut(
                  label: 'For Him',
                  onTap: () => onCategory('Men'),
                ),
                CategoryShortcut(
                  label: 'Unisex',
                  onTap: () => onCategory('Unisex'),
                ),
                CategoryShortcut(label: 'Top Picks', onTap: onTopPicks),
                CategoryShortcut(
                  label: 'Floral',
                  onTap: () => onCategory('Floral'),
                ),
                CategoryShortcut(
                  label: 'Fresh',
                  onTap: () => onCategory('Fresh'),
                ),
                CategoryShortcut(
                  label: 'Woody',
                  onTap: () => onCategory('Woody'),
                ),
                CategoryShortcut(label: 'Bestsellers', onTap: onTopPicks),
              ],
            ),
            const SizedBox(height: 28),
            BrowseCatalogModule(onBrowseCatalog: onBrowseCatalog),
            const SizedBox(height: 30),
            SectionHeader(
              key: const Key('home-top-picks-section'),
              title: 'Top Picks',
              onViewAll: onTopPicks,
            ),
            const SizedBox(height: 12),
            if (topPicks.isEmpty)
              SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    catalogError ?? 'No scents available yet.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: WireframeColors.muted,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height:
                    350.0 +
                    ((MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                                .clamp(0.0, 2.0) *
                            110.0)
                        .toDouble(),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: topPicks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 11),
                  itemBuilder: (_, index) => ProductCard(
                    product: topPicks[index],
                    onTap: () => onProduct(topPicks[index]),
                    onAddToCart: () => onAddToCart(topPicks[index]),
                    isFavorite: wishlistIds.contains(topPicks[index].id),
                    onFavorite: () => onFavorite(topPicks[index]),
                  ),
                ),
              ),
            const SizedBox(height: 30),
            SectionHeader(title: 'Featured Brands', onViewAll: onBrowseCatalog),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 2),
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
          ],
        ),
      ),
    );
  }
}

class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Semantics(
      button: true,
      label: 'Search scents, brands, or notes',
      child: Material(
        color: colors.field,
        borderRadius: BorderRadius.circular(ScentifyRadius.medium),
        child: InkWell(
          key: const Key('home-search-bar'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(ScentifyRadius.medium),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 20, color: colors.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Search scents, brands, or notes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ScentifyTypography.supporting.copyWith(
                      fontSize: 13,
                      color: colors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeroSlide {
  const _HomeHeroSlide({
    required this.eyebrow,
    required this.title,
    required this.assetPath,
    required this.backdropPath,
    required this.buttonLabel,
    this.opensTopPicks = false,
    this.fit = BoxFit.cover,
    this.backgroundColor = WireframeColors.darkSurface,
  });

  final String eyebrow;
  final String title;
  final String assetPath;
  final String backdropPath;
  final String buttonLabel;
  final bool opensTopPicks;
  final BoxFit fit;
  final Color backgroundColor;
}

const _homeHeroSlides = <_HomeHeroSlide>[
  _HomeHeroSlide(
    eyebrow: 'New arrivals',
    title: 'Fresh scents\njust landed',
    assetPath: ScentifyAssets.onboardingRecommendations,
    backdropPath: ScentifyAssets.hero,
    buttonLabel: 'Shop new arrivals',
    fit: BoxFit.contain,
    backgroundColor: ScentifyColors.surfaceMuted,
  ),
  _HomeHeroSlide(
    eyebrow: 'Evening edit',
    title: 'Find your\nafter-dark scent',
    assetPath: ScentifyAssets.libre,
    backdropPath: ScentifyAssets.authEditorialHero,
    buttonLabel: 'Shop evening scents',
    fit: BoxFit.contain,
    backgroundColor: ScentifyColors.surfaceMuted,
  ),
  _HomeHeroSlide(
    eyebrow: 'Top picks',
    title: 'Bottles worth\nwearing',
    assetPath: ScentifyAssets.onboardingAuthenticShopping,
    backdropPath: ScentifyAssets.heroEvening,
    buttonLabel: 'View top picks',
    opensTopPicks: true,
    fit: BoxFit.contain,
    backgroundColor: ScentifyColors.surfaceMuted,
  ),
];

class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    super.key,
    required this.cartCount,
    required this.notificationCount,
    required this.onCart,
    required this.onNotifications,
    required this.onBrowse,
    required this.onTopPicks,
    this.showChrome = true,
  });

  final int cartCount;
  final int notificationCount;
  final VoidCallback onCart;
  final VoidCallback onNotifications;
  final VoidCallback onBrowse;
  final VoidCallback onTopPicks;
  final bool showChrome;

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  late final PageController _controller;
  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (!_controller.hasClients || page == _currentPage) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(31) / 31;
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseHeroHeight =
            (constraints.maxWidth * 0.62).clamp(190.0, 230.0).toDouble() +
            8 +
            (widget.showChrome ? 48 : 0);
        final heroHeight =
            baseHeroHeight + ((textScale - 1).clamp(0.0, 2.0) * 160);
        return Column(
          children: [
            SizedBox(
              height: heroHeight,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    ScentifyRadius.extraLarge,
                  ),
                  border: Border.all(
                    color: ScentifyThemeColors.of(context).border,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    ScentifyRadius.extraLarge,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        key: const Key('home-hero-carousel'),
                        controller: _controller,
                        itemCount: _homeHeroSlides.length,
                        physics: const PageScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        onPageChanged: (page) =>
                            setState(() => _currentPage = page),
                        itemBuilder: (context, index) {
                          final slide = _homeHeroSlides[index];
                          final onTap = slide.opensTopPicks
                              ? widget.onTopPicks
                              : widget.onBrowse;
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final titleFontSize = constraints.maxWidth < 420
                                  ? 21.0
                                  : 29.0;
                              final artworkWidth =
                                  textScale >= 1.5 || constraints.maxWidth < 340
                                  ? 0.0
                                  : constraints.maxWidth * 0.42;
                              final textWidth = artworkWidth == 0
                                  ? constraints.maxWidth - 36
                                  : (constraints.maxWidth - artworkWidth - 36)
                                        .clamp(120.0, 190.0)
                                        .toDouble();
                              return InkWell(
                                key: ValueKey('home-hero-slide-$index'),
                                onTap: onTap,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      key: ValueKey(
                                        'home-hero-backdrop-$index',
                                      ),
                                      slide.backdropPath,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.centerRight,
                                      errorBuilder: (_, _, _) => ColoredBox(
                                        color: ScentifyThemeColors.of(context)
                                            .resolveLightColor(
                                              slide.backgroundColor,
                                            ),
                                      ),
                                    ),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            ScentifyThemeColors.of(context)
                                                .canvas
                                                .withValues(alpha: 0.96),
                                            ScentifyThemeColors.of(context)
                                                .canvas
                                                .withValues(alpha: 0.74),
                                            ScentifyThemeColors.of(context)
                                                .canvas
                                                .withValues(alpha: 0.06),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (artworkWidth > 0)
                                      Positioned(
                                        top: 8,
                                        right: 6,
                                        bottom: 8,
                                        width: artworkWidth + 18,
                                        child: Image.asset(
                                          key: ValueKey(
                                            'home-hero-artwork-$index',
                                          ),
                                          slide.assetPath,
                                          fit: slide.fit,
                                          alignment: Alignment.centerRight,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                    if (widget.showChrome)
                                      Positioned(
                                        top: 14,
                                        left: 17,
                                        right: 12,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: ScentifyLogo(
                                                size: 19,
                                                color: ScentifyThemeColors.of(
                                                  context,
                                                ).ink,
                                              ),
                                            ),
                                            CartIconButton(
                                              count: widget.cartCount,
                                              onPressed: widget.onCart,
                                            ),
                                            const SizedBox(width: 4),
                                            NotificationIconButton(
                                              count: widget.notificationCount,
                                              onPressed: widget.onNotifications,
                                            ),
                                          ],
                                        ),
                                      ),
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        18,
                                        widget.showChrome ? 56 : 18,
                                        14,
                                        8,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: SizedBox(
                                          width: textWidth,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              WireEyebrow(
                                                slide.eyebrow,
                                                color: ScentifyThemeColors.of(
                                                  context,
                                                ).muted,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                slide.title,
                                                style: ScentifyTypography
                                                    .display
                                                    .copyWith(
                                                      fontSize: titleFontSize,
                                                      color:
                                                          ScentifyThemeColors.of(
                                                            context,
                                                          ).ink,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              SmallButton(
                                                label: slide.buttonLabel,
                                                onPressed: onTap,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < _homeHeroSlides.length; index++)
                  InkWell(
                    key: ValueKey('home-hero-dot-$index'),
                    onTap: () => _goTo(index),
                    borderRadius: BorderRadius.circular(99),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: _Dot(active: index == _currentPage),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(118, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ScentifyRadius.small),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class HomeServiceStrip extends StatelessWidget {
  const HomeServiceStrip({super.key});

  static const _services = [
    (Icons.spa_outlined, 'Curated scents'),
    (Icons.tune_rounded, 'Size options'),
    (Icons.favorite_border_rounded, 'Saved wishlist'),
    (Icons.local_shipping_outlined, 'Order tracking'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    const serviceTints = [
      ScentifyColors.sage,
      ScentifyColors.smoke,
      ScentifyColors.sand,
      ScentifyColors.blush,
    ];
    final labelFontSize = MediaQuery.textScalerOf(context).scale(12);
    final scaledHeight = 34 + labelFontSize * 3.0;
    return SizedBox(
      height: scaledHeight < 68 ? 68 : scaledHeight,
      child: Row(
        children: [
          for (var index = 0; index < _services.length; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == _services.length - 1 ? 0 : 6,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.resolveLightColor(serviceTints[index]),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _services[index].$1,
                        size: 15,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _services[index].$2,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: colors.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BrowseCatalogModule extends StatelessWidget {
  const BrowseCatalogModule({super.key, required this.onBrowseCatalog});

  final VoidCallback onBrowseCatalog;

  @override
  Widget build(BuildContext context) {
    return WireSurface(
      key: const Key('home-browse-catalog'),
      color: WireframeColors.paper,
      radius: 16,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: WireframeColors.field,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search,
              size: 16,
              color: WireframeColors.ink,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Browse every scent',
                  style: TextStyle(
                    fontFamily: _modernFontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Explore all products with search, filters, and sorting.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: WireframeColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 132,
            child: WireButton(
              key: const Key('home-browse-catalog-cta'),
              label: 'Shop all products',
              height: 48,
              fontSize: 12,
              dark: false,
              onPressed: onBrowseCatalog,
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryShortcut extends StatelessWidget {
  const CategoryShortcut({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final categoryColor = switch (label) {
      'For Her' || 'Floral' => ScentifyColors.blush,
      'For Him' || 'Woody' => ScentifyColors.smoke,
      'Unisex' || 'Fresh' => ScentifyColors.sage,
      'Top Picks' => ScentifyColors.sand,
      _ => ScentifyColors.plum,
    };
    final imageAsset = switch (label) {
      'For Her' => ScentifyAssets.cocoMademoiselle,
      'For Him' => ScentifyAssets.sauvage,
      'Unisex' => ScentifyAssets.santal33,
      'Top Picks' => ScentifyAssets.baccaratRouge540,
      'Bestsellers' => ScentifyAssets.libre,
      'Floral' => ScentifyAssets.forHer,
      'Fresh' => ScentifyAssets.englishPearFreesia,
      'Woody' => ScentifyAssets.oudWood,
      _ => ScentifyAssets.cocoMademoiselle,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
        decoration: BoxDecoration(
          color: colors.resolveLightColor(categoryColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: PlaceholderImage(
                key: ValueKey(
                  'home-category-image-${label.toLowerCase().replaceAll(' ', '-')}',
                ),
                radius: 12,
                fit: BoxFit.contain,
                tone: categoryColor,
                backgroundColor: Colors.transparent,
                assetPath: imageAsset,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ScentifyTypography.caption.copyWith(color: colors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class BrandTile extends StatelessWidget {
  const BrandTile({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final logo = switch (label) {
      'Chanel' => (ScentifyAssets.chanelLogo, const Size(42, 24)),
      'Dior' => (ScentifyAssets.diorLogo, const Size(44, 20)),
      'YSL' => (ScentifyAssets.yslLogo, const Size(30, 28)),
      'Gucci' => (ScentifyAssets.gucciLogo, const Size(44, 18)),
      'Versace' => (ScentifyAssets.versaceLogo, const Size(34, 28)),
      _ => (ScentifyAssets.chanelLogo, const Size(42, 24)),
    };
    return Semantics(
      label: '$label brand',
      child: SizedBox(
        width: 68,
        height: 86,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.field,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  logo.$1,
                  width: logo.$2.width,
                  height: logo.$2.height,
                  fit: BoxFit.contain,
                  color: colors.ink,
                  colorBlendMode: BlendMode.srcIn,
                  semanticLabel: '$label logo',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ScentifyTypography.caption.copyWith(
                  fontSize: 10,
                  color: colors.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    required this.isFavorite,
    required this.onFavorite,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final available = product.isAvailable;
    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(ScentifyRadius.large),
      child: Container(
        width: 162,
        decoration: BoxDecoration(
          color: ScentifyThemeColors.of(context).canvas,
          borderRadius: BorderRadius.circular(ScentifyRadius.small),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        ScentifyRadius.medium,
                      ),
                      child: PlaceholderImage(
                        radius: ScentifyRadius.small,
                        fit: BoxFit.contain,
                        tone: productTone(product),
                        backgroundColor: ScentifyColors.surfaceMuted,
                        assetPath: productImageAsset(product),
                        imageUrl: productImageUrl(product),
                      ),
                    ),
                  ),
                  if (!available)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.58),
                        alignment: Alignment.center,
                        child: _UnavailableTag(),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ProductFavoriteButton(
                      product: product,
                      isFavorite: isFavorite,
                      onFavorite: onFavorite,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0,
                        color: ScentifyThemeColors.of(context).muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _modernFontFamily,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          formatPrice(product.price),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          product.volume,
                          style: TextStyle(
                            fontSize: 11,
                            color: ScentifyThemeColors.of(context).muted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: available ? onAddToCart : null,
                        icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                        label: const Text('Add to Cart'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ScentifyThemeColors.of(context).ink,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductFavoriteButton extends StatelessWidget {
  const ProductFavoriteButton({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavorite,
  });

  final Product product;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final tooltip = isFavorite
        ? 'Remove ${product.name} from wishlist'
        : 'Add ${product.name} to wishlist';

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onFavorite();
          },
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  key: ValueKey(isFavorite),
                  size: 19,
                  color: isFavorite
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? ScentifyThemeColors.of(context).softGold
                            : ScentifyColors.champagne)
                      : ScentifyThemeColors.of(context).ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.onNav,
    required this.onAddToCart,
    required this.onFilter,
    required this.onProduct,
    required this.onGenderChanged,
    required this.products,
    required this.wishlistIds,
    required this.onFavorite,
    required this.filters,
    this.catalogError,
    this.loading = false,
  });

  final List<Product> products;
  final String? catalogError;
  final bool loading;
  final ValueChanged<int> onNav;
  final ValueChanged<Product> onAddToCart;
  final VoidCallback onFilter;
  final ValueChanged<Product> onProduct;
  final ValueChanged<String> onGenderChanged;
  final Set<String> wishlistIds;
  final ValueChanged<Product> onFavorite;
  final CatalogFilters filters;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _searchController = TextEditingController();
  String _query = '';
  late String _selectedGender;
  _CatalogSort _sort = _CatalogSort.featured;

  @override
  void initState() {
    super.initState();
    _selectedGender = widget.filters.gender;
  }

  @override
  void didUpdateWidget(covariant CatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) {
      _selectedGender = widget.filters.gender;
    }
  }

  List<Product> get _filteredProducts {
    final query = _query.trim().toLowerCase();
    final products = widget.products.where((product) {
      final matchesQuery =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.description.toLowerCase().contains(query) ||
          product.topNotes.any((note) => note.toLowerCase().contains(query)) ||
          product.heartNotes.any(
            (note) => note.toLowerCase().contains(query),
          ) ||
          product.baseNotes.any((note) => note.toLowerCase().contains(query));
      final matchesGender =
          _selectedGender == 'All' || product.gender == _selectedGender;
      final matchesBrand =
          widget.filters.brands.isEmpty ||
          widget.filters.brands.contains(product.brand);
      final matchesPrice =
          product.price >= widget.filters.priceRange.start &&
          product.price <= widget.filters.priceRange.end;
      final matchesFamily =
          widget.filters.families.isEmpty ||
          widget.filters.families.any(
            (family) => _productMatchesFamily(product, family),
          );
      return matchesQuery &&
          matchesGender &&
          matchesBrand &&
          matchesPrice &&
          matchesFamily;
    }).toList();

    switch (_sort) {
      case _CatalogSort.featured:
        break;
      case _CatalogSort.priceLowToHigh:
        products.sort((a, b) => a.price.compareTo(b.price));
      case _CatalogSort.priceHighToLow:
        products.sort((a, b) => b.price.compareTo(a.price));
    }

    return products;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  bool _productMatchesFamily(Product product, String family) {
    final copy = [
      product.description,
      ...product.topNotes,
      ...product.heartNotes,
      ...product.baseNotes,
    ].join(' ').toLowerCase();
    final signals = switch (family) {
      'Floral' => ['rose', 'jasmine', 'flower', 'floral', 'iris', 'orchid'],
      'Fresh' => ['fresh', 'marine', 'aquatic', 'mint', 'green'],
      'Woody' => ['wood', 'cedar', 'sandalwood', 'oud', 'vetiver'],
      'Citrus' => ['citrus', 'bergamot', 'lemon', 'orange', 'mandarin'],
      'Oriental' => ['amber', 'spice', 'oriental', 'incense'],
      'Gourmand' => ['vanilla', 'caramel', 'coffee', 'cocoa', 'sweet'],
      _ => <String>[],
    };
    return signals.any(copy.contains);
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;

    return WireframeShell(
      showBottomNav: true,
      selectedNav: 1,
      onNav: widget.onNav,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 3, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WireTopBar(
                  title: 'Shop all scents',
                  actions: [
                    Badge(
                      isLabelVisible: widget.filters.activeCount > 0,
                      label: Text('${widget.filters.activeCount}'),
                      backgroundColor: ScentifyThemeColors.of(context).softGold,
                      textColor: ScentifyThemeColors.of(context).ink,
                      child: IconButton(
                        onPressed: widget.onFilter,
                        icon: const Icon(Icons.tune_rounded, size: 19),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 48,
                          height: 48,
                        ),
                        tooltip: 'Filters',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                WireSearchInput(
                  inputKey: const Key('catalog-search-input'),
                  controller: _searchController,
                  autofocus: false,
                  hint: 'Search scents, brands, or notes',
                  onChanged: (value) => setState(() => _query = value),
                  onClear: _query.isEmpty ? null : _clearSearch,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                for (final gender in const ['All', 'Women', 'Men', 'Unisex'])
                  _FilterChip(
                    label: gender,
                    selected: _selectedGender == gender,
                    onTap: () {
                      setState(() => _selectedGender = gender);
                      widget.onGenderChanged(gender);
                    },
                  ),
              ],
            ),
          ),
          if (widget.filters.families.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final family in const [
                      'Floral',
                      'Fresh',
                      'Woody',
                      'Citrus',
                      'Oriental',
                      'Gourmand',
                    ])
                      if (widget.filters.families.contains(family))
                        Chip(
                          avatar: const Icon(Icons.check_rounded, size: 16),
                          label: Text(family),
                          backgroundColor: ScentifyThemeColors.of(context)
                              .selected,
                          labelStyle: TextStyle(
                            color: ScentifyThemeColors.of(context).brassInk,
                            fontWeight: FontWeight.w600,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(
              children: [
                PopupMenuButton<_CatalogSort>(
                  key: const Key('catalog-sort'),
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  padding: EdgeInsets.zero,
                  tooltip: 'Sort products',
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _CatalogSort.featured,
                      child: Text('Featured', style: TextStyle(fontSize: 14)),
                    ),
                    PopupMenuItem(
                      value: _CatalogSort.priceLowToHigh,
                      child: Text(
                        'Price: low to high',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    PopupMenuItem(
                      value: _CatalogSort.priceHighToLow,
                      child: Text(
                        'Price: high to low',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                  child: const SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sort',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.keyboard_arrow_down, size: 13),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${products.length} scents',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (widget.loading)
            const Expanded(child: CatalogSkeletonGrid())
          else if (products.isEmpty)
            Expanded(
              child: CatalogEmptyState(
                query: _query,
                error: widget.catalogError,
                onClear: _clearSearch,
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = ScentifyBreakpoints.catalogColumnCount(
                    constraints.maxWidth,
                  );
                  final gridWidth = ScentifyBreakpoints.catalogGridWidth(
                    constraints.maxWidth,
                    columns,
                  );
                  final tileWidth = ScentifyBreakpoints.catalogTileWidth(
                    gridWidth,
                    columns,
                  );
                  final tileExtent =
                      tileWidth +
                      ScentifyBreakpoints.catalogTileHeightOffset +
                      ((MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                                  .clamp(0.0, 2.0) *
                              110.0)
                          .toDouble();

                  return Center(
                    child: SizedBox(
                      width: gridWidth,
                      child: GridView.builder(
                        key: const Key('catalog-product-grid'),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing:
                              ScentifyBreakpoints.catalogCrossAxisSpacing,
                          mainAxisSpacing: 16,
                          mainAxisExtent: tileExtent,
                        ),
                        itemCount: products.length,
                        itemBuilder: (_, index) => CatalogProductTile(
                          key: ValueKey('catalog-product-$index'),
                          product: products[index],
                          imageKey: ValueKey('catalog-product-image-$index'),
                          priceKey: ValueKey('catalog-product-price-$index'),
                          onTap: () => widget.onProduct(products[index]),
                          onAddToCart: () =>
                              widget.onAddToCart(products[index]),
                          isFavorite: widget.wishlistIds.contains(
                            products[index].id,
                          ),
                          onFavorite: () => widget.onFavorite(products[index]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class TopPicksPage extends StatelessWidget {
  const TopPicksPage({
    super.key,
    required this.onNav,
    required this.onProduct,
    required this.onAddToCart,
    required this.products,
    required this.wishlistIds,
    required this.onFavorite,
    this.catalogError,
  });

  final ValueChanged<int> onNav;
  final ValueChanged<Product> onProduct;
  final ValueChanged<Product> onAddToCart;
  final List<Product> products;
  final Set<String> wishlistIds;
  final ValueChanged<Product> onFavorite;
  final String? catalogError;

  @override
  Widget build(BuildContext context) {
    final topPicks = products.take(10).toList(growable: false);
    return WireframeShell(
      key: const Key('top-picks-page'),
      selectedNav: 1,
      onNav: onNav,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'Top 10 Perfumes', centerTitle: true),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: WireEyebrow('Ranked by our community'),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Updated monthly',
                  style: TextStyle(fontSize: 12, color: WireframeColors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: topPicks.isEmpty
                ? CatalogEmptyState(
                    query: '',
                    error: catalogError,
                    onClear: () {},
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    children: [
                      Column(
                        children: [
                          for (var index = 0; index < topPicks.length; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == topPicks.length - 1 ? 0 : 10,
                              ),
                              child: TopPickRow(
                                key: ValueKey('top-pick-${index + 1}'),
                                rank: index + 1,
                                product: topPicks[index],
                                onTap: () => onProduct(topPicks[index]),
                                onAddToCart: () => onAddToCart(topPicks[index]),
                                isFavorite: wishlistIds.contains(
                                  topPicks[index].id,
                                ),
                                onFavorite: () => onFavorite(topPicks[index]),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class TopPickRow extends StatelessWidget {
  const TopPickRow({
    super.key,
    required this.rank,
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    required this.isFavorite,
    required this.onFavorite,
  });

  final int rank;
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final available = product.isAvailable;
    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 172,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WireframeColors.paper,
          border: Border.all(color: WireframeColors.border),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: WireframeColors.ink.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: switch (rank) {
                  1 => const Color(0xFFE9D7A7),
                  2 => const Color(0xFFDDE0E4),
                  3 => const Color(0xFFE5B89D),
                  _ => WireframeColors.darkSurface,
                },
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontFamily: _modernFontFamily,
                  fontSize: 16,
                  height: 1,
                  color: rank <= 3
                      ? WireframeColors.ink
                      : WireframeColors.paper,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 78,
              height: 120,
              child: PlaceholderImage(
                width: 78,
                height: 120,
                radius: 10,
                fit: BoxFit.contain,
                tone: productTone(product),
                backgroundColor: WireframeColors.field,
                assetPath: productImageAsset(product),
                imageUrl: productImageUrl(product),
              ),
            ),
            if (!available) const _UnavailableTag(),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.brand,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: WireframeColors.brassInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _modernFontFamily,
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        formatPrice(product.price),
                        style: TextStyle(
                          fontSize: 14,
                          color: WireframeColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        product.volume,
                        style: TextStyle(
                          fontSize: 12,
                          color: WireframeColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ProductFavoriteButton(
                  product: product,
                  isFavorite: isFavorite,
                  onFavorite: onFavorite,
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    onPressed: available ? onAddToCart : null,
                    tooltip: 'Add ${product.name} to cart',
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ScentifySelectableChip(
        label: label,
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

class CatalogProductTile extends StatelessWidget {
  const CatalogProductTile({
    super.key,
    required this.product,
    required this.imageKey,
    required this.priceKey,
    required this.onTap,
    required this.onAddToCart,
    required this.isFavorite,
    required this.onFavorite,
  });

  final Product product;
  final Key imageKey;
  final Key priceKey;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final bool isFavorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final available = product.isAvailable;
    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: ScentifyThemeColors.of(context).canvas,
          borderRadius: BorderRadius.circular(ScentifyRadius.small),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ScentifyRadius.small),
                      child: PlaceholderImage(
                        key: imageKey,
                        radius: 8,
                        fit: BoxFit.contain,
                        tone: productTone(product),
                        backgroundColor: ScentifyColors.surfaceMuted,
                        assetPath: productImageAsset(product),
                        imageUrl: productImageUrl(product),
                      ),
                    ),
                  ),
                  if (!available)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.58),
                        alignment: Alignment.center,
                        child: const _UnavailableTag(),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: ProductFavoriteButton(
                      product: product,
                      isFavorite: isFavorite,
                      onFavorite: onFavorite,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0,
                        color: ScentifyThemeColors.of(context).muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _modernFontFamily,
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatPrice(product.price),
                            key: priceKey,
                            style: TextStyle(
                              fontSize: 16,
                              color: ScentifyThemeColors.of(context).ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          product.volume,
                          style: TextStyle(
                            fontSize: 12,
                            color: ScentifyThemeColors.of(context).muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: available ? onAddToCart : null,
                        icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                        label: const Text('Add to Cart'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ScentifyThemeColors.of(context).ink,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableTag extends StatelessWidget {
  const _UnavailableTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.grey.shade700,
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'Unavailable',
      style: TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class CatalogSkeletonGrid extends StatelessWidget {
  const CatalogSkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ScentifyBreakpoints.catalogColumnCount(
          constraints.maxWidth,
        );
        final gridWidth = ScentifyBreakpoints.catalogGridWidth(
          constraints.maxWidth,
          columns,
        );
        final tileWidth = ScentifyBreakpoints.catalogTileWidth(
          gridWidth,
          columns,
        );

        return Center(
          child: SizedBox(
            width: gridWidth,
            child: GridView.builder(
              key: const Key('catalog-skeleton-grid'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: ScentifyBreakpoints.catalogCrossAxisSpacing,
                mainAxisSpacing: 16,
                mainAxisExtent:
                    tileWidth + ScentifyBreakpoints.catalogTileHeightOffset,
              ),
              itemCount: 6,
              itemBuilder: (context, index) => const ScentifyCard(
                padding: EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SizedBox.expand(
                        child: ScentifySkeleton(
                          width: double.infinity,
                          height: 180,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    ScentifySkeleton(width: 70, height: 10, radius: 5),
                    SizedBox(height: 8),
                    ScentifySkeleton(width: 120, height: 14, radius: 6),
                    SizedBox(height: 12),
                    ScentifySkeleton(width: 90, height: 14, radius: 6),
                    SizedBox(height: 12),
                    ScentifySkeleton(width: double.infinity, height: 36),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({
    super.key,
    required this.query,
    required this.onClear,
    this.error,
  });

  final String query;
  final VoidCallback onClear;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ScentifyEmptyState(
      icon: error == null ? Icons.search_off_rounded : Icons.cloud_off_outlined,
      title: error == null ? 'No scents found' : 'Catalog unavailable',
      message:
          error ??
          'Try another search or reset the active filters${query.trim().isEmpty ? '' : ' for “${query.trim()}”'}.',
      actionLabel: 'Reset filters',
      onAction: onClear,
    );
  }
}

class FiltersPage extends StatefulWidget {
  const FiltersPage({
    super.key,
    required this.onBack,
    required this.onApply,
    required this.products,
    required this.initial,
  });

  final VoidCallback onBack;
  final ValueChanged<CatalogFilters> onApply;
  final List<Product> products;
  final CatalogFilters initial;

  @override
  State<FiltersPage> createState() => _FiltersPageState();
}

class _FiltersPageState extends State<FiltersPage> {
  final _brandSearchController = TextEditingController();
  late Set<String> _brands;
  late Set<String> _families;
  late String _gender;
  late RangeValues _priceRange;
  String _brandQuery = '';
  bool _showAllBrands = false;

  @override
  void initState() {
    super.initState();
    _brands = {...widget.initial.brands};
    _families = {...widget.initial.families};
    _gender = widget.initial.gender;
    _priceRange = widget.initial.priceRange;
  }

  List<String> get _availableBrands {
    final query = _brandQuery.trim().toLowerCase();
    final brands =
        widget.products.map((product) => product.brand).toSet().toList()
          ..sort();
    return brands
        .where((brand) => query.isEmpty || brand.toLowerCase().contains(query))
        .toList(growable: false);
  }

  int get _matchingCount => widget.products.where((product) {
    final matchesBrand = _brands.isEmpty || _brands.contains(product.brand);
    final matchesGender = _gender == 'All' || product.gender == _gender;
    final matchesPrice =
        product.price >= _priceRange.start && product.price <= _priceRange.end;
    final searchable = [
      product.description,
      ...product.topNotes,
      ...product.heartNotes,
      ...product.baseNotes,
    ].join(' ').toLowerCase();
    final matchesFamily =
        _families.isEmpty ||
        _families.any((family) {
          final signals = switch (family) {
            'Floral' => [
              'rose',
              'jasmine',
              'flower',
              'floral',
              'iris',
              'orchid',
            ],
            'Fresh' => ['fresh', 'marine', 'aquatic', 'mint', 'green'],
            'Woody' => ['wood', 'cedar', 'sandalwood', 'oud', 'vetiver'],
            'Citrus' => ['citrus', 'bergamot', 'lemon', 'orange', 'mandarin'],
            'Oriental' => ['amber', 'spice', 'oriental', 'incense'],
            'Gourmand' => ['vanilla', 'caramel', 'coffee', 'cocoa', 'sweet'],
            _ => <String>[],
          };
          return signals.any(searchable.contains);
        });
    return matchesBrand && matchesGender && matchesPrice && matchesFamily;
  }).length;

  void _reset() => setState(() {
    _brands.clear();
    _families.clear();
    _gender = 'All';
    _priceRange = const RangeValues(0, 50000);
    _brandQuery = '';
    _showAllBrands = false;
    _brandSearchController.clear();
  });

  @override
  void dispose() {
    _brandSearchController.dispose();
    super.dispose();
  }

  void _apply() => widget.onApply(
    CatalogFilters(
      brands: Set.unmodifiable(_brands),
      families: Set.unmodifiable(_families),
      gender: _gender,
      priceRange: _priceRange,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return WireframeShell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(
              title: 'Filters',
              onBack: widget.onBack,
              actions: [
                TextButton(
                  onPressed: _reset,
                  child: const Text(
                    'Reset',
                    style: TextStyle(fontSize: 14, color: WireframeColors.ink),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                const Text(
                  'Find your signature scent',
                  style: TextStyle(
                    fontFamily: _modernFontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose only what matters. You can change these anytime.',
                  style: TextStyle(fontSize: 14, color: WireframeColors.muted),
                ),
                const SizedBox(height: 16),
                ScentifyCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: _FilterTitle('Brand')),
                          if (_brands.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: WireframeColors.selected,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                pluralized(
                                  _brands.length,
                                  'brand selected',
                                  'brands selected',
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      WireSearchInput(
                        inputKey: const Key('filter-brand-search'),
                        controller: _brandSearchController,
                        hint: 'Search brands',
                        onChanged: (value) =>
                            setState(() => _brandQuery = value),
                        onClear: _brandQuery.isEmpty
                            ? null
                            : () {
                                _brandSearchController.clear();
                                setState(() => _brandQuery = '');
                              },
                      ),
                      const SizedBox(height: 8),
                      for (final brand in _availableBrands.take(
                        _showAllBrands ? _availableBrands.length : 6,
                      ))
                        FilterCheck(
                          label: brand,
                          checked: _brands.contains(brand),
                          onChanged: (value) => setState(
                            () => value
                                ? _brands.add(brand)
                                : _brands.remove(brand),
                          ),
                        ),
                      if (_availableBrands.length > 6)
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showAllBrands = !_showAllBrands),
                          icon: Icon(
                            _showAllBrands
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _showAllBrands ? 'Show less' : 'Show more',
                          ),
                        ),
                      if (_availableBrands.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'No matching brands',
                            style: TextStyle(
                              fontSize: 14,
                              color: WireframeColors.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ScentifyCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FilterTitle('Gender'),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: WireframeColors.field,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            for (final value in [
                              'All',
                              'Women',
                              'Men',
                              'Unisex',
                            ])
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: ChoiceTile(
                                    label: value,
                                    selected: _gender == value,
                                    onTap: () =>
                                        setState(() => _gender = value),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ScentifyCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FilterTitle('Price Range'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _PricePill(
                            label: 'Minimum',
                            value: formatPrice(_priceRange.start.round()),
                          ),
                          _PricePill(
                            label: 'Maximum',
                            value: _priceRange.end == 50000
                                ? '${formatPrice(50000)}+'
                                : formatPrice(_priceRange.end.round()),
                          ),
                        ],
                      ),
                      RangeSlider(
                        values: _priceRange,
                        min: 0,
                        max: 50000,
                        divisions: 20,
                        labels: RangeLabels(
                          formatPrice(_priceRange.start.round()),
                          formatPrice(_priceRange.end.round()),
                        ),
                        onChanged: (value) =>
                            setState(() => _priceRange = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ScentifyCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _FilterTitle('Fragrance Family'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final family in [
                            'Floral',
                            'Fresh',
                            'Woody',
                            'Citrus',
                            'Oriental',
                            'Gourmand',
                          ])
                            ScentifySelectableChip(
                              label: family,
                              selected: _families.contains(family),
                              onTap: () => setState(
                                () => _families.contains(family)
                                    ? _families.remove(family)
                                    : _families.add(family),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              color: WireframeColors.paper,
              border: Border(top: BorderSide(color: WireframeColors.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: ScentifySecondaryButton(
                    label: 'Reset',
                    onPressed: _reset,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ScentifyPrimaryButton(
                    label: 'Show ${pluralized(_matchingCount, 'scent')}',
                    onPressed: _apply,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTitle extends StatelessWidget {
  const _FilterTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WireframeColors.field,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: WireframeColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class FilterCheck extends StatelessWidget {
  const FilterCheck({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 15,
            ),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ProductGalleryItem {
  const _ProductGalleryItem({this.assetPath, this.imageUrl});

  final String? assetPath;
  final String? imageUrl;
}

class ProductImageCarousel extends StatefulWidget {
  const ProductImageCarousel({
    super.key,
    required this.product,
    required this.imageSize,
  });

  final Product product;
  final double imageSize;

  @override
  State<ProductImageCarousel> createState() => _ProductImageCarouselState();
}

class _ProductImageCarouselState extends State<ProductImageCarousel> {
  late final PageController _controller;
  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_ProductGalleryItem> _galleryItems(Product product) {
    final items = <_ProductGalleryItem>[];
    final assetPath = productImageAsset(product);
    final seenUrls = <String>{};

    if (assetPath != null) {
      items.add(_ProductGalleryItem(assetPath: assetPath));
    }
    for (final rawUrl in product.imageUrls) {
      final url = rawUrl.trim();
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        continue;
      }
      if (seenUrls.add(url)) {
        items.add(_ProductGalleryItem(imageUrl: url));
      }
    }
    if (items.isEmpty) {
      items.add(const _ProductGalleryItem());
    }
    return items;
  }

  void _goTo(int page) {
    if (!_controller.hasClients) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant ProductImageCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        oldWidget.product.imageUrls.length != widget.product.imageUrls.length) {
      _currentPage = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _galleryItems(widget.product);
    final colors = ScentifyThemeColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: const Key('product-image-carousel'),
          width: widget.imageSize,
          height: widget.imageSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                key: const Key('product-image-pages'),
                controller: _controller,
                itemCount: items.length,
                physics: items.length > 1
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return PlaceholderImage(
                    key: ValueKey('product-image-page-$index'),
                    width: widget.imageSize,
                    height: widget.imageSize,
                    radius: 4,
                    fit: BoxFit.contain,
                    tone: productTone(widget.product),
                    backgroundColor: Colors.transparent,
                    assetPath: item.assetPath,
                    imageUrl: item.imageUrl,
                  );
                },
              ),
              if (items.length > 1)
                Positioned(
                  left: 3,
                  top: widget.imageSize / 2 - 24,
                  child: IconButton(
                    key: const Key('product-image-previous'),
                    onPressed: _currentPage == 0
                        ? null
                        : () => _goTo(_currentPage - 1),
                    icon: const Icon(Icons.chevron_left, size: 18),
                    color: colors.ink,
                    disabledColor: colors.faint,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.paper.withValues(alpha: 0.82),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    tooltip: 'Previous product image',
                  ),
                ),
              if (items.length > 1)
                Positioned(
                  right: 3,
                  top: widget.imageSize / 2 - 24,
                  child: IconButton(
                    key: const Key('product-image-next'),
                    onPressed: _currentPage == items.length - 1
                        ? null
                        : () => _goTo(_currentPage + 1),
                    icon: const Icon(Icons.chevron_right, size: 18),
                    color: colors.ink,
                    disabledColor: colors.faint,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.paper.withValues(alpha: 0.82),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    tooltip: 'Next product image',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < items.length; index++)
              Semantics(
                button: true,
                selected: index == _currentPage,
                label: 'Product image ${index + 1} of ${items.length}',
                child: InkWell(
                  key: ValueKey('product-image-dot-$index'),
                  onTap: () => _goTo(index),
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: _Dot(active: index == _currentPage)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class ProductPage extends StatefulWidget {
  const ProductPage({
    super.key,
    required this.product,
    this.recommendations = const [],
    required this.isFavorite,
    required this.onBack,
    required this.onFavorite,
    this.onRecommendation,
    required this.onAddToCart,
    this.reviewRepository,
  });

  final Product product;
  final List<Product> recommendations;
  final bool isFavorite;
  final VoidCallback onBack;
  final VoidCallback onFavorite;
  final ValueChanged<Product>? onRecommendation;
  final void Function(int quantity, String volume) onAddToCart;
  final ProductReviewRepository? reviewRepository;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  StreamSubscription<List<ProductReview>>? _reviewsSubscription;
  List<ProductReview> _reviews = const [];
  String? _reviewError;
  bool _loadingReviews = false;
  late String _selectedVolume = _defaultProductVolume(widget.product);
  var _quantity = 1;
  var _aboutExpanded = false;
  var _reviewsExpanded = false;

  @override
  void initState() {
    super.initState();
    _watchReviews();
  }

  int _priceFor(String volume) {
    return widget.product.priceFor(volume);
  }

  bool get _selectedVolumeAvailable =>
      widget.product.isVolumeAvailable(_selectedVolume);

  void _selectVolume(String volume) {
    setState(() {
      _selectedVolume = volume;
      final stock = widget.product.stockFor(volume);
      if (widget.product.hasKnownStock && stock > 0 && _quantity > stock) {
        _quantity = stock;
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProductPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _watchReviews();
      _selectedVolume = _defaultProductVolume(widget.product);
      _quantity = 1;
      _aboutExpanded = false;
      _reviewsExpanded = false;
    } else if (!widget.product.availableVolumes.contains(_selectedVolume) ||
        !_selectedVolumeAvailable) {
      _selectedVolume = _defaultProductVolume(widget.product);
      _quantity = 1;
    }
  }

  void _watchReviews() {
    unawaited(_reviewsSubscription?.cancel());
    final repository = widget.reviewRepository;
    if (repository == null) {
      _reviews = const [];
      _reviewError = null;
      _loadingReviews = false;
      return;
    }
    _loadingReviews = true;
    _reviewError = null;
    _reviewsSubscription = repository
        .watchForProduct(widget.product.id)
        .listen(
          (reviews) {
            if (!mounted) return;
            setState(() {
              _reviews = List.unmodifiable(reviews);
              _reviewError = null;
              _loadingReviews = false;
            });
          },
          onError: (Object error, StackTrace stack) {
            if (!mounted) return;
            setState(() {
              _reviewError = 'Reviews are temporarily unavailable.';
              _loadingReviews = false;
            });
          },
        );
  }

  Widget _buildReviewContent() {
    final verifiedReviews = _reviews
        .where((review) => review.verifiedPurchase)
        .toList(growable: false);
    if (_loadingReviews && verifiedReviews.isEmpty) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (verifiedReviews.isEmpty) {
      return Text(
        _reviewError ?? 'No verified reviews yet.',
        style: ScentifyTypography.caption,
      );
    }
    final average =
        verifiedReviews.fold<int>(0, (sum, review) => sum + review.rating) /
        verifiedReviews.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${average.toStringAsFixed(1)} · ${verifiedReviews.length} '
          '${verifiedReviews.length == 1 ? 'review' : 'reviews'}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < verifiedReviews.length; index++) ...[
          if (index > 0)
            const Divider(height: 16, color: WireframeColors.border),
          _ProductReviewTile(review: verifiedReviews[index]),
        ],
        if (_reviewError != null) ...[
          const SizedBox(height: 8),
          Text(
            _reviewError!,
            style: const TextStyle(fontSize: 12, color: WireframeColors.muted),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    unawaited(_reviewsSubscription?.cancel());
    super.dispose();
  }

  Widget _buildProductGallery(
    ScentifyThemeColors colors, {
    required double height,
    required double imageSize,
  }) {
    return Container(
      key: const Key('product-gallery-frame'),
      height: height,
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Center(
            child: ProductImageCarousel(
              product: widget.product,
              imageSize: imageSize,
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: ScentifyIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: widget.onBack,
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: ScentifyIconButton(
              icon: widget.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              tooltip: 'Wishlist',
              selected: widget.isFavorite,
              onPressed: widget.onFavorite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSummary(ScentifyThemeColors colors) {
    Widget sizeChoice(String value) => VariantTile(
      tapKey: ValueKey('product-size-$value'),
      label: value,
      price: _priceFor(value),
      selected: value == _selectedVolume,
      isAvailable: widget.product.isVolumeAvailable(value),
      onTap: widget.product.isVolumeAvailable(value)
          ? () => _selectVolume(value)
          : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WireEyebrow(widget.product.brand, color: colors.muted),
        const SizedBox(height: 8),
        Text(
          widget.product.name,
          style: ScentifyTypography.title.copyWith(color: colors.ink),
        ),
        const SizedBox(height: 12),
        Text(
          formatPrice(_priceFor(_selectedVolume)),
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ).copyWith(color: colors.ink),
        ),
        const SizedBox(height: 16),
        if (widget.product.description.trim().isNotEmpty) ...[
          Text(
            widget.product.description.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
            ).copyWith(color: colors.muted),
          ),
          const SizedBox(height: 24),
        ] else
          const SizedBox(height: 12),
        const CustomerSectionTitle(title: 'Choose a size'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600 &&
                MediaQuery.textScalerOf(context).scale(14) >= 21) {
              final width = constraints.maxWidth >= 256
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in widget.product.availableVolumes)
                    SizedBox(width: width, child: sizeChoice(value)),
                ],
              );
            }
            return Row(
              children: [
                for (final value in widget.product.availableVolumes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: sizeChoice(value),
                    ),
                  ),
              ],
            );
          },
        ),
        if (widget.product.hasKnownStock &&
            widget.product.stockFor(_selectedVolume) > 0 &&
            widget.product.stockFor(_selectedVolume) <= 5) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.local_fire_department_outlined,
                size: 16,
                color: colors.brassInk,
              ),
              const SizedBox(width: 6),
              Text(
                'Only ${widget.product.stockFor(_selectedVolume)} left in stock',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ).copyWith(color: colors.tobacco),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFragranceNotes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ScentifySectionHeader(title: 'Fragrance Notes'),
      const SizedBox(height: 16),
      ProductNoteRow(
        label: 'Top Notes',
        value: widget.product.topNotes.join(' · '),
      ),
      ProductNoteRow(
        label: 'Heart Notes',
        value: widget.product.heartNotes.join(' · '),
      ),
      ProductNoteRow(
        label: 'Base Notes',
        value: widget.product.baseNotes.join(' · '),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return WireframeShell(
      key: const Key('product-detail-page'),
      bottomBar: ProductPurchaseBar(
        key: const Key('product-purchase-bar'),
        quantity: _quantity,
        total: _priceFor(_selectedVolume) * _quantity,
        onDecrement: () {
          if (_quantity > 1) {
            setState(() => _quantity--);
          }
        },
        onIncrement: () {
          final stock = widget.product.stockFor(_selectedVolume);
          if (!widget.product.hasKnownStock || _quantity < stock) {
            setState(() => _quantity++);
          }
        },
        onAddToCart: _selectedVolumeAvailable
            ? () => widget.onAddToCart(_quantity, _selectedVolume)
            : null,
      ),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  if (constraints.maxWidth >=
                      ScentifyBreakpoints.expandedMinWidth)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 9,
                          child: _buildProductGallery(
                            colors,
                            height: 420,
                            imageSize: 300,
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 11,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildProductSummary(colors),
                                const SizedBox(height: 20),
                                _buildFragranceNotes(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (constraints.maxWidth <
                      ScentifyBreakpoints.expandedMinWidth) ...[
                    _buildProductGallery(colors, height: 292, imageSize: 220),
                    const SizedBox(height: 32),
                    _buildProductSummary(colors),
                    const SizedBox(height: 32),
                    _buildFragranceNotes(),
                  ],
                  const SizedBox(height: 10),
                  if (widget.product.description.trim().isNotEmpty)
                    ProductAccordion(
                      toggleKey: const Key('product-about-toggle'),
                      label: 'About',
                      expanded: _aboutExpanded,
                      onTap: () =>
                          setState(() => _aboutExpanded = !_aboutExpanded),
                      child: Text(
                        widget.product.description.trim(),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ProductAccordion(
                    toggleKey: const Key('product-reviews-toggle'),
                    label: 'Reviews',
                    expanded: _reviewsExpanded,
                    onTap: () =>
                        setState(() => _reviewsExpanded = !_reviewsExpanded),
                    child: ScentifyCard(
                      shadow: false,
                      color: WireframeColors.field,
                      child: _buildReviewContent(),
                    ),
                  ),
                  if (widget.recommendations.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const ScentifySectionHeader(title: 'You may also like'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 190,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.recommendations.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) => RecommendationCard(
                          product: widget.recommendations[index],
                          onTap: () => widget.onRecommendation?.call(
                            widget.recommendations[index],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductReviewTile extends StatelessWidget {
  const _ProductReviewTile({required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final stars =
        '${List.filled(review.rating, '★').join()}'
        '${List.filled(5 - review.rating, '☆').join()}';
    return Column(
      key: ValueKey('product-review-${review.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(stars, style: const TextStyle(color: WireframeColors.tobacco)),
            const SizedBox(width: 8),
            const Text(
              'Verified purchase',
              style: TextStyle(fontSize: 12, color: WireframeColors.muted),
            ),
          ],
        ),
        if (review.title.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            review.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(review.comment, style: ScentifyTypography.caption),
        ],
      ],
    );
  }
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return SizedBox(
      width: 142,
      child: Material(
        color: colors.paper,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PlaceholderImage(
                    fit: BoxFit.contain,
                    radius: 12,
                    tone: productTone(product),
                    backgroundColor: colors.field,
                    assetPath: productImageAsset(product),
                    imageUrl: productImageUrl(product),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ScentifyTypography.caption.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ScentifyPriceText(
                  product.price,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProductPurchaseBar extends StatelessWidget {
  const ProductPurchaseBar({
    super.key,
    required this.quantity,
    required this.total,
    required this.onDecrement,
    required this.onIncrement,
    required this.onAddToCart,
  });

  final int quantity;
  final int total;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colors.paper,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Row(
              children: [
                QuantityStepper(
                  key: const Key('product-quantity-stepper'),
                  quantity: quantity,
                  onDecrement: onDecrement,
                  onIncrement: onIncrement,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: WireButton(
                    key: const Key('product-add-to-cart'),
                    label: 'Add to Cart  •  ${formatPrice(total)}',
                    icon: Icons.shopping_bag_outlined,
                    onPressed: onAddToCart == null
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            onAddToCart!();
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Decrease quantity',
            child: InkWell(
              key: const Key('product-quantity-decrement'),
              onTap: onDecrement,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: Icon(Icons.remove, size: 15)),
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              '$quantity',
              key: const Key('product-quantity-value'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Tooltip(
            message: 'Increase quantity',
            child: InkWell(
              key: const Key('product-quantity-increment'),
              onTap: onIncrement,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: Icon(Icons.add, size: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductNoteRow extends StatelessWidget {
  const ProductNoteRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: colors.muted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class ProductAccordion extends StatelessWidget {
  const ProductAccordion({
    super.key,
    required this.toggleKey,
    required this.label,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  final Key toggleKey;
  final String label;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          key: toggleKey,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 17,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2, bottom: 12),
                  child: Align(alignment: Alignment.centerLeft, child: child),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class ProductQuickView extends StatefulWidget {
  const ProductQuickView({
    super.key,
    required this.product,
    required this.onAddToCart,
    required this.onViewDetails,
  });

  final Product product;
  final ValueChanged<String> onAddToCart;
  final VoidCallback onViewDetails;

  @override
  State<ProductQuickView> createState() => _ProductQuickViewState();
}

class _ProductQuickViewState extends State<ProductQuickView> {
  late String _selectedVolume = _defaultProductVolume(widget.product);

  bool get _selectedVolumeAvailable =>
      widget.product.isVolumeAvailable(_selectedVolume);

  List<String> get _volumes => widget.product.availableVolumes.isEmpty
      ? [widget.product.volume]
      : widget.product.availableVolumes;

  @override
  void didUpdateWidget(covariant ProductQuickView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id ||
        !widget.product.availableVolumes.contains(_selectedVolume) ||
        !_selectedVolumeAvailable) {
      _selectedVolume = _defaultProductVolume(widget.product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedStock = widget.product.stockFor(_selectedVolume);
    return Container(
      key: const Key('product-quick-view'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: WireframeColors.paper,
        border: Border.all(color: WireframeColors.border),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: WireframeColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      tooltip: 'Close',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 124,
                  height: 124,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: WireframeColors.field,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: PlaceholderImage(
                    radius: 14,
                    fit: BoxFit.contain,
                    tone: productTone(widget.product),
                    backgroundColor: Colors.transparent,
                    assetPath: productImageAsset(widget.product),
                    imageUrl: productImageUrl(widget.product),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.brand,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WireframeColors.muted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          key: const Key('quick-view-selected-price'),
                          formatPrice(widget.product.priceFor(_selectedVolume)),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _selectedVolumeAvailable
                                    ? ScentifyColors.success
                                    : ScentifyColors.danger,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _selectedVolumeAvailable
                                  ? widget.product.hasKnownStock
                                        ? '$selectedStock in stock'
                                        : 'In stock'
                                  : 'Out of stock',
                              style: TextStyle(
                                fontSize: 12,
                                color: _selectedVolumeAvailable
                                    ? ScentifyColors.success
                                    : ScentifyColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose a size',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                for (final value in _volumes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: VariantTile(
                        tapKey: ValueKey('product-quick-size-$value'),
                        label: value,
                        price: widget.product.priceFor(value),
                        selected: value == _selectedVolume,
                        isAvailable: widget.product.isVolumeAvailable(value),
                        onTap: widget.product.isVolumeAvailable(value)
                            ? () => setState(() => _selectedVolume = value)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            WireButton(
              key: const Key('quick-view-add-to-cart'),
              label:
                  'Add to Cart  •  ${formatPrice(widget.product.priceFor(_selectedVolume))}',
              icon: Icons.shopping_bag_outlined,
              onPressed: _selectedVolumeAvailable
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onAddToCart(_selectedVolume);
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            WireButton(
              key: const Key('quick-view-view-details'),
              label: 'View full details',
              dark: false,
              onPressed: widget.onViewDetails,
            ),
          ],
        ),
      ),
    );
  }
}

class VariantTile extends StatelessWidget {
  const VariantTile({
    super.key,
    required this.label,
    required this.price,
    required this.selected,
    this.onTap,
    this.tapKey,
    this.isAvailable = true,
  });

  final String label;
  final int price;
  final bool selected;
  final VoidCallback? onTap;
  final Key? tapKey;
  final bool isAvailable;

  @override
  Widget build(BuildContext context) {
    final tile = ScentifySizeSelectorCard(
      label: label,
      price: price,
      stockLabel: isAvailable ? 'In stock' : 'Out of stock',
      selected: selected,
      available: isAvailable,
      onTap: onTap,
    );

    if (tapKey != null) {
      return KeyedSubtree(key: tapKey, child: tile);
    }
    return tile;
  }
}

class WishlistPage extends StatelessWidget {
  const WishlistPage({
    super.key,
    required this.onNav,
    required this.onProduct,
    required this.products,
    required this.wishlistIds,
    required this.onToggle,
    required this.onAddToCart,
    this.error,
  });

  final ValueChanged<int> onNav;
  final ValueChanged<Product> onProduct;
  final List<Product> products;
  final Set<String> wishlistIds;
  final ValueChanged<Product> onToggle;
  final ValueChanged<Product> onAddToCart;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final savedProducts = products
        .where((product) => wishlistIds.contains(product.id))
        .toList();
    return WireframeShell(
      selectedNav: 2,
      onNav: onNav,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'My Wishlist'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
            child: Row(
              children: [
                const Expanded(child: WireEyebrow('Scents worth remembering')),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: WireframeColors.selected,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    pluralized(savedProducts.length, 'saved scent'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.tobacco,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: savedProducts.isEmpty
                ? ScentifyEmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: error == null
                        ? 'Your wishlist is waiting'
                        : 'Wishlist unavailable',
                    message: error ?? 'Save the scents you love and they will stay close at hand.',
                    actionLabel: 'Start shopping',
                    onAction: () => onNav(1),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 18),
                    itemCount: savedProducts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) => Dismissible(
                      key: ValueKey('wishlist-${savedProducts[index].id}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => onToggle(savedProducts[index]),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(
                          color: ScentifyColors.dangerSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: ScentifyColors.danger,
                        ),
                      ),
                      child: WishlistRow(
                        product: savedProducts[index],
                        onTap: () => onProduct(savedProducts[index]),
                        onToggle: () => onToggle(savedProducts[index]),
                        onAddToCart: () => onAddToCart(savedProducts[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class WishlistRow extends StatelessWidget {
  const WishlistRow({
    super.key,
    required this.product,
    required this.onTap,
    required this.onToggle,
    required this.onAddToCart,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final available = product.isAvailable;
    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 156,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.paper,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.ink.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            PlaceholderImage(
              width: 72,
              height: 108,
              radius: 11,
              fit: BoxFit.contain,
              tone: productTone(product),
              backgroundColor: WireframeColors.field,
              assetPath: productImageAsset(product),
              imageUrl: productImageUrl(product),
            ),
            if (!available) const SizedBox(width: 8),
            if (!available) const _UnavailableTag(),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.brand,
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: colors.brassInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _modernFontFamily,
                      fontSize: 14,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        formatPrice(product.price),
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        product.volume,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    width: 132,
                    child: WireButton(
                      label: 'Add to Cart',
                      icon: Icons.shopping_bag_outlined,
                      onPressed: available ? onAddToCart : null,
                      fontSize: 14,
                      radius: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            ProductFavoriteButton(
              product: product,
              isFavorite: true,
              onFavorite: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItem {
  _CartItem({required this.product, required this.item})
    : quantity = item.quantity;

  final Product product;
  final CartItem item;
  int quantity;
  bool selected = false;
}

class _CartGroup {
  _CartGroup({required this.brand, required this.items});

  final String brand;
  final List<_CartItem> items;
}

class CartPage extends StatefulWidget {
  const CartPage({
    super.key,
    required this.cart,
    required this.products,
    required this.onBack,
    required this.onCheckout,
    required this.onSetQuantity,
    required this.onRemove,
    this.error,
  });

  final Cart cart;
  final List<Product> products;
  final VoidCallback onBack;
  final void Function(List<CartItem> items) onCheckout;
  final Future<void> Function(CartItem item, int quantity) onSetQuantity;
  final Future<void> Function(CartItem item) onRemove;
  final String? error;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late List<_CartGroup> _groups;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _groups = _groupsFromCart(widget.cart);
  }

  @override
  void didUpdateWidget(covariant CartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cart, widget.cart) ||
        !identical(oldWidget.products, widget.products)) {
      _groups = _groupsFromCart(widget.cart);
    }
  }

  List<_CartGroup> _groupsFromCart(Cart cart) {
    final groups = <_CartGroup>[];
    for (final item in cart.items) {
      final product = _productFor(item);
      final existingGroup = groups.where(
        (group) => group.brand == product.brand,
      );
      final cartItem = _CartItem(product: product, item: item);
      if (existingGroup.isEmpty) {
        groups.add(_CartGroup(brand: product.brand, items: [cartItem]));
      } else {
        existingGroup.first.items.add(cartItem);
      }
    }
    return groups;
  }

  Product _productFor(CartItem item) {
    for (final product in widget.products) {
      if (product.id == item.productId) {
        return product;
      }
    }
    return Product(
      id: item.productId,
      name: item.productName,
      brand: 'Scentify',
      price: item.unitPrice.centavos ~/ 100,
      volume: item.variantLabel,
      availableVolumes: [item.variantLabel],
    );
  }

  Iterable<_CartItem> get _items => _groups.expand((group) => group.items);

  int get _selectedCount => _items
      .where((item) => item.selected)
      .fold(0, (total, item) => total + item.quantity);

  int get _totalCount => _items.fold(0, (total, item) => total + item.quantity);

  int get _selectedLineCount => _items.where((item) => item.selected).length;

  int get _selectedSubtotal => _items
      .where((item) => item.selected)
      .fold(
        0,
        (total, item) =>
            total + item.item.unitPrice.centavos ~/ 100 * item.quantity,
      );

  bool get _hasSelection => _items.any((item) => item.selected);

  bool get _allSelected =>
      _items.isNotEmpty && _items.every((item) => item.selected);

  List<CartItem> get _selectedItems => [
    for (final item in _items)
      if (item.selected) item.item,
  ];

  void _toggleItem(_CartItem item) {
    setState(() => item.selected = !item.selected);
  }

  void _toggleGroup(_CartGroup group) {
    final shouldSelectGroup = group.items.any((item) => !item.selected);
    setState(() {
      for (final item in group.items) {
        item.selected = shouldSelectGroup;
      }
    });
  }

  void _toggleAll() {
    final shouldSelectAll = !_allSelected;
    setState(() {
      for (final item in _items) {
        item.selected = shouldSelectAll;
      }
    });
  }

  void _changeQuantity(_CartItem item, int delta) {
    final nextQuantity = item.quantity + delta;
    if (nextQuantity < 1) return;
    unawaited(widget.onSetQuantity(item.item, nextQuantity));
  }

  void _removeItem(_CartItem item) {
    unawaited(widget.onRemove(item.item));
  }

  Widget _buildItemList() {
    if (_groups.isEmpty) {
      return _EmptyCartState(error: widget.error);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      children: [
        for (final group in _groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CartGroupCard(
              key: ValueKey('cart-group-${group.brand}'),
              brand: group.brand,
              items: group.items,
              isEditing: _isEditing,
              selected:
                  group.items.isNotEmpty &&
                  group.items.every((item) => item.selected),
              onToggleGroup: () => _toggleGroup(group),
              onToggleItem: _toggleItem,
              onDecrease: (item) => _changeQuantity(item, -1),
              onIncrease: (item) => _changeQuantity(item, 1),
              onRemove: _removeItem,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WireframeShell(
      backgroundColor: ScentifyThemeColors.of(context).cartBackground,
      child: Column(
        children: [
          Container(
            color: WireframeColors.cartSurface,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _CartHeader(
              count: _totalCount,
              isEditing: _isEditing,
              onBack: widget.onBack,
              onToggleEditing: () => setState(() => _isEditing = !_isEditing),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                final summary = _CartSummary(
                  totalCount: _totalCount,
                  selectedCount: _selectedCount,
                  selectedLineCount: _selectedLineCount,
                  subtotal: _selectedSubtotal,
                  hasSelection: _hasSelection,
                  allSelected: _allSelected,
                  onToggleAll: _groups.isEmpty ? null : _toggleAll,
                  onCheckout: _hasSelection
                      ? () => widget.onCheckout(_selectedItems)
                      : null,
                  isDock: !isWide,
                );

                if (isWide) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildItemList()),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 320,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: summary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(child: _buildItemList()),
                    SafeArea(top: false, child: summary),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CartRow extends StatelessWidget {
  const CartRow({
    super.key,
    required this.product,
    required this.price,
    required this.variantLabel,
    required this.quantity,
    required this.selected,
    required this.isEditing,
    required this.onToggle,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final Product product;
  final int price;
  final String variantLabel;
  final int quantity;
  final bool selected;
  final bool isEditing;
  final VoidCallback onToggle;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CartSelectionButton(
            selected: selected,
            onPressed: onToggle,
            label: selected
                ? 'Deselect ${product.name}'
                : 'Select ${product.name}',
          ),
          const SizedBox(width: 2),
          PlaceholderImage(
            width: 70,
            height: 70,
            radius: 10,
            fit: BoxFit.contain,
            tone: productTone(product),
            backgroundColor: WireframeColors.field,
            assetPath: productImageAsset(product),
            imageUrl: productImageUrl(product),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: _modernFontFamily,
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isEditing)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          onPressed: onRemove,
                          padding: EdgeInsets.zero,
                          tooltip: 'Remove ${product.name}',
                          icon: const Icon(Icons.delete_outline, size: 18),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  variantLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatPrice(price),
                  style: const TextStyle(
                    color: WireframeColors.cartAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: _CartQuantityControl(
                    quantity: quantity,
                    onDecrease: onDecrease,
                    onIncrease: onIncrease,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({
    required this.count,
    required this.isEditing,
    required this.onBack,
    required this.onToggleEditing,
  });

  final int count;
  final bool isEditing;
  final VoidCallback onBack;
  final VoidCallback onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back,
              color: WireframeColors.cartAccent,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              label: 'My Cart, $count items in cart',
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'My Cart',
                      style: TextStyle(
                        fontSize: 21,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' ($count)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: WireframeColors.muted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onToggleEditing,
            icon: Icon(
              isEditing ? Icons.close : Icons.delete_outline,
              size: 18,
            ),
            tooltip: isEditing ? 'Done editing' : 'Edit cart',
          ),
        ],
      ),
    );
  }
}

class _CartSelectionButton extends StatelessWidget {
  const _CartSelectionButton({
    required this.selected,
    required this.onPressed,
    required this.label,
  });

  final bool selected;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: selected,
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        tooltip: label,
        icon: Icon(
          selected ? Icons.check_box : Icons.check_box_outline_blank,
          size: 16,
          color: onPressed == null
              ? WireframeColors.faint
              : selected
              ? WireframeColors.cartAccent
              : WireframeColors.ink,
        ),
      ),
    );
  }
}

class _CartQuantityControl extends StatelessWidget {
  const _CartQuantityControl({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: WireframeColors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WireframeColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CartQuantityButton(
            icon: Icons.remove,
            label: 'Decrease quantity',
            onPressed: quantity > 1 ? onDecrease : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          _CartQuantityButton(
            icon: Icons.add,
            label: 'Increase quantity',
            onPressed: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _CartQuantityButton extends StatelessWidget {
  const _CartQuantityButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        tooltip: label,
        icon: Icon(
          icon,
          size: 15,
          color: onPressed == null
              ? WireframeColors.faint
              : WireframeColors.ink,
        ),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({
    required this.totalCount,
    required this.selectedCount,
    required this.selectedLineCount,
    required this.subtotal,
    required this.hasSelection,
    required this.allSelected,
    required this.onToggleAll,
    required this.onCheckout,
    required this.isDock,
  });

  final int totalCount;
  final int selectedCount;
  final int selectedLineCount;
  final int subtotal;
  final bool hasSelection;
  final bool allSelected;
  final VoidCallback? onToggleAll;
  final VoidCallback? onCheckout;
  final bool isDock;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = selectedLineCount == 0
        ? 'No item selected'
        : '$selectedCount ${selectedCount == 1 ? 'item' : 'items'} selected';

    final content = Column(
      mainAxisSize: isDock ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDock) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      selectedLabel,
                      key: ValueKey(selectedLabel),
                      style: const TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                  ),
                ),
                Text(
                  '$totalCount ${totalCount == 1 ? 'item' : 'items'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: WireframeColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    _CartSelectionButton(
                      selected: allSelected,
                      onPressed: onToggleAll,
                      label: 'Select all cart items',
                    ),
                    const Text('Select all', style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    const Text(
                      'Shipping',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text('Free', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 2),
                SummaryLine(
                  label: 'Subtotal',
                  value: hasSelection ? formatPrice(subtotal) : formatPrice(0),
                ),
                SummaryLine(
                  label: 'Total',
                  value: hasSelection ? formatPrice(subtotal) : formatPrice(0),
                  strong: true,
                ),
                const SizedBox(height: 8),
                _CartCheckoutButton(
                  selectedCount: selectedCount,
                  hasSelection: hasSelection,
                  onPressed: onCheckout,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _CartSelectionButton(
                  selected: allSelected,
                  onPressed: onToggleAll,
                  label: 'Select all cart items',
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    selectedLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.muted,
                    ),
                  ),
                ),
                Text(
                  '$totalCount ${totalCount == 1 ? 'item' : 'items'} in cart',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: WireframeColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cart total',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                _CartTotalText(hasSelection: hasSelection, subtotal: subtotal),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _CartCheckoutButton(
              selectedCount: selectedCount,
              hasSelection: hasSelection,
              onPressed: onCheckout,
            ),
          ),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: WireframeColors.cartSurface,
        border: Border.all(color: WireframeColors.border),
        borderRadius: isDock ? BorderRadius.zero : BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _CartTotalText extends StatelessWidget {
  const _CartTotalText({required this.hasSelection, required this.subtotal});

  final bool hasSelection;
  final int subtotal;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        hasSelection ? formatPrice(subtotal) : formatPrice(0),
        key: ValueKey('$hasSelection-$subtotal'),
        style: TextStyle(
          color: hasSelection
              ? WireframeColors.cartAccent
              : WireframeColors.muted,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CartCheckoutButton extends StatelessWidget {
  const _CartCheckoutButton({
    required this.selectedCount,
    required this.hasSelection,
    required this.onPressed,
  });

  final int selectedCount;
  final bool hasSelection;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: hasSelection
              ? WireframeColors.cartAccent
              : WireframeColors.field,
          foregroundColor: hasSelection ? Colors.white : WireframeColors.muted,
          disabledBackgroundColor: WireframeColors.field,
          disabledForegroundColor: WireframeColors.muted,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          'Checkout ($selectedCount)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _CartGroupCard extends StatelessWidget {
  const _CartGroupCard({
    super.key,
    required this.brand,
    required this.items,
    required this.isEditing,
    required this.selected,
    required this.onToggleGroup,
    required this.onToggleItem,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final String brand;
  final List<_CartItem> items;
  final bool isEditing;
  final bool selected;
  final VoidCallback onToggleGroup;
  final ValueChanged<_CartItem> onToggleItem;
  final ValueChanged<_CartItem> onDecrease;
  final ValueChanged<_CartItem> onIncrease;
  final ValueChanged<_CartItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WireframeColors.cartSurface,
        border: Border.all(color: WireframeColors.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: ScentifyShadows.subtle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                _CartSelectionButton(
                  selected: selected,
                  onPressed: onToggleGroup,
                  label: 'Select all $brand items',
                ),
                Expanded(
                  child: Text(
                    brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: WireframeColors.border),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                indent: 10,
                endIndent: 10,
                color: WireframeColors.border,
              ),
            CartRow(
              key: ValueKey(
                '${items[index].item.productId}-${items[index].item.variantId}',
              ),
              product: items[index].product,
              price: items[index].item.unitPrice.centavos ~/ 100,
              variantLabel: items[index].item.variantLabel,
              quantity: items[index].quantity,
              selected: items[index].selected,
              isEditing: isEditing,
              onToggle: () => onToggleItem(items[index]),
              onDecrease: () => onDecrease(items[index]),
              onIncrease: () => onIncrease(items[index]),
              onRemove: () => onRemove(items[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return ScentifyEmptyState(
      icon: error == null
          ? Icons.shopping_bag_outlined
          : Icons.cloud_off_outlined,
      title: error == null ? 'Your cart is empty' : 'Cart unavailable',
      message:
          error ?? 'Add a fragrance when you find one you want to keep close.',
    );
  }
}

class _CheckoutContentFrame extends StatelessWidget {
  const _CheckoutContentFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class CheckoutSteps extends StatelessWidget {
  const CheckoutSteps({super.key, required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    const labels = ['Address', 'Delivery', 'Review & Place Order'];
    final colors = ScentifyThemeColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (textScale >= 1.5 || constraints.maxWidth < 400) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step ${active + 1} of ${labels.length}',
                  style: ScentifyTypography.metadata.copyWith(
                    color: colors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  labels[active],
                  style: ScentifyTypography.label.copyWith(color: colors.ink),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (active + 1) / labels.length,
                  minHeight: 4,
                  color: scheme.primary,
                  backgroundColor: colors.border,
                  semanticsLabel: 'Checkout progress',
                  semanticsValue:
                      '${((active + 1) / labels.length * 100).round()}',
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              for (var index = 0; index < labels.length; index++) ...[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index <= active ? scheme.primary : colors.field,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: index <= active ? scheme.onPrimary : colors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 12,
                    color: index <= active ? colors.ink : colors.muted,
                    fontWeight: index == active
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                if (index != labels.length - 1)
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: index < active ? scheme.primary : colors.border,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class CheckoutAddressPage extends StatefulWidget {
  const CheckoutAddressPage({
    super.key,
    required this.onBack,
    required this.onNext,
    this.onSaveAddress,
    this.onDeleteSavedAddress,
    this.onSavedAddressSelected,
    this.initialAddress,
    this.autocompleteProvider,
    this.savedAddress,
    this.error,
    this.addressSaveMessage =
        'Save this address for future orders if you choose.',
    this.profileAddressBook = false,
  });

  final VoidCallback onBack;
  final ValueChanged<ShippingAddress> onNext;
  final Future<void> Function(SavedAddress address)? onSaveAddress;
  final Future<void> Function()? onDeleteSavedAddress;
  final ValueChanged<String?>? onSavedAddressSelected;
  final ShippingAddress? initialAddress;
  final AddressAutocompleteProvider? autocompleteProvider;
  final SavedAddress? savedAddress;
  final String? error;
  final String addressSaveMessage;
  final bool profileAddressBook;

  @override
  State<CheckoutAddressPage> createState() => _CheckoutAddressPageState();
}

class _CheckoutAddressPageState extends State<CheckoutAddressPage> {
  late final TextEditingController _fullName;
  late final TextEditingController _phoneNumber;
  late final TextEditingController _address;
  late final TextEditingController _province;
  late final TextEditingController _city;
  late final TextEditingController _barangay;
  late final TextEditingController _postalCode;
  final _suggestions = <AddressSuggestion>[];
  Map<String, String> _fieldErrors = {};
  String _notes = '';
  String? _error;
  String? _placeId;
  double? _latitude;
  double? _longitude;
  String _addressSource = 'manual';
  String _autocompleteSessionToken = '';
  Timer? _autocompleteTimer;
  bool _isResolvingSuggestion = false;
  bool _isSubmitting = false;
  bool _isSavingAddress = false;
  late bool _editing;
  String? _suggestionError;

  @override
  void initState() {
    super.initState();
    final savedRecord = widget.savedAddress;
    final initial = widget.initialAddress ?? savedRecord?.address;
    _editing = savedRecord == null || widget.initialAddress != null;
    _placeId = widget.initialAddress == null ? savedRecord?.placeId : null;
    _latitude = widget.initialAddress == null ? savedRecord?.latitude : null;
    _longitude = widget.initialAddress == null ? savedRecord?.longitude : null;
    _addressSource = widget.initialAddress == null
        ? savedRecord?.addressSource ?? 'manual'
        : 'manual';
    _notes = initial?.notes ?? '';
    _autocompleteSessionToken = DateTime.now().microsecondsSinceEpoch
        .toString();
    _fullName = TextEditingController(text: initial?.fullName);
    _phoneNumber = TextEditingController(text: initial?.phoneNumber);
    _address = TextEditingController(text: initial?.addressLine1);
    _province = TextEditingController(text: initial?.province);
    _city = TextEditingController(text: initial?.city);
    _barangay = TextEditingController(text: initial?.barangay);
    _postalCode = TextEditingController(text: initial?.postalCode);
  }

  @override
  void didUpdateWidget(covariant CheckoutAddressPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.savedAddress == null && widget.savedAddress != null) {
      final isBlank = [
        _fullName,
        _phoneNumber,
        _address,
        _province,
        _city,
        _barangay,
        _postalCode,
      ].every((controller) => controller.text.trim().isEmpty);
      if (_editing && isBlank) {
        final saved = widget.savedAddress!;
        _fullName.text = saved.address.fullName;
        _phoneNumber.text = saved.address.phoneNumber;
        _address.text = saved.address.addressLine1;
        _province.text = saved.address.province;
        _city.text = saved.address.city;
        _barangay.text = saved.address.barangay;
        _postalCode.text = saved.address.postalCode;
        _placeId = saved.placeId;
        _latitude = saved.latitude;
        _longitude = saved.longitude;
        _addressSource = saved.addressSource;
        _notes = saved.address.notes;
        _editing = false;
      }
    } else if (oldWidget.savedAddress != null && widget.savedAddress == null) {
      _editing = true;
    }
  }

  @override
  void dispose() {
    _autocompleteTimer?.cancel();
    _fullName.dispose();
    _phoneNumber.dispose();
    _address.dispose();
    _province.dispose();
    _city.dispose();
    _barangay.dispose();
    _postalCode.dispose();
    super.dispose();
  }

  Map<String, String> _addressFieldErrors() {
    final fullName = _fullName.text.trim();
    final phoneNumber = _phoneNumber.text.trim();
    final addressLine1 = _address.text.trim();
    final barangay = _barangay.text.trim();
    final city = _city.text.trim();
    final province = _province.text.trim();
    final postalCode = _postalCode.text.trim();
    final errors = <String, String>{};
    if (fullName.isEmpty) {
      errors['fullName'] = 'Enter your full name.';
    } else if (fullName.length > 120) {
      errors['fullName'] = 'Full name must be 120 characters or fewer.';
    }
    if (phoneNumber.isEmpty) {
      errors['phoneNumber'] = 'Enter your phone number.';
    } else if (phoneNumber.length > 32) {
      errors['phoneNumber'] = 'Phone number must be 32 characters or fewer.';
    } else if (normalizePhilippineMobileNumber(phoneNumber) == null) {
      errors['phoneNumber'] =
          'Use a Philippine mobile number: 09xxxxxxxxx or +639xxxxxxxxx.';
    }
    if (addressLine1.isEmpty) {
      errors['address'] = 'Enter your address.';
    } else if (addressLine1.length > 240) {
      errors['address'] = 'Address must be 240 characters or fewer.';
    }
    if (province.isEmpty) {
      errors['province'] = 'Enter your province or region.';
    } else if (province.length > 120) {
      errors['province'] = 'Province must be 120 characters or fewer.';
    }
    if (city.isEmpty) {
      errors['city'] = 'Enter your city or municipality.';
    } else if (city.length > 120) {
      errors['city'] = 'City / Municipality must be 120 characters or fewer.';
    }
    if (barangay.isEmpty) {
      errors['barangay'] = 'Enter your barangay.';
    } else if (barangay.length > 120) {
      errors['barangay'] = 'Barangay must be 120 characters or fewer.';
    }
    if (postalCode.isEmpty) {
      errors['postalCode'] = 'Enter your ZIP code.';
    } else if (postalCode.length > 4 ||
        !RegExp(r'^[0-9]{4}$').hasMatch(postalCode)) {
      errors['postalCode'] = 'ZIP code must contain four digits.';
    }
    return errors;
  }

  ShippingAddress _formAddress() => ShippingAddress(
    fullName: _fullName.text.trim(),
    phoneNumber:
        normalizePhilippineMobileNumber(_phoneNumber.text) ??
        _phoneNumber.text.trim(),
    addressLine1: _address.text.trim(),
    barangay: _barangay.text.trim(),
    city: _city.text.trim(),
    province: _province.text.trim(),
    postalCode: _postalCode.text.trim(),
    notes: _notes,
  );

  bool _validateForm() {
    final fieldErrors = _addressFieldErrors();
    setState(() {
      _fieldErrors = fieldErrors;
      if (fieldErrors.isEmpty) _error = null;
    });
    return fieldErrors.isEmpty;
  }

  SavedAddress _savedAddressFromForm(ShippingAddress address) {
    final now = DateTime.now();
    return SavedAddress(
      id:
          widget.savedAddress?.id ??
          FirestoreSavedAddressRepository.primaryAddressId,
      address: address,
      label: widget.savedAddress?.label ?? 'Home',
      isDefault: true,
      latitude: _latitude,
      longitude: _longitude,
      placeId: _placeId,
      addressSource: _addressSource,
      createdAt: widget.savedAddress?.createdAt ?? now,
      updatedAt: now,
    );
  }

  void _continueToDelivery() {
    if (_isSubmitting || !_validateForm()) return;
    setState(() => _isSubmitting = true);
    widget.onSavedAddressSelected?.call(null);
    final address = _formAddress();
    _province.text = address.province;
    widget.onNext(address);
  }

  void _continueWithSavedAddress() {
    final saved = widget.savedAddress!;
    _notes = saved.address.notes;
    _fullName.text = saved.address.fullName;
    _phoneNumber.text = saved.address.phoneNumber;
    _address.text = saved.address.addressLine1;
    _barangay.text = saved.address.barangay;
    _city.text = saved.address.city;
    _province.text = saved.address.province;
    _postalCode.text = saved.address.postalCode;
    final fieldErrors = _addressFieldErrors();
    if (fieldErrors.isNotEmpty) {
      setState(() {
        _fieldErrors = fieldErrors;
        _editing = true;
      });
      return;
    }
    widget.onSavedAddressSelected?.call(saved.id);
    widget.onNext(_formAddress());
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_validateForm()) return;
    setState(() {
      _fieldErrors.clear();
      _error = null;
      _isSubmitting = true;
    });

    try {
      final address = _formAddress();
      _province.text = address.province;
      final savedAddress = _savedAddressFromForm(address);
      final saveAddress = widget.onSaveAddress;
      if (saveAddress == null) {
        throw StateError('Address saving is unavailable.');
      }
      await saveAddress(savedAddress);
      widget.onSavedAddressSelected?.call(savedAddress.id);
      widget.onNext(address);
    } catch (error) {
      if (mounted) {
        setState(() => _error = savedAddressErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveAddressToMyAddresses() async {
    if (_isSavingAddress || !_validateForm()) return;
    final saveAddress = widget.onSaveAddress;
    if (saveAddress == null) return;
    setState(() {
      _isSavingAddress = true;
      _error = null;
    });
    try {
      await saveAddress(_savedAddressFromForm(_formAddress()));
    } catch (error) {
      if (mounted) {
        setState(() => _error = savedAddressErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isSavingAddress = false);
    }
  }

  void _startNewAddress() {
    widget.onSavedAddressSelected?.call(null);
    _fullName.clear();
    _phoneNumber.clear();
    _address.clear();
    _province.clear();
    _city.clear();
    _barangay.clear();
    _postalCode.clear();
    _placeId = null;
    _latitude = null;
    _longitude = null;
    _addressSource = 'manual';
    _notes = '';
    _suggestions.clear();
    setState(() {
      _editing = true;
      _fieldErrors.clear();
      _error = null;
      _suggestionError = null;
    });
  }

  void _editSavedAddress() {
    widget.onSavedAddressSelected?.call(null);
    setState(() {
      _editing = true;
      _fieldErrors.clear();
      _error = null;
      _suggestionError = null;
    });
  }

  Future<void> _deleteSavedAddress() async {
    try {
      await widget.onDeleteSavedAddress?.call();
      if (mounted) _startNewAddress();
    } on Object {
      if (mounted) {
        setState(() => _error = 'Unable to remove your saved address.');
      }
    }
  }

  void _onAddressChanged(String query) {
    _placeId = null;
    _latitude = null;
    _longitude = null;
    _addressSource = 'manual';
    _autocompleteTimer?.cancel();
    final provider = widget.autocompleteProvider;
    if (provider == null || query.trim().length < 2) {
      setState(() {
        _suggestions.clear();
        _suggestionError = null;
      });
      return;
    }
    if (_suggestionError != null) {
      setState(() => _suggestionError = null);
    }
    _autocompleteTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final suggestions = await provider.suggest(
          query: query.trim(),
          sessionToken: _autocompleteSessionToken,
        );
        if (!mounted || _address.text.trim() != query.trim()) return;
        setState(() {
          _suggestions
            ..clear()
            ..addAll(suggestions);
          _suggestionError = null;
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          _suggestions.clear();
          _suggestionError = 'Address suggestions are temporarily unavailable. You can still enter your address manually.';
        });
      }
    });
  }

  Future<void> _selectAddressSuggestion(AddressSuggestion suggestion) async {
    final provider = widget.autocompleteProvider;
    if (provider == null || _isResolvingSuggestion) return;
    setState(() {
      _isResolvingSuggestion = true;
      _error = null;
      _suggestionError = null;
    });
    try {
      final details = await provider.details(
        placeId: suggestion.placeId,
        sessionToken: _autocompleteSessionToken,
      );
      if (!mounted) return;
      _address.text = details.addressLine1;
      _barangay.text = details.barangay;
      _city.text = details.city;
      _province.text = details.province;
      _postalCode.text = details.postalCode;
      setState(() {
        _placeId = details.placeId;
        _latitude = details.latitude;
        _longitude = details.longitude;
        _addressSource = details.addressSource;
        _suggestions.clear();
      });
    } on Object {
      if (mounted) {
        setState(
          () => _suggestionError =
              'We could not load that address. You can enter it manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _isResolvingSuggestion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WireframeShell(
      child: _CheckoutContentFrame(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WireTopBar(
                title: widget.profileAddressBook ? 'Addresses' : 'Checkout',
                onBack: widget.onBack,
              ),
            ),
            if (!widget.profileAddressBook) const CheckoutSteps(active: 0),
            Expanded(
              child: !_editing && widget.savedAddress != null
                  ? ListView(
                      key: const Key('address-picker'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        CustomerSectionTitle(
                          title: widget.profileAddressBook
                              ? 'Your saved address'
                              : 'Choose an address',
                        ),
                        const SizedBox(height: 5),
                        Text(
                          widget.profileAddressBook
                              ? 'This address is ready to use at checkout.'
                              : 'Confirm where you want this order delivered.',
                          style: TextStyle(
                            fontSize: 14,
                            color: WireframeColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        WireSurface(
                          color: WireframeColors.paper,
                          radius: 16,
                          shadow: false,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.radio_button_checked,
                                  size: 18,
                                  color: WireframeColors.brassInk,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${widget.savedAddress!.address.fullName} · ${widget.savedAddress!.address.phoneNumber}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: WireframeColors.selected,
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                          child: const Text(
                                            'LAST USED',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${widget.savedAddress!.address.addressLine1}, '
                                      '${widget.savedAddress!.address.barangay}, '
                                      '${widget.savedAddress!.address.city}, '
                                      '${widget.savedAddress!.address.province} '
                                      '${widget.savedAddress!.address.postalCode}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.4,
                                        color: WireframeColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    TextButton(
                                      onPressed: _editSavedAddress,
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: const Text(
                                        'Edit address',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        WireButton(
                          label: widget.profileAddressBook
                              ? 'Use this address'
                              : 'Deliver to this address',
                          onPressed: _continueWithSavedAddress,
                        ),
                        const SizedBox(height: 8),
                        WireButton(
                          label: '+ Add new address',
                          onPressed: _startNewAddress,
                          dark: false,
                        ),
                        if (widget.onDeleteSavedAddress != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => unawaited(_deleteSavedAddress()),
                            child: const Text('Remove saved address'),
                          ),
                        ],
                      ],
                    )
                  : ListView(
                      key: const Key('address-form'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        CustomerSectionTitle(
                          title: widget.profileAddressBook
                              ? 'Add a delivery address'
                              : 'Delivery Address',
                        ),
                        const SizedBox(height: 9),
                        WireTextField(
                          label: 'Full Name',
                          icon: Icons.person_outline,
                          controller: _fullName,
                          textInputAction: TextInputAction.next,
                          maxLength: 120,
                          errorText: _fieldErrors['fullName'],
                        ),
                        const SizedBox(height: 10),
                        WireTextField(
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          controller: _phoneNumber,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          maxLength: 32,
                          errorText: _fieldErrors['phoneNumber'],
                        ),
                        const SizedBox(height: 10),
                        WireTextField(
                          key: const Key('checkout-address-search'),
                          label: 'Address',
                          icon: Icons.location_on_outlined,
                          controller: _address,
                          onChanged: _onAddressChanged,
                          textInputAction: TextInputAction.next,
                          maxLength: 240,
                          errorText: _fieldErrors['address'],
                        ),
                        if (_isResolvingSuggestion)
                          const LinearProgressIndicator(minHeight: 2),
                        if (_suggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: WireframeColors.paper,
                              border: Border.all(color: WireframeColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                for (final suggestion in _suggestions)
                                  Material(
                                    color: WireframeColors.paper,
                                    child: ListTile(
                                      key: ValueKey(
                                        'address-suggestion-${suggestion.placeId}',
                                      ),
                                      dense: true,
                                      title: Text(suggestion.primaryText),
                                      subtitle: Text(suggestion.secondaryText),
                                      onTap: () => unawaited(
                                        _selectAddressSuggestion(suggestion),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (_suggestionError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _suggestionError!,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: ScentifyThemeColors.of(context).muted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: WireTextField(
                                label: 'Province / Region',
                                icon: Icons.map_outlined,
                                controller: _province,
                                textInputAction: TextInputAction.next,
                                maxLength: 120,
                                errorText: _fieldErrors['province'],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: WireTextField(
                                label: 'City / Municipality',
                                icon: Icons.location_city_outlined,
                                controller: _city,
                                textInputAction: TextInputAction.next,
                                maxLength: 120,
                                errorText: _fieldErrors['city'],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: WireTextField(
                                label: 'Barangay',
                                icon: Icons.place_outlined,
                                controller: _barangay,
                                textInputAction: TextInputAction.next,
                                maxLength: 120,
                                errorText: _fieldErrors['barangay'],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: WireTextField(
                                label: 'Zip Code',
                                icon: Icons.markunread_mailbox_outlined,
                                controller: _postalCode,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                maxLength: 4,
                                errorText: _fieldErrors['postalCode'],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.addressSaveMessage,
                          style: TextStyle(
                            fontSize: 14,
                            color: ScentifyThemeColors.of(context).muted,
                          ),
                        ),
                      ],
                    ),
            ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null || widget.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error ?? widget.error!,
                          key: const Key('checkout-address-error'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    if (!widget.profileAddressBook &&
                        widget.onSaveAddress != null)
                      TextButton.icon(
                        onPressed: _isSavingAddress
                            ? null
                            : () => unawaited(_saveAddressToMyAddresses()),
                        icon: _isSavingAddress
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bookmark_add_outlined),
                        label: Text(
                          _isSavingAddress
                              ? 'Saving to My Addresses…'
                              : 'Save to My Addresses',
                        ),
                      ),
                    WireButton(
                      label: widget.profileAddressBook
                          ? _isSubmitting
                                ? 'Saving address...'
                                : 'Save address'
                          : _isSubmitting
                          ? 'Continuing...'
                          : 'Continue to Delivery',
                      onPressed: widget.profileAddressBook
                          ? _isSubmitting
                                ? null
                                : _submit
                          : _isSubmitting
                          ? null
                          : _continueToDelivery,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CheckoutDeliveryPage extends StatelessWidget {
  const CheckoutDeliveryPage({
    super.key,
    this.address,
    required this.selected,
    required this.onBack,
    required this.onSelect,
    required this.onNext,
  });

  final ShippingAddress? address;
  final String selected;
  final VoidCallback onBack;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return WireframeShell(
      child: _CheckoutContentFrame(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WireTopBar(title: 'Checkout', onBack: onBack),
            ),
            const CheckoutSteps(active: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                children: [
                  if (address != null) ...[
                    WireSurface(
                      color: WireframeColors.paper,
                      radius: 14,
                      shadow: false,
                      padding: const EdgeInsets.fromLTRB(11, 10, 9, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: WireframeColors.ink,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Delivery Address',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${address!.fullName} · ${address!.phoneNumber}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: WireframeColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${address!.addressLine1}, ${address!.city}, ${address!.province}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: WireframeColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const CustomerSectionTitle(title: 'Delivery Option'),
                  const SizedBox(height: 10),
                  RadioOption(
                    title: 'Standard Delivery',
                    subtitle: '3-5 business days',
                    price: formatPrice(80),
                    selected: selected == 'Standard Delivery',
                    onTap: () => onSelect('Standard Delivery'),
                  ),
                  RadioOption(
                    title: 'Express Delivery',
                    subtitle: '1-2 business days',
                    price: formatPrice(150),
                    selected: selected == 'Express Delivery',
                    onTap: () => onSelect('Express Delivery'),
                  ),
                  RadioOption(
                    title: 'Same day delivery',
                    subtitle: 'Metro Manila only',
                    price: formatPrice(250),
                    selected: selected == 'Same day delivery',
                    onTap: () => onSelect('Same day delivery'),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: WireButton(
                          label: 'Back',
                          onPressed: onBack,
                          dark: false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WireButton(
                          label: 'Continue to Review',
                          onPressed: onNext,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RadioOption extends StatelessWidget {
  const RadioOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.selected,
    required this.onTap,
    this.leadingIcon,
  });

  final String title;
  final String subtitle;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? WireframeColors.selected : WireframeColors.field,
          border: selected ? Border.all(color: WireframeColors.ink) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 17,
            ),
            const SizedBox(width: 8),
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 17, color: WireframeColors.brassInk),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class CheckoutPaymentPage extends StatefulWidget {
  const CheckoutPaymentPage({
    super.key,
    this.address,
    required this.items,
    required this.products,
    required this.delivery,
    required this.onBack,
    required this.onChangeAddress,
    required this.onChangeDelivery,
    required this.onPay,
    required this.itemCount,
    required this.subtotal,
    required this.shippingFee,
    this.paymentMethod = 'cod',
    this.showOnlinePayments = false,
    this.onPaymentMethodChanged,
    this.error,
  });

  final ShippingAddress? address;
  final List<CartItem> items;
  final List<Product> products;
  final String delivery;
  final VoidCallback onBack;
  final VoidCallback onChangeAddress;
  final VoidCallback onChangeDelivery;
  final Future<void> Function() onPay;
  final int itemCount;
  final Money subtotal;
  final Money shippingFee;
  final String paymentMethod;
  final bool showOnlinePayments;
  final ValueChanged<String>? onPaymentMethodChanged;
  final String? error;

  @override
  State<CheckoutPaymentPage> createState() => _CheckoutPaymentPageState();
}

class _CheckoutPaymentPageState extends State<CheckoutPaymentPage> {
  bool _termsAccepted = false;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (!_termsAccepted || _isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.onPay();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Product? _productFor(CartItem item) {
    for (final product in widget.products) {
      if (product.id == item.productId) return product;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.subtotal + widget.shippingFee;
    return WireframeShell(
      bottomBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
          decoration: const BoxDecoration(
            color: WireframeColors.paper,
            border: Border(top: BorderSide(color: WireframeColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated total',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPrice(total.centavos ~/ 100),
                      style: const TextStyle(
                        fontFamily: _modernFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 168,
                child: WireButton(
                  key: const Key('place-order-button'),
                  label: _isSubmitting ? 'Placing order...' : 'Place order',
                  onPressed: _termsAccepted && !_isSubmitting ? _submit : null,
                ),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'Review order', onBack: widget.onBack),
          ),
          const CheckoutSteps(active: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
              children: [
                if (widget.address != null) ...[
                  _ReviewSectionHeader(
                    title: 'Deliver to',
                    action: 'Change',
                    onAction: widget.onChangeAddress,
                  ),
                  const SizedBox(height: 8),
                  WireSurface(
                    color: WireframeColors.paper,
                    radius: 14,
                    shadow: false,
                    padding: const EdgeInsets.fromLTRB(11, 10, 9, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: WireframeColors.ink,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.address!.fullName} · ${widget.address!.phoneNumber}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.address!.addressLine1}, ${widget.address!.barangay}, '
                                '${widget.address!.city}, ${widget.address!.province} '
                                '${widget.address!.postalCode}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: WireframeColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const _ReviewSectionHeader(title: 'Order items'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 14,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.storefront_outlined, size: 15),
                            SizedBox(width: 6),
                            Text(
                              'Scentify Official',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var index = 0; index < widget.items.length; index++)
                        _ReviewOrderItem(
                          item: widget.items[index],
                          product: _productFor(widget.items[index]),
                          showDivider: index < widget.items.length - 1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ReviewSectionHeader(
                  title: 'Shipping method',
                  action: 'Change',
                  onAction: widget.onChangeDelivery,
                ),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 14,
                  shadow: false,
                  padding: const EdgeInsets.all(11),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 18,
                        color: WireframeColors.brassInk,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.delivery,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.delivery == 'Express Delivery'
                                  ? 'Arrives in 1–2 business days'
                                  : widget.delivery == 'Same day delivery'
                                  ? 'Metro Manila only'
                                  : 'Arrives in 3–5 business days',
                              style: const TextStyle(
                                fontSize: 12,
                                color: WireframeColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatPrice(widget.shippingFee.centavos ~/ 100),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _ReviewSectionHeader(title: 'Payment method'),
                const SizedBox(height: 8),
                _PaymentMethodOption(
                  value: 'cod',
                  groupValue: widget.paymentMethod,
                  title: 'Cash on Delivery',
                  subtitle:
                      'Pay in cash when your confirmed order is delivered.',
                  icon: Icons.payments_outlined,
                  onChanged: widget.onPaymentMethodChanged,
                ),
                if (widget.showOnlinePayments) ...[
                  const SizedBox(height: 8),
                  _PaymentMethodOption(
                    value: 'gcash',
                    groupValue: widget.paymentMethod,
                    title: 'GCash',
                    subtitle: 'Pay securely through online checkout.',
                    icon: Icons.credit_card_outlined,
                    onChanged: widget.onPaymentMethodChanged,
                  ),
                ],
                const SizedBox(height: 12),
                const _ReviewSectionHeader(title: 'Order summary'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 14,
                  shadow: false,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SummaryLine(
                        label: 'Item subtotal (${widget.itemCount})',
                        value: formatPrice(widget.subtotal.centavos ~/ 100),
                      ),
                      SummaryLine(
                        label: 'Delivery fee',
                        value: formatPrice(widget.shippingFee.centavos ~/ 100),
                      ),
                      const Divider(color: WireframeColors.border),
                      SummaryLine(
                        label: 'Estimated total',
                        value: formatPrice(total.centavos ~/ 100),
                        strong: true,
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'We’ll confirm the final price and stock before preparing your order.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: WireframeColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Tooltip(
                  message: 'Agree to Terms and Conditions',
                  child: InkWell(
                    onTap: () =>
                        setState(() => _termsAccepted = !_termsAccepted),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        children: [
                          Icon(
                            _termsAccepted
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'I agree to the Terms and Conditions and confirm the order details above.',
                              style: TextStyle(fontSize: 14, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Text(
                      widget.error!,
                      key: const Key('checkout-payment-error'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => WireSurface(
    color: WireframeColors.paper,
    radius: 14,
    shadow: false,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: RadioListTile<String>(
      value: value,
      groupValue: groupValue,
      onChanged: (value) {
        if (value != null) onChanged?.call(value);
      },
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: WireframeColors.brassInk),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, height: 1.3),
      ),
    ),
  );
}

class _ReviewSectionHeader extends StatelessWidget {
  const _ReviewSectionHeader({this.title = '', this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: _modernFontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(action!, style: const TextStyle(fontSize: 14)),
        ),
    ],
  );
}

class _ReviewOrderItem extends StatelessWidget {
  const _ReviewOrderItem({
    required this.item,
    required this.product,
    required this.showDivider,
  });

  final CartItem item;
  final Product? product;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            PlaceholderImage(
              width: 56,
              height: 66,
              radius: 10,
              fit: BoxFit.contain,
              tone: product == null
                  ? WireframeColors.placeholder
                  : productTone(product!),
              backgroundColor: WireframeColors.field,
              assetPath: product == null ? null : productImageAsset(product!),
              imageUrl: product == null ? null : productImageUrl(product!),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _modernFontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.variantLabel} · Qty ${item.quantity}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatPrice(item.lineTotal.centavos ~/ 100),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (showDivider) const Divider(height: 1, color: WireframeColors.border),
    ],
  );
}

class SummaryLine extends StatelessWidget {
  const SummaryLine({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: strong ? 14 : 12,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 14 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ConfirmationPage extends StatelessWidget {
  const ConfirmationPage({
    super.key,
    required this.order,
    required this.onViewOrder,
  });

  final Order? order;
  final VoidCallback onViewOrder;

  @override
  Widget build(BuildContext context) {
    return WireframeShell(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(35),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: WireframeColors.darkButton,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white),
              ),
              const SizedBox(height: 19),
              Text(
                order?.status == OrderStatus.pendingConfirmation
                    ? 'Order Request Sent'
                    : 'Order Placed!',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                order?.status == OrderStatus.pendingConfirmation
                    ? 'We’ll confirm the price and stock before preparing your order.'
                    : order?.paymentMethod == 'cod'
                    ? 'Pay with cash when your order arrives.'
                    : 'Thank you for your purchase.',
                style: TextStyle(fontSize: 14, color: WireframeColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                'Order #${order?.id ?? 'pending'}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              WireButton(label: 'View Order', onPressed: onViewOrder),
              const SizedBox(height: 23),
              const Text(
                'Estimated Delivery',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                order?.deliveryOption.estimatedDays ?? 'To be confirmed',
                style: TextStyle(fontSize: 14, color: WireframeColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PurchaseFilter { all, toConfirm, toPay, toShip, toReceive, completed }

class MyPurchasesPage extends StatefulWidget {
  const MyPurchasesPage({
    super.key,
    required this.orders,
    required this.products,
    this.onNav,
    required this.onBack,
    required this.onOrder,
    this.reviewRepository,
    this.onSubmitReview,
    this.error,
  });

  final List<Order> orders;
  final List<Product> products;
  final ValueChanged<int>? onNav;
  final VoidCallback onBack;
  final ValueChanged<Order?> onOrder;
  final ProductReviewRepository? reviewRepository;
  final Future<void> Function(
    Order order,
    OrderItemSnapshot item,
    int rating,
    String title,
    String comment,
  )?
  onSubmitReview;
  final String? error;

  @override
  State<MyPurchasesPage> createState() => _MyPurchasesPageState();
}

class _MyPurchasesPageState extends State<MyPurchasesPage> {
  _PurchaseFilter _filter = _PurchaseFilter.all;
  final Map<String, Future<bool>> _reviewStatus = {};

  List<Order> get _visibleOrders => widget.orders
      .where((order) {
        return switch (_filter) {
          _PurchaseFilter.all => true,
          _PurchaseFilter.toConfirm =>
            order.status == OrderStatus.pendingConfirmation,
          _PurchaseFilter.toPay => order.status == OrderStatus.pendingPayment,
          _PurchaseFilter.toShip =>
            order.status == OrderStatus.confirmed ||
                order.status == OrderStatus.processing ||
                order.status == OrderStatus.packed,
          _PurchaseFilter.toReceive => order.status == OrderStatus.shipped,
          _PurchaseFilter.completed => order.status == OrderStatus.delivered,
        };
      })
      .toList(growable: false);

  String _label(_PurchaseFilter filter) => switch (filter) {
    _PurchaseFilter.all => 'All',
    _PurchaseFilter.toConfirm => 'To confirm',
    _PurchaseFilter.toPay => 'To pay',
    _PurchaseFilter.toShip => 'To ship',
    _PurchaseFilter.toReceive => 'To receive',
    _PurchaseFilter.completed => 'Completed',
  };

  Product? _productFor(OrderItemSnapshot item) {
    for (final product in widget.products) {
      if (product.id == item.productId) return product;
    }
    return null;
  }

  String _reviewKey(Order order, OrderItemSnapshot item) =>
      '${order.id}|${item.productId}|${item.variantId}';

  Widget _reviewAction(Order order, OrderItemSnapshot item) {
    final repository = widget.reviewRepository;
    if (repository == null || widget.onSubmitReview == null) {
      return const SizedBox.shrink();
    }
    final key = _reviewKey(order, item);
    final reviewStatus = _reviewStatus.putIfAbsent(
      key,
      () => repository.hasReviewForOrderItem(
        orderId: order.id,
        productId: item.productId,
        variantId: item.variantId,
      ),
    );
    return FutureBuilder<bool>(
      future: reviewStatus,
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(top: 4, right: 8),
              child: Text(
                'Reviewed',
                style: TextStyle(
                  fontSize: 12,
                  color: WireframeColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: ValueKey('rate-purchase-${order.id}-${item.variantId}'),
            onPressed: () => unawaited(_ratePurchaseItem(order, item)),
            icon: const Icon(Icons.star_outline_rounded, size: 16),
            label: const Text('Rate this item'),
          ),
        );
      },
    );
  }

  Future<void> _ratePurchaseItem(Order order, OrderItemSnapshot item) async {
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => _ProductReviewDialog(
        productName: item.productName,
        onSubmit: (draft) => widget.onSubmitReview!(
          order,
          item,
          draft.rating,
          '',
          draft.comment,
        ),
      ),
    );
    if (!mounted || submitted != true) return;
    setState(() {
      _reviewStatus[_reviewKey(order, item)] = Future.value(true);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Review submitted')));
  }

  @override
  Widget build(BuildContext context) {
    final orders = _visibleOrders;
    return WireframeShell(
      key: const Key('my-purchases-page'),
      showBottomNav: widget.onNav != null,
      selectedNav: 3,
      onNav: widget.onNav,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'My Purchases', onBack: widget.onBack),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filter in _PurchaseFilter.values)
                  _FilterChip(
                    label: _label(filter),
                    selected: _filter == filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.error != null && widget.orders.isEmpty
                ? Center(
                    child: Text(
                      widget.error!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: WireframeColors.muted,
                      ),
                    ),
                  )
                : orders.isEmpty
                ? const _PurchasesEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final firstItem = order.items.firstOrNull;
                      return Column(
                        children: [
                          _PurchaseCard(
                            key: ValueKey('purchase-${order.id}'),
                            order: order,
                            product: firstItem == null
                                ? null
                                : _productFor(firstItem),
                            onTap: () => widget.onOrder(order),
                          ),
                          if (order.status == OrderStatus.delivered)
                            for (final item in order.items)
                              _reviewAction(order, item),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductReviewDraft {
  const _ProductReviewDraft({required this.rating, required this.comment});

  final int rating;
  final String comment;
}

class _ProductReviewDialog extends StatefulWidget {
  const _ProductReviewDialog({
    required this.productName,
    required this.onSubmit,
  });

  final String productName;
  final Future<void> Function(_ProductReviewDraft draft) onSubmit;

  @override
  State<_ProductReviewDialog> createState() => _ProductReviewDialogState();
}

class _ProductReviewDialogState extends State<_ProductReviewDialog> {
  final _comment = TextEditingController();
  var _rating = 0;
  var _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _ProductReviewDraft(rating: _rating, comment: _comment.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = _reviewFailureMessage(error);
        });
      }
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.productName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var rating = 1; rating <= 5; rating++)
                IconButton(
                  key: Key('review-rating-$rating'),
                  tooltip: '$rating stars',
                  visualDensity: VisualDensity.compact,
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _rating = rating),
                  icon: Icon(
                    rating <= _rating ? Icons.star_rounded : Icons.star_outline,
                    color: WireframeColors.tobacco,
                  ),
                ),
            ],
          ),
          TextField(
            key: const Key('review-comment-input'),
            controller: _comment,
            maxLength: 1000,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Your review (optional)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: WireframeColors.tobacco),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('review-submit-button'),
          onPressed: _rating == 0 || _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit review'),
        ),
      ],
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    super.key,
    required this.order,
    required this.product,
    required this.onTap,
  });

  final Order order;
  final Product? product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = order.items.firstOrNull;
    final itemCount = order.items.fold<int>(
      0,
      (total, orderItem) => total + orderItem.quantity,
    );
    final created = order.createdAt;
    final date = '${created.month}/${created.day}/${created.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: WireSurface(
        color: WireframeColors.paper,
        radius: 18,
        shadow: false,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 15),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Scentify Official',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _orderStatusColor(order.status)
                        .withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _orderStatusLabel(order.status).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: _orderStatusColor(order.status),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 18, color: WireframeColors.border),
            Row(
              children: [
                PlaceholderImage(
                  width: 62,
                  height: 72,
                  radius: 12,
                  fit: BoxFit.contain,
                  tone: product == null
                      ? WireframeColors.placeholder
                      : productTone(product!),
                  backgroundColor: WireframeColors.field,
                  assetPath: product == null
                      ? null
                      : productImageAsset(product!),
                  imageUrl: product == null ? null : productImageUrl(product!),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item?.productName ?? 'Scentify order',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: _modernFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item == null
                            ? '$itemCount items'
                            : '${item.variantLabel} · Qty ${item.quantity}'
                                  '${order.items.length > 1 ? ' +${order.items.length - 1} more' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: WireframeColors.muted,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        formatPrice(order.total.centavos ~/ 100),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _orderPaymentSummary(order),
                        style: const TextStyle(
                          fontSize: 12,
                          color: WireframeColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 18, color: WireframeColors.border),
            Row(
              children: [
                Text(
                  'Order ${order.id} · $date',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
                const Spacer(),
                const Text(
                  'View details',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchasesEmptyState extends StatelessWidget {
  const _PurchasesEmptyState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 38,
            color: WireframeColors.faint,
          ),
          SizedBox(height: 12),
          Text(
            'No purchases here yet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 5),
          Text(
            'Orders in this status will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: WireframeColors.muted),
          ),
        ],
      ),
    ),
  );
}

class TrackingPage extends StatelessWidget {
  const TrackingPage({super.key, required this.order, required this.onBack});

  final Order? order;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final currentOrder = order;
    return WireframeShell(
      key: const Key('tracking-page'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(
              title: currentOrder == null
                  ? 'Order monitor'
                  : 'Order #${currentOrder.id}',
              onBack: onBack,
            ),
          ),
          Expanded(
            child: currentOrder == null
                ? const Center(
                    child: Text(
                      'No orders yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                  )
                : _OrderMonitor(order: currentOrder),
          ),
        ],
      ),
    );
  }
}

class _OrderMonitor extends StatelessWidget {
  const _OrderMonitor({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final statuses = _orderProgressStatuses(order);
    final activeIndex = statuses.indexOf(order.status);
    final progress = (activeIndex + 1) / statuses.length;
    final itemCount = order.items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );

    return ListView(
      key: const Key('order-monitor-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        WireSurface(
          key: const Key('tracking-status-card'),
          color: WireframeColors.paper,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _orderStatusColor(order.status),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _orderStatusIcon(order.status),
                      size: 20,
                      color: WireframeColors.paper,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const WireEyebrow(
                          'Live order status',
                          color: WireframeColors.muted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _orderStatusLabel(order.status),
                          style: const TextStyle(
                            fontFamily: _modernFontFamily,
                            fontSize: 18,
                            color: WireframeColors.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatPrice(order.total.centavos ~/ 100),
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                _orderStatusDescription(
                  order.status,
                  paymentStatus: order.paymentStatus,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: WireframeColors.muted,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: WireframeColors.field,
                  color: WireframeColors.ink,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.ink,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Est. ${order.deliveryOption.estimatedDays}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionHeader(title: 'Order progress'),
        const SizedBox(height: 8),
        WireSurface(
          color: WireframeColors.paper,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            children: [
              for (var index = 0; index < statuses.length; index++)
                _OrderTimelineStep(
                  status: statuses[index],
                  isComplete: index < activeIndex,
                  isCurrent: index == activeIndex,
                  showConnector: index < statuses.length - 1,
                  paymentStatus: order.paymentStatus,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(title: 'Items ($itemCount)'),
        const SizedBox(height: 8),
        WireSurface(
          color: WireframeColors.paper,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              for (var index = 0; index < order.items.length; index++)
                _OrderItemRow(
                  item: order.items[index],
                  showDivider: index < order.items.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionHeader(title: 'Delivery details'),
        const SizedBox(height: 8),
        WireSurface(
          color: WireframeColors.paper,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.shippingAddress.fullName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${order.shippingAddress.addressLine1}, '
                '${order.shippingAddress.barangay}, '
                '${order.shippingAddress.city}, '
                '${order.shippingAddress.province} '
                '${order.shippingAddress.postalCode}',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: WireframeColors.muted,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 15,
                    color: WireframeColors.brassInk,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${order.deliveryOption.name} · '
                      '${order.deliveryOption.estimatedDays}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WireframeColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionHeader(title: 'Payment details'),
        const SizedBox(height: 8),
        WireSurface(
          color: WireframeColors.paper,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            children: [
              SummaryLine(
                label: 'Payment method',
                value: _orderPaymentMethodLabel(order.paymentMethod),
              ),
              SummaryLine(
                label: 'Payment status',
                value: _orderPaymentStatusLabel(order.paymentStatus),
              ),
              const Divider(color: WireframeColors.border),
              SummaryLine(
                label: order.status == OrderStatus.pendingConfirmation
                    ? 'Estimated total'
                    : 'Order total',
                value: formatPrice(order.total.centavos ~/ 100),
                strong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionHeader(title: 'Invoice'),
        const SizedBox(height: 8),
        WireSurface(
          key: const Key('order-invoice-card'),
          color: WireframeColors.paper,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SummaryLine(label: 'Invoice number', value: order.id),
              SummaryLine(
                label: 'Invoice date',
                value: _invoiceDate(order.createdAt),
              ),
              SummaryLine(
                label: 'Bill to',
                value: order.shippingAddress.fullName,
              ),
              const Divider(color: WireframeColors.border),
              for (final item in order.items)
                SummaryLine(
                  label:
                      '${item.productName} · ${item.variantLabel} × ${item.quantity}',
                  value: formatPrice(item.lineTotal.centavos ~/ 100),
                ),
              const Divider(color: WireframeColors.border),
              SummaryLine(
                label: 'Subtotal',
                value: formatPrice(order.subtotal.centavos ~/ 100),
              ),
              SummaryLine(
                label: 'Delivery',
                value: formatPrice(order.deliveryFee.centavos ~/ 100),
              ),
              SummaryLine(
                label: 'Total',
                value: formatPrice(order.total.centavos ~/ 100),
                strong: true,
              ),
            ],
          ),
        ),
        if (order.status == OrderStatus.pendingConfirmation)
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              'Final price and availability will be confirmed before the order is prepared.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: WireframeColors.muted,
              ),
            ),
          ),
        const SizedBox(height: 12),
        const CustomerSectionTitle(title: 'Delivery update'),
        const SizedBox(height: 8),
        WireSurface(
          color: WireframeColors.paper,
          radius: 16,
          shadow: false,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: WireframeColors.selected,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _orderStatusIcon(order.status),
                  size: 18,
                  color: WireframeColors.tobacco,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _orderStatusLabel(order.status),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_orderStatusDescription(order.status, paymentStatus: order.paymentStatus)} We will notify you when the status changes.',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: WireframeColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderTimelineStep extends StatelessWidget {
  const _OrderTimelineStep({
    required this.status,
    required this.isComplete,
    required this.isCurrent,
    required this.showConnector,
    this.paymentStatus,
  });

  final OrderStatus status;
  final bool isComplete;
  final bool isCurrent;
  final bool showConnector;
  final String? paymentStatus;

  @override
  Widget build(BuildContext context) {
    final active = isComplete || isCurrent;
    final color = active ? _orderStatusColor(status) : WireframeColors.border;
    return SizedBox(
      key: ValueKey('order-status-${status.name}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 27,
            child: Column(
              children: [
                Container(
                  width: 25,
                  height: 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? color : WireframeColors.canvas,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.3),
                  ),
                  child: Icon(
                    _orderStatusIcon(status),
                    size: 13,
                    color: active ? WireframeColors.paper : color,
                  ),
                ),
                if (showConnector)
                  Container(
                    width: 2,
                    height: 28,
                    color: isComplete ? color : WireframeColors.border,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _orderStatusLabel(status),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: active
                                ? WireframeColors.ink
                                : WireframeColors.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _orderStatusDescription(
                            status,
                            paymentStatus: paymentStatus,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: WireframeColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrent)
                    const Text(
                      'NOW',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.brassInk,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    )
                  else if (isComplete)
                    const Icon(
                      Icons.check,
                      size: 15,
                      color: WireframeColors.olive,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item, required this.showDivider});

  final OrderItemSnapshot item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: WireframeColors.border))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WireframeColors.field,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.local_florist_outlined,
              size: 17,
              color: WireframeColors.brassInk,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.variantLabel} · Qty ${item.quantity}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatPrice(item.lineTotal.centavos ~/ 100),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({
    super.key,
    required this.notifications,
    required this.readNotificationIds,
    required this.onBack,
    required this.onMarkAllRead,
    required this.onOpen,
  });

  final List<ScentifyNotification> notifications;
  final Set<String> readNotificationIds;
  final VoidCallback onBack;
  final VoidCallback onMarkAllRead;
  final ValueChanged<ScentifyNotification> onOpen;

  @override
  Widget build(BuildContext context) {
    final unreadCount = notifications
        .where((notification) => !readNotificationIds.contains(notification.id))
        .length;
    return WireframeShell(
      key: const Key('notifications-page'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(
              title: 'Notifications',
              onBack: onBack,
              actions: [
                IconButton(
                  key: const Key('notifications-mark-all'),
                  onPressed: unreadCount == 0 ? null : onMarkAllRead,
                  icon: const Icon(Icons.done_all, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  tooltip: 'Mark all as read',
                ),
              ],
            ),
          ),
          Expanded(
            child: notifications.isEmpty
                ? const _NotificationsEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 24),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _NotificationTile(
                        key: ValueKey('notification-${notification.id}'),
                        notification: notification,
                        isRead: readNotificationIds.contains(notification.id),
                        onTap: () => onOpen(notification),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.isRead,
    required this.onTap,
  });

  final ScentifyNotification notification;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: WireSurface(
        color: isRead ? WireframeColors.paper : WireframeColors.selected,
        padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isRead ? WireframeColors.field : WireframeColors.gold,
                shape: BoxShape.circle,
              ),
              child: Icon(
                notification.orderId == null
                    ? Icons.notifications_none
                    : Icons.local_shipping_outlined,
                size: 17,
                color: isRead ? WireframeColors.muted : WireframeColors.paper,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: WireframeColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: WireframeColors.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _notificationTimeLabel(notification.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 17,
              color: WireframeColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsEmptyState extends StatelessWidget {
  const _NotificationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: WireSurface(
          color: WireframeColors.paper,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_none,
                size: 29,
                color: WireframeColors.brassInk,
              ),
              const SizedBox(height: 9),
              const Text(
                'You’re all caught up',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                'Order and delivery updates will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: WireframeColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HelpCentrePage extends StatelessWidget {
  const HelpCentrePage({
    super.key,
    required this.onBack,
    required this.onPurchases,
  });

  final VoidCallback onBack;
  final VoidCallback onPurchases;

  @override
  Widget build(BuildContext context) {
    const questions = <(String, String)>[
      (
        'How do I track my order?',
        'Open Profile, choose My Purchases, then select an order to view its live status and delivery timeline.',
      ),
      (
        'Can I change an order after placing it?',
        'Review the address, variant, and delivery details before sending the order request. Changes may no longer be available once processing starts.',
      ),
      (
        'How do I choose the right size?',
        'Open a product, compare the available volumes and prices, then select an in-stock size before adding it to your bag.',
      ),
      (
        'Why is a scent unavailable?',
        'A volume can sell out independently of the other sizes. Choose another available volume or revisit the product later.',
      ),
      (
        'Where can I review a delivered item?',
        'Delivered purchases show review actions from My Purchases when the item is eligible and has not been reviewed yet.',
      ),
    ];

    return WireframeShell(
      key: const Key('help-centre-page'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'Help Centre', onBack: onBack),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
              children: [
                WireSurface(
                  color: WireframeColors.darkSurface,
                  border: false,
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.support_agent,
                        size: 28,
                        color: WireframeColors.goldSoft,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How can we help?',
                              style: TextStyle(
                                fontFamily: _modernFontFamily,
                                fontSize: 17,
                                color: WireframeColors.paper,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Find quick answers about shopping, checkout, and orders.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: WireframeColors.goldSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const CustomerSectionTitle(title: 'Your orders'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 16,
                  shadow: false,
                  padding: EdgeInsets.zero,
                  child: MenuRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Track or review a purchase',
                    subtitle: 'Open your order history and live status',
                    onTap: onPurchases,
                    showDivider: false,
                  ),
                ),
                const SizedBox(height: 18),
                const CustomerSectionTitle(title: 'Frequently asked questions'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 16,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      for (final question in questions)
                        ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            10,
                            0,
                            10,
                            12,
                          ),
                          iconColor: WireframeColors.brassInk,
                          collapsedIconColor: WireframeColors.muted,
                          title: Text(
                            question.$1,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                question.$2,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
                                  color: WireframeColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AboutScentifyPage extends StatelessWidget {
  const AboutScentifyPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return WireframeShell(
      key: const Key('about-scentify-page'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'About Scentify', onBack: onBack),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                WireSurface(
                  color: WireframeColors.darkSurface,
                  border: false,
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                  child: const Column(
                    children: [
                      ScentifyLogo(size: 28, color: WireframeColors.paper),
                      SizedBox(height: 12),
                      Text(
                        'Find a scent that feels like you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _modernFontFamily,
                          fontSize: 18,
                          color: WireframeColors.goldSoft,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const CustomerSectionTitle(title: 'Our purpose'),
                const SizedBox(height: 8),
                const Text(
                  'Scentify makes fragrance discovery easier by bringing curated products, clear size choices, and a dependable purchase journey into one place.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: WireframeColors.muted,
                  ),
                ),
                const SizedBox(height: 18),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 16,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: const Column(
                    children: [
                      MenuRow(
                        icon: Icons.auto_awesome_outlined,
                        label: 'Curated discovery',
                        subtitle: 'Browse by mood, notes, and preferences',
                      ),
                      MenuRow(
                        icon: Icons.verified_user_outlined,
                        label: 'Clear purchase details',
                        subtitle: 'Variant, delivery, payment, and totals before order',
                      ),
                      MenuRow(
                        icon: Icons.inventory_2_outlined,
                        label: 'Order transparency',
                        subtitle:
                            'Status updates from confirmation to delivery',
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Scentify 1.0.0 (1)',
                    style: TextStyle(
                      fontSize: 12,
                      color: WireframeColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onBack,
    required this.onEditProfile,
    required this.onNotifications,
    required this.onAddresses,
    required this.onHelp,
    required this.onAbout,
  });

  final ThemeMode themeMode;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onBack;
  final VoidCallback onEditProfile;
  final VoidCallback onNotifications;
  final VoidCallback onAddresses;
  final VoidCallback onHelp;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return WireframeShell(
      key: const Key('settings-page'),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WireTopBar(title: 'Settings', onBack: onBack),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const CustomerSectionTitle(title: 'Preferences'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  padding: EdgeInsets.zero,
                  child: Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      key: const Key('settings-dark-mode'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      title: const Text('Dark appearance'),
                      subtitle: const Text('Choose a comfortable screen theme'),
                      value: themeMode == ThemeMode.dark,
                      activeTrackColor: colors.primaryAction,
                      onChanged: onThemeChanged,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const CustomerSectionTitle(title: 'Account'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      MenuRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Edit profile',
                        subtitle: 'Update your display name',
                        onTap: onEditProfile,
                      ),
                      MenuRow(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notifications',
                        subtitle: 'View order and product updates',
                        onTap: onNotifications,
                      ),
                      MenuRow(
                        icon: Icons.location_on_outlined,
                        label: 'Addresses',
                        subtitle: 'Manage delivery addresses',
                        onTap: onAddresses,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const CustomerSectionTitle(title: 'Support'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      MenuRow(
                        icon: Icons.help_outline_rounded,
                        label: 'Help centre',
                        subtitle: 'FAQs and order guidance',
                        onTap: onHelp,
                      ),
                      MenuRow(
                        icon: Icons.info_outline_rounded,
                        label: 'About Scentify',
                        subtitle: 'App information',
                        onTap: onAbout,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.onNav,
    required this.onSettings,
    required this.onOrders,
    required this.onWishlist,
    required this.onAddresses,
    required this.onHelp,
    required this.onAbout,
    required this.onLogout,
    required this.orderCount,
    required this.wishlistCount,
    required this.profile,
    required this.latestOrder,
    required this.products,
    required this.onTrackOrder,
    required this.onEditProfile,
    this.profileError,
  });

  final ValueChanged<int> onNav;
  final VoidCallback onSettings;
  final VoidCallback onOrders;
  final VoidCallback onWishlist;
  final VoidCallback onAddresses;
  final VoidCallback onHelp;
  final VoidCallback onAbout;
  final VoidCallback onLogout;
  final int orderCount;
  final int wishlistCount;
  final UserProfile profile;
  final Order? latestOrder;
  final List<Product> products;
  final VoidCallback onTrackOrder;
  final VoidCallback onEditProfile;
  final String? profileError;

  @override
  Widget build(BuildContext context) {
    final displayName = profile.displayName.trim().isEmpty
        ? 'Scentify customer'
        : profile.displayName.trim();
    final email = profile.email.trim().isEmpty
        ? 'No email connected'
        : profile.email.trim();
    final initials = _profileInitials(displayName);
    Product? latestProduct;
    if (latestOrder != null && latestOrder!.items.isNotEmpty) {
      final productId = latestOrder!.items.first.productId;
      for (final product in products) {
        if (product.id == productId) {
          latestProduct = product;
          break;
        }
      }
    }

    return WireframeShell(
      selectedNav: 4,
      onNav: onNav,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: ScentifyCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: WireframeColors.field,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        fontFamily: _modernFontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'My account',
                          style: TextStyle(
                            fontSize: 12,
                            color: WireframeColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _modernFontFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WireframeColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('profile-edit-button'),
                    onPressed: onEditProfile,
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    tooltip: 'Edit profile',
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (profileError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: WireframeColors.field,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.sync_problem_outlined,
                              size: 14,
                              color: WireframeColors.muted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                profileError!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: WireframeColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                const SectionHeader(title: 'Account overview'),
                const SizedBox(height: 9),
                WireSurface(
                  color: WireframeColors.paper,
                  radius: 16,
                  shadow: false,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: ProfileStat(
                          label: 'Orders',
                          value: '$orderCount',
                          onTap: onOrders,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 34,
                        color: WireframeColors.border,
                      ),
                      Expanded(
                        child: ProfileStat(
                          label: 'Wishlist',
                          value: '$wishlistCount',
                          onTap: onWishlist,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const ProfileMembershipCard(),
                const SizedBox(height: 18),
                const SectionHeader(title: 'Latest purchase'),
                const SizedBox(height: 9),
                if (latestOrder == null)
                  const ProfileEmptyOrderCard()
                else
                  ProfileOrderCard(
                    order: latestOrder!,
                    product: latestProduct,
                    onTap: onOrders,
                    onTrack: onTrackOrder,
                  ),
                const SizedBox(height: 18),
                const WireEyebrow('Manage your Scentify'),
                const SizedBox(height: 8),
                WireSurface(
                  color: WireframeColors.paper,
                  shadow: false,
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      MenuRow(
                        icon: Icons.shopping_bag_outlined,
                        label: 'My Orders',
                        subtitle: pluralized(orderCount, 'order'),
                        onTap: onOrders,
                      ),
                      MenuRow(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        subtitle: 'Theme and account preferences',
                        onTap: onSettings,
                      ),
                      MenuRow(
                        icon: Icons.favorite_border,
                        label: 'My Wishlist',
                        subtitle: pluralized(wishlistCount, 'saved scent'),
                        onTap: onWishlist,
                      ),
                      MenuRow(
                        icon: Icons.location_on_outlined,
                        label: 'Addresses',
                        subtitle: 'Delivery addresses',
                        onTap: onAddresses,
                      ),
                      MenuRow(
                        icon: Icons.help_outline,
                        label: 'Help Centre',
                        subtitle: 'FAQs and order guidance',
                        onTap: onHelp,
                      ),
                      MenuRow(
                        icon: Icons.info_outline,
                        label: 'About Scentify',
                        subtitle: 'Version 1.0.0',
                        onTap: onAbout,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ScentifySecondaryButton(
                  label: 'Log Out',
                  icon: Icons.logout_rounded,
                  onPressed: onLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileStat extends StatelessWidget {
  const ProfileStat({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: _modernFontFamily,
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            WireEyebrow(label),
          ],
        ),
      ),
    );
  }
}

class ProfileMembershipCard extends StatelessWidget {
  const ProfileMembershipCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ScentifyCard(
      color: WireframeColors.darkSurface,
      border: false,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFF34332E),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: WireframeColors.goldSoft,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SCENTIFY PROFILE',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: WireframeColors.goldSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your saved scents and orders, together',
                  style: TextStyle(
                    fontSize: 12,
                    color: WireframeColors.paper,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileOrderCard extends StatelessWidget {
  const ProfileOrderCard({
    super.key,
    required this.order,
    required this.product,
    required this.onTap,
    required this.onTrack,
  });

  final Order order;
  final Product? product;
  final VoidCallback onTap;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: WireSurface(
        color: WireframeColors.darkSurface,
        border: false,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 72,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: WireframeColors.paper,
                borderRadius: BorderRadius.circular(14),
              ),
              child: product == null
                  ? const Icon(
                      Icons.shopping_bag_outlined,
                      color: WireframeColors.muted,
                    )
                  : PlaceholderImage(
                      radius: 10,
                      fit: BoxFit.contain,
                      tone: productTone(product!),
                      backgroundColor: Colors.transparent,
                      assetPath: productImageAsset(product!),
                      imageUrl: productImageUrl(product!),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: WireEyebrow(
                          'Latest order',
                          color: WireframeColors.goldSoft,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _orderStatusColor(order.status)
                              .withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _orderStatusLabel(order.status),
                          style: const TextStyle(
                            fontSize: 12,
                            color: WireframeColors.paper,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Order #${shortOrderNumber(order.id)}',
                    style: TextStyle(
                      fontFamily: _modernFontFamily,
                      fontSize: 12,
                      color: WireframeColors.paper,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${pluralized(itemCount, 'item')} · '
                    '${order.deliveryOption.estimatedDays}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD8D6CF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onTrack,
                      icon: const Icon(Icons.local_shipping_outlined, size: 15),
                      label: const Text('Track order'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: WireframeColors.paper,
                        side: const BorderSide(color: Color(0xFF5B5A54)),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileEmptyOrderCard extends StatelessWidget {
  const ProfileEmptyOrderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const WireSurface(
      color: WireframeColors.paper,
      border: false,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 20,
            color: WireframeColors.muted,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No orders yet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 3),
                Text(
                  'Your next order will appear here in real time.',
                  style: TextStyle(fontSize: 14, color: WireframeColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _profileInitials(String displayName) {
  final words = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return 'S';
  }
  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }
  return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'
      .toUpperCase();
}

class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: colors.border))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.selected,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: colors.brassInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 14, color: colors.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 17, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

enum _AdminModule {
  overview,
  orders,
  products,
  inventory,
  customers,
  notifications,
  settings,
  access,
}

extension _AdminModulePresentation on _AdminModule {
  String get label => switch (this) {
    _AdminModule.overview => 'Overview',
    _AdminModule.orders => 'Orders',
    _AdminModule.products => 'Products',
    _AdminModule.inventory => 'Inventory',
    _AdminModule.customers => 'Customers',
    _AdminModule.notifications => 'Notifications',
    _AdminModule.settings => 'Settings',
    _AdminModule.access => 'Admin access',
  };

  IconData get icon => switch (this) {
    _AdminModule.overview => Icons.dashboard_outlined,
    _AdminModule.orders => Icons.receipt_long_outlined,
    _AdminModule.products => Icons.shopping_bag_outlined,
    _AdminModule.inventory => Icons.inventory_2_outlined,
    _AdminModule.customers => Icons.people_outline,
    _AdminModule.notifications => Icons.notifications_none,
    _AdminModule.settings => Icons.settings_outlined,
    _AdminModule.access => Icons.admin_panel_settings_outlined,
  };

  String get imageAsset => switch (this) {
    _AdminModule.overview => ScentifyAssets.heroEvening,
    _AdminModule.orders => ScentifyAssets.baccaratRouge540,
    _AdminModule.products => ScentifyAssets.libre,
    _AdminModule.inventory => ScentifyAssets.hero,
    _AdminModule.customers => ScentifyAssets.onboardingFavorites,
    _AdminModule.notifications => ScentifyAssets.authEditorialHero,
    _AdminModule.settings => ScentifyAssets.onboardingAuthenticShopping,
    _AdminModule.access => ScentifyAssets.superadminDashboardHero,
  };

  Color get tileTint => switch (this) {
    _AdminModule.overview => const Color(0xFF7F654A),
    _AdminModule.orders => const Color(0xFF9A613A),
    _AdminModule.products => const Color(0xFF69724A),
    _AdminModule.inventory => const Color(0xFF596344),
    _AdminModule.customers => const Color(0xFF9A724C),
    _AdminModule.notifications => const Color(0xFF6D553F),
    _AdminModule.settings => const Color(0xFF6D553F),
    _AdminModule.access => const Color(0xFF2C251E),
  };
}

class AdminPage extends StatefulWidget {
  const AdminPage({
    super.key,
    required this.orderRepository,
    this.catalogRepository,
    required this.profile,
    required this.onLogout,
    this.products = const [],
  });

  final OrderRepository orderRepository;
  final CatalogRepository? catalogRepository;
  final UserProfile profile;
  final VoidCallback onLogout;
  final List<Product> products;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  late final AdminOrderService _orderService;
  AdminInventoryService? _inventoryService;
  StreamSubscription<List<Order>>? _ordersSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _inventorySubscription;
  List<Order> _orders = const [];
  List<Map<String, dynamic>> _inventoryChanges = const [];
  String? _error;
  String? _activeOrderId;
  _AdminModule _selectedModule = _AdminModule.overview;

  List<_AdminModule> get _availableModules => [
    _AdminModule.overview,
    _AdminModule.orders,
    _AdminModule.products,
    _AdminModule.inventory,
    _AdminModule.customers,
    _AdminModule.notifications,
    _AdminModule.settings,
    if (widget.profile.isSuperAdmin) _AdminModule.access,
  ];

  @override
  void initState() {
    super.initState();
    _orderService = AdminOrderService(widget.orderRepository);
    final catalogRepository = widget.catalogRepository;
    if (catalogRepository != null) {
      _inventoryService = AdminInventoryService(catalogRepository);
      _inventorySubscription = _inventoryService!.watchRecentChanges().listen((
        changes,
      ) {
        if (mounted) setState(() => _inventoryChanges = changes);
      });
    }
    _ordersSubscription = widget.orderRepository.watchAll().listen(
      (orders) {
        if (!mounted) {
          return;
        }
        setState(() {
          _orders = List.unmodifiable(orders);
          _error = null;
        });
      },
      onError: (Object error, StackTrace stack) {
        if (mounted) {
          setState(() {
            _error = 'Orders are unavailable. Confirm this account has an admin or superadmin role.';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    unawaited(_ordersSubscription?.cancel());
    unawaited(_inventorySubscription?.cancel());
    super.dispose();
  }

  OrderStatus? _nextStatus(OrderStatus status) {
    return switch (status) {
      OrderStatus.pendingPayment => OrderStatus.confirmed,
      OrderStatus.pendingConfirmation => OrderStatus.confirmed,
      OrderStatus.confirmed => OrderStatus.processing,
      OrderStatus.processing => OrderStatus.packed,
      OrderStatus.packed => OrderStatus.shipped,
      OrderStatus.shipped => OrderStatus.delivered,
      OrderStatus.delivered => null,
      OrderStatus.cancelled => null,
    };
  }

  String _actionLabel(OrderStatus current, OrderStatus nextStatus) {
    if (current == OrderStatus.pendingConfirmation) {
      return 'Confirm after review';
    }
    return nextStatus == OrderStatus.confirmed
        ? 'Approve payment'
        : 'Mark ${_orderStatusLabel(nextStatus)}';
  }

  List<_AdminModule> get _dashboardModules => [
    _AdminModule.overview,
    _AdminModule.orders,
    _AdminModule.products,
    _AdminModule.inventory,
    _AdminModule.customers,
    if (widget.profile.isSuperAdmin) _AdminModule.access,
  ];

  void _selectModule(_AdminModule module) {
    setState(() => _selectedModule = module);
  }

  Widget _moduleGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        return GridView.builder(
          key: const Key('admin-module-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _dashboardModules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 3 ? 1.52 : 1.28,
          ),
          itemBuilder: (context, index) {
            final module = _dashboardModules[index];
            return _AdminModuleCard(
              key: module == _AdminModule.access
                  ? null
                  : ValueKey('admin-module-${module.name}'),
              module: module,
              onTap: () => _selectModule(module),
            );
          },
        );
      },
    );
  }

  Widget _moduleTabs() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final module in _availableModules) ...[
          Builder(
            builder: (context) {
              final selected = _selectedModule == module;
              return ChoiceChip(
                key: ValueKey('admin-module-${module.name}'),
                avatar: Icon(
                  module.icon,
                  size: 15,
                  color: selected
                      ? WireframeColors.goldSoft
                      : WireframeColors.muted,
                ),
                label: Text(module.label),
                selected: selected,
                onSelected: (_) => setState(() => _selectedModule = module),
                selectedColor: WireframeColors.darkSurface,
                backgroundColor: WireframeColors.paper,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: selected ? WireframeColors.paper : WireframeColors.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                visualDensity: VisualDensity.standard,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                side: BorderSide(
                  color: selected
                      ? WireframeColors.darkSurface
                      : WireframeColors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  List<Widget> _buildModuleContent({
    required int customerCount,
    required int outOfStockCount,
    required int lowStockCount,
  }) {
    final pendingOrders = _orders
        .where(
          (order) =>
              order.status == OrderStatus.pendingPayment ||
              order.status == OrderStatus.pendingConfirmation,
        )
        .length;
    final activeOrders = _orders
        .where(
          (order) =>
              order.status != OrderStatus.pendingPayment &&
              order.status != OrderStatus.pendingConfirmation &&
              order.status != OrderStatus.delivered &&
              order.status != OrderStatus.cancelled,
        )
        .length;
    final completedOrders = _orders
        .where((order) => order.status == OrderStatus.delivered)
        .length;
    switch (_selectedModule) {
      case _AdminModule.overview:
        return [
          const SectionHeader(title: 'Dashboard overview'),
          const SizedBox(height: 5),
          const Text(
            'Review COD requests, check current prices and stock, and move confirmed orders through fulfillment.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          if (_orders.isEmpty)
            const _AdminEmptyState(message: 'No orders yet.')
          else ...[
            const Text(
              'Recent orders',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._orders.take(3).map(_orderCard),
          ],
        ];
      case _AdminModule.orders:
        return [
          const SectionHeader(title: 'Orders to review'),
          const SizedBox(height: 5),
          const Text(
            'Check product prices and stock before confirming a COD request. Only then move the order through fulfillment.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          _AdminOrdersSummary(
            pendingOrders: pendingOrders,
            activeOrders: activeOrders,
            completedOrders: completedOrders,
          ),
          const SizedBox(height: 14),
          if (_orders.isEmpty)
            const _AdminEmptyState(message: 'No orders yet.')
          else
            ..._orders.map(_orderCard),
        ];
      case _AdminModule.products:
        return [
          const SectionHeader(title: 'Product catalog'),
          const SizedBox(height: 5),
          Text(
            '${widget.products.length} products are loaded. This module shows the current catalog.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          const _AdminReadOnlyNotice(
            message: 'Product editing and publishing are not available yet.',
          ),
          const SizedBox(height: 12),
          if (widget.products.isEmpty)
            const _AdminEmptyState(message: 'The catalog is still loading.')
          else
            WireSurface(
              color: WireframeColors.paper,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final product in widget.products.take(10))
                    _AdminProductRow(product: product),
                ],
              ),
            ),
          if (widget.products.length > 10) ...[
            const SizedBox(height: 8),
            Text(
              '+ ${widget.products.length - 10} more products in the catalog',
              style: const TextStyle(
                fontSize: 14,
                color: WireframeColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ];
      case _AdminModule.inventory:
        return [
          const SectionHeader(title: 'Inventory health'),
          const SizedBox(height: 5),
          const Text(
            'Keep an eye on stock levels before customers reach checkout.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AdminMetric(
                  label: 'Out of stock',
                  value: '$outOfStockCount',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AdminMetric(label: 'Low stock', value: '$lowStockCount'),
              ),
            ],
          ),
          if (_inventoryService == null) ...[
            const SizedBox(height: 10),
            const _AdminReadOnlyNotice(
              message: 'Inventory adjustments are not available yet.',
            ),
          ],
          const SizedBox(height: 10),
          if (widget.products.isEmpty)
            const _AdminEmptyState(
              message: 'Inventory data will appear when the catalog finishes loading.',
            )
          else
            WireSurface(
              color: WireframeColors.paper,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final product in widget.products.take(20))
                    _AdminProductRow(
                      product: product,
                      onRestock: _inventoryService == null
                          ? null
                          : (variantId, quantity) =>
                                _restock(product.id, variantId, quantity),
                    ),
                ],
              ),
            ),
          if (_inventoryChanges.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SectionHeader(title: 'Recent stock changes'),
            const SizedBox(height: 6),
            WireSurface(
              color: WireframeColors.paper,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final change in _inventoryChanges)
                    ListTile(
                      dense: true,
                      title: Text(
                        '${change['variantId'] ?? 'Variant'}: ${change['delta'] is num && (change['delta'] as num) > 0 ? '+' : ''}${change['delta'] ?? 0}',
                      ),
                      subtitle: Text(
                        change['reason']?.toString() ?? 'Stock updated',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ];
      case _AdminModule.customers:
        return [
          const SectionHeader(title: 'Customers'),
          const SizedBox(height: 5),
          const Text(
            'A quick view of customers who have placed orders in Scentify.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          AdminMetric(label: 'Customers with orders', value: '$customerCount'),
          const SizedBox(height: 10),
          const _AdminReadOnlyNotice(
            message: 'Customer directory and profile management are not available yet.',
          ),
          const SizedBox(height: 10),
          WireSurface(
            color: WireframeColors.paper,
            padding: const EdgeInsets.all(14),
            child: Text(
              customerCount == 0
                  ? 'Customer activity will appear here after the first order.'
                  : 'Customer identities remain protected. Order activity is grouped by account ID for admin operations.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: WireframeColors.muted,
              ),
            ),
          ),
        ];
      case _AdminModule.notifications:
        return [
          const SectionHeader(title: 'Notifications'),
          const SizedBox(height: 5),
          const Text(
            'Review the operational notification channels used by the store.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          const _AdminStatusRow(
            icon: Icons.notifications_active_outlined,
            title: 'Order updates',
            detail: 'Requires a supported device and notification permission',
          ),
          const _AdminStatusRow(
            icon: Icons.payment_outlined,
            title: 'Payment review',
            detail: 'Visible in Orders to review',
          ),
          const _AdminStatusRow(
            icon: Icons.local_shipping_outlined,
            title: 'Fulfillment updates',
            detail: 'Sent by the deployed order-status backend trigger',
          ),
        ];
      case _AdminModule.settings:
        return [
          const SectionHeader(title: 'Store settings'),
          const SizedBox(height: 5),
          const Text(
            'Configuration and account information for this admin session.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          WireSurface(
            color: WireframeColors.paper,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Column(
              children: [
                _AdminInfoRow(label: 'Account', value: widget.profile.email),
                _AdminInfoRow(
                  label: 'Role',
                  value: widget.profile.isSuperAdmin ? 'Superadmin' : 'Admin',
                ),
                _AdminInfoRow(
                  label: 'Catalog products loaded',
                  value: '${widget.products.length}',
                ),
              ],
            ),
          ),
        ];
      case _AdminModule.access:
        return [
          const SectionHeader(title: 'Superadmin access'),
          const SizedBox(height: 5),
          const Text(
            'This protected module shows the role assigned to this account.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: WireframeColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          WireSurface(
            color: WireframeColors.darkSurface,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: WireframeColors.goldSoft,
                  size: 25,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Superadmin role active for ${widget.profile.email}.',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: WireframeColors.paper,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _AdminStatusRow(
            icon: Icons.lock_outline,
            title: 'Role-based access',
            detail: 'Superadmin claim verified during login',
          ),
          const _AdminStatusRow(
            icon: Icons.manage_accounts_outlined,
            title: 'Staff access tools',
            detail: 'Unavailable in this app version',
          ),
        ];
    }
  }

  String? _moduleReadOnlyNotice() => switch (_selectedModule) {
    _AdminModule.notifications =>
      'Campaign authoring and manual dispatch are not available yet.',
    _AdminModule.settings =>
      'Store configuration cannot be changed from this screen.',
    _AdminModule.access => 'Admin staff management is not available yet.',
    _ => null,
  };

  Widget _orderCard(Order order) {
    final nextStatus = _nextStatus(order.status);
    return _AdminOrderCard(
      key: ValueKey('admin-order-${order.id}'),
      order: order,
      actionLabel: nextStatus == null
          ? null
          : _actionLabel(order.status, nextStatus),
      isBusy: _activeOrderId == order.id,
      onAction: () => unawaited(_transition(order)),
    );
  }

  Future<void> _restock(
    String productId,
    String variantId,
    int quantity,
  ) async {
    final service = _inventoryService;
    if (service == null || _activeOrderId != null) return;
    setState(() => _error = null);
    try {
      await service.adjustStock(
        actor: widget.profile,
        productId: productId,
        variantId: variantId,
        delta: quantity,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Inventory restocked')));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AppException
              ? error.message
              : 'Unable to restock inventory.';
        });
      }
    }
  }

  Future<void> _transition(Order order) async {
    final nextStatus = _nextStatus(order.status);
    if (nextStatus == null || _activeOrderId != null) {
      return;
    }
    setState(() {
      _activeOrderId = order.id;
      _error = null;
    });
    try {
      await _orderService.transitionStatus(
        actor: widget.profile,
        orderId: order.id,
        nextStatus: nextStatus,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is AppException
              ? error.message
              : 'Unable to update this order.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _activeOrderId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _orders
        .where(
          (order) =>
              order.status == OrderStatus.pendingPayment ||
              order.status == OrderStatus.pendingConfirmation,
        )
        .length;
    final processingCount = _orders
        .where(
          (order) =>
              order.status == OrderStatus.confirmed ||
              order.status == OrderStatus.processing,
        )
        .length;
    final packedCount = _orders
        .where((order) => order.status == OrderStatus.packed)
        .length;
    final shippedCount = _orders
        .where((order) => order.status == OrderStatus.shipped)
        .length;
    final deliveredCount = _orders
        .where((order) => order.status == OrderStatus.delivered)
        .length;
    final totalSales = _orders
        .where(
          (order) =>
              order.status != OrderStatus.pendingPayment &&
              order.status != OrderStatus.pendingConfirmation,
        )
        .fold<int>(0, (total, order) => total + order.total.centavos);
    final customerCount = _orders.map((order) => order.userId).toSet().length;
    final outOfStockCount = widget.products
        .where((product) => product.stock <= 0)
        .length;
    final lowStockCount = widget.products
        .where((product) => product.stock > 0 && product.stock <= 5)
        .length;
    final displayName = widget.profile.displayName.trim().isEmpty
        ? widget.profile.email.split('@').first
        : widget.profile.displayName.trim();
    final moduleNotice = _moduleReadOnlyNotice();

    return WireframeShell(
      backgroundColor: const Color(0xFFF1E8DB),
      bottomBar: _AdminBottomNav(
        selectedModule: _selectedModule,
        onSelect: _selectModule,
      ),
      expandedNavigationRail: _AdminBottomNav(
        selectedModule: _selectedModule,
        onSelect: _selectModule,
        expanded: true,
      ),
      child: ListView(
        key: const Key('admin-page'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _AdminHero(
            title: _selectedModule == _AdminModule.access
                ? 'Superadmin access'
                : widget.profile.isSuperAdmin
                ? 'Superadmin dashboard'
                : 'Admin dashboard',
            displayName: displayName,
            isSuperAdmin: widget.profile.isSuperAdmin,
            pendingCount: pendingCount,
            onNotifications: () => _selectModule(_AdminModule.notifications),
            onAccess: widget.profile.isSuperAdmin
                ? () => _selectModule(_AdminModule.access)
                : null,
            onLogout: widget.onLogout,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AdminKpiCard(
                  label: 'Total orders',
                  value: '${_orders.length}',
                  icon: Icons.receipt_long_outlined,
                  accent: const Color(0xFFE8D7BF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AdminKpiCard(
                  label: 'Awaiting approval',
                  value: '$pendingCount',
                  icon: Icons.schedule_outlined,
                  accent: const Color(0xFFF1CF91),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AdminKpiCard(
                  label: 'Confirmed sales',
                  value: formatPrice(totalSales ~/ 100),
                  icon: Icons.auto_graph_outlined,
                  accent: WireframeColors.olive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AdminFulfillmentMonitor(
            pendingCount: pendingCount,
            processingCount: processingCount,
            packedCount: packedCount,
            shippedCount: shippedCount,
            deliveredCount: deliveredCount,
            onViewAll: () => _selectModule(_AdminModule.orders),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('admin-order-error'),
              style: const TextStyle(fontSize: 14, color: Color(0xFF9C2C2C)),
            ),
          ],
          const SizedBox(height: 20),
          if (_selectedModule == _AdminModule.overview) ...[
            const _AdminDesignSectionTitle(title: 'Management modules'),
            const SizedBox(height: 12),
            _moduleGrid(),
          ] else ...[
            _AdminModuleHeader(
              module: _selectedModule,
              onBack: () => _selectModule(_AdminModule.overview),
            ),
            const SizedBox(height: 10),
            _moduleTabs(),
            const SizedBox(height: 12),
            if (moduleNotice != null) ...[
              _AdminReadOnlyNotice(message: moduleNotice),
              const SizedBox(height: 10),
            ],
            ..._buildModuleContent(
              customerCount: customerCount,
              outOfStockCount: outOfStockCount,
              lowStockCount: lowStockCount,
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({
    required this.title,
    required this.displayName,
    required this.isSuperAdmin,
    required this.pendingCount,
    required this.onNotifications,
    required this.onAccess,
    required this.onLogout,
  });

  final String title;
  final String displayName;
  final bool isSuperAdmin;
  final int pendingCount;
  final VoidCallback onNotifications;
  final VoidCallback? onAccess;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 282,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              ScentifyAssets.superadminDashboardHero,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              semanticLabel: 'Luxury fragrance bottles in warm light',
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    WireframeColors.darkSurface.withValues(alpha: 0.98),
                    WireframeColors.darkSurface.withValues(alpha: 0.84),
                    WireframeColors.darkSurface.withValues(alpha: 0.18),
                  ],
                  stops: const [0, 0.48, 1],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Positioned(
              top: 15,
              left: 17,
              right: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ScentifyLogo(
                          size: 19,
                          color: WireframeColors.paper,
                        ),
                        const SizedBox(height: 5),
                        WireEyebrow(
                          'Operations lounge',
                          color: WireframeColors.goldSoft,
                        ),
                      ],
                    ),
                  ),
                  _AdminHeroIconButton(
                    key: const Key('admin-notifications'),
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    badge: pendingCount > 0,
                    onTap: onNotifications,
                  ),
                  const SizedBox(width: 5),
                  _AdminHeroIconButton(
                    key: const Key('admin-logout'),
                    icon: Icons.logout_rounded,
                    tooltip: 'Log out',
                    onTap: onLogout,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 76, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSuperAdmin
                            ? Icons.admin_panel_settings_outlined
                            : Icons.storefront_outlined,
                        size: 15,
                        color: WireframeColors.goldSoft,
                      ),
                      const SizedBox(width: 6),
                      WireEyebrow(
                        isSuperAdmin ? 'Elevated access' : 'Store operations',
                        color: WireframeColors.goldSoft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: _modernFontFamily,
                      fontSize: 24,
                      height: 1.04,
                      color: WireframeColors.paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      'Welcome back, $displayName. Keep every scent moving beautifully.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Color(0xFFE8DCCB),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    button: onAccess != null,
                    label: isSuperAdmin ? 'Open superadmin access' : null,
                    child: InkWell(
                      key: isSuperAdmin
                          ? const Key('admin-module-access')
                          : null,
                      onTap: onAccess,
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        alignment: Alignment.center,
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: WireframeColors.paper.withValues(alpha: 0.12),
                          border: Border.all(
                            color: WireframeColors.goldSoft.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          isSuperAdmin
                              ? 'SUPERADMIN · ELEVATED ROLE'
                              : 'ADMIN · ORDER OPERATIONS',
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.7,
                            color: WireframeColors.goldSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminHeroIconButton extends StatelessWidget {
  const _AdminHeroIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WireframeColors.ink.withValues(alpha: 0.34),
                border: Border.all(
                  color: WireframeColors.goldSoft.withValues(alpha: 0.7),
                ),
                shape: BoxShape.circle,
              ),
              child: Semantics(
                button: true,
                label: tooltip,
                child: Icon(icon, size: 18, color: WireframeColors.paper),
              ),
            ),
          ),
        ),
        if (badge)
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: WireframeColors.goldSoft,
                shape: BoxShape.circle,
                border: Border.all(color: WireframeColors.darkSurface),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminKpiCard extends StatelessWidget {
  const _AdminKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = WireframeColors.selected,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      padding: const EdgeInsets.fromLTRB(11, 11, 10, 10),
      decoration: BoxDecoration(
        color: WireframeColors.paper,
        border: Border.all(color: WireframeColors.border),
        borderRadius: BorderRadius.circular(19),
        boxShadow: [
          BoxShadow(
            color: WireframeColors.ink.withValues(alpha: 0.045),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: WireframeColors.tobacco),
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.1,
              color: WireframeColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 18,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFulfillmentMonitor extends StatelessWidget {
  const _AdminFulfillmentMonitor({
    required this.pendingCount,
    required this.processingCount,
    required this.packedCount,
    required this.shippedCount,
    required this.deliveredCount,
    required this.onViewAll,
  });

  final int pendingCount;
  final int processingCount;
  final int packedCount;
  final int shippedCount;
  final int deliveredCount;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('Pending', pendingCount, WireframeColors.gold),
      ('Processing', processingCount, WireframeColors.olive),
      ('Packed', packedCount, WireframeColors.olive),
      ('Shipped', shippedCount, WireframeColors.olive),
      ('Delivered', deliveredCount, WireframeColors.olive),
    ];

    return Container(
      key: const Key('admin-fulfillment-monitor'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: WireframeColors.paper,
        border: Border.all(color: WireframeColors.border),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: WireframeColors.ink.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: WireframeColors.olive,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  size: 21,
                  color: WireframeColors.paper,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fulfillment monitor',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Live order processing status',
                      style: TextStyle(
                        fontSize: 12,
                        color: WireframeColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: WireframeColors.tobacco,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  minimumSize: const Size(48, 48),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 17),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 19),
          SizedBox(
            height: 91,
            child: Stack(
              children: [
                Positioned(
                  top: 12,
                  left: 19,
                  right: 19,
                  child: Row(
                    children: [
                      for (var index = 0; index < stages.length - 1; index++)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: index == 0
                                ? WireframeColors.gold
                                : WireframeColors.olive.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final stage in stages)
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 25,
                              height: 25,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: stage.$3,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: WireframeColors.paper,
                                  width: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              stage.$1,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                color: WireframeColors.muted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${stage.$2}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDesignSectionTitle extends StatelessWidget {
  const _AdminDesignSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: _modernFontFamily,
            fontSize: 24,
            height: 1.08,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 9),
        Container(
          width: 38,
          height: 3,
          decoration: BoxDecoration(
            color: WireframeColors.gold,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }
}

class _AdminModuleCard extends StatelessWidget {
  const _AdminModuleCard({
    super.key,
    required this.module,
    required this.onTap,
  });

  final _AdminModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lightTile = module != _AdminModule.access;
    return Semantics(
      button: true,
      label: '${module.label} module',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: module.tileTint,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  module.imageAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        module.tileTint.withValues(
                          alpha: lightTile ? 0.18 : 0.4,
                        ),
                        module.tileTint.withValues(
                          alpha: lightTile ? 0.86 : 0.95,
                        ),
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 39,
                        height: 39,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: lightTile
                              ? WireframeColors.paper.withValues(alpha: 0.72)
                              : WireframeColors.ink.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: WireframeColors.goldSoft.withValues(
                              alpha: lightTile ? 0.4 : 0.8,
                            ),
                          ),
                        ),
                        child: Icon(
                          module.icon,
                          size: 19,
                          color: lightTile
                              ? WireframeColors.tobacco
                              : WireframeColors.paper,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              module.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: lightTile
                                    ? WireframeColors.ink
                                    : WireframeColors.paper,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: lightTile
                                ? WireframeColors.ink
                                : WireframeColors.paper,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminModuleHeader extends StatelessWidget {
  const _AdminModuleHeader({required this.module, required this.onBack});

  final _AdminModule module;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Back to dashboard',
          icon: const Icon(Icons.arrow_back, size: 19),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        ),
        const SizedBox(width: 4),
        Icon(module.icon, size: 20, color: WireframeColors.brassInk),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            module.label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({
    required this.selectedModule,
    required this.onSelect,
    this.expanded = false,
  });

  final _AdminModule selectedModule;
  final ValueChanged<_AdminModule> onSelect;
  final bool expanded;

  static const _items = [
    (_AdminModule.overview, Icons.dashboard_outlined, 'Dashboard'),
    (_AdminModule.orders, Icons.receipt_long_outlined, 'Orders'),
    (_AdminModule.products, Icons.inventory_2_outlined, 'Products'),
    (_AdminModule.customers, Icons.people_outline, 'Customers'),
    (_AdminModule.settings, Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    final selectedIndex = _items.indexWhere(
      (item) => item.$1 == selectedModule,
    );
    final effectiveIndex = selectedIndex < 0 ? 0 : selectedIndex;

    if (expanded) {
      return NavigationRail(
        backgroundColor: colors.paper,
        indicatorColor: colors.selected,
        minWidth: 84,
        groupAlignment: -0.8,
        labelType: NavigationRailLabelType.all,
        scrollable: true,
        selectedIndex: effectiveIndex,
        onDestinationSelected: (index) => onSelect(_items[index].$1),
        destinations: [
          for (final item in _items)
            NavigationRailDestination(
              icon: Icon(item.$2),
              label: Text(item.$3),
            ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: NavigationBar(
        backgroundColor: colors.paper,
        indicatorColor: colors.selected,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: effectiveIndex,
        onDestinationSelected: (index) => onSelect(_items[index].$1),
        destinations: [
          for (final item in _items)
            NavigationDestination(
              icon: Icon(item.$2),
              selectedIcon: Icon(item.$2),
              label: item.$3,
              tooltip: item.$3,
            ),
        ],
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return WireSurface(
      color: WireframeColors.paper,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            size: 24,
            color: WireframeColors.brassInk,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: WireframeColors.muted),
          ),
        ],
      ),
    );
  }
}

class _AdminProductRow extends StatelessWidget {
  const _AdminProductRow({required this.product, this.onRestock});

  final Product product;
  final Future<void> Function(String variantId, int quantity)? onRestock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WireframeColors.border)),
      ),
      child: Row(
        children: [
          PlaceholderImage(
            width: 42,
            height: 48,
            radius: 9,
            tone: productTone(product),
            backgroundColor: WireframeColors.field,
            assetPath: productImageAsset(product),
            imageUrl: productImageUrl(product),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.brand,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${product.stock} in stock',
                style: TextStyle(
                  fontSize: 12,
                  color: product.stock <= 5
                      ? const Color(0xFF9C2C2C)
                      : WireframeColors.muted,
                ),
              ),
              for (final entry in product.stockByVolume.entries)
                TextButton(
                  key: ValueKey('adjust-stock-${product.id}-${entry.key}'),
                  onPressed: onRestock == null
                      ? null
                      : () =>
                            _showRestockDialog(context, entry.key, entry.value),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Text('Adjust ${entry.key}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showRestockDialog(
    BuildContext context,
    String variantIdOrLabel,
    int currentStock,
  ) async {
    final quantityController = TextEditingController(text: '10');
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adjust $variantIdOrLabel'),
        content: TextField(
          controller: quantityController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Stock change (+/-)',
            helperText: 'Current stock: $currentStock',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(quantityController.text.trim());
              if (value != null && value != 0) Navigator.pop(context, value);
            },
            child: const Text('Apply adjustment'),
          ),
        ],
      ),
    );
    quantityController.dispose();
    if (quantity != null) {
      final variantId =
          product.variantIdsByVolume[variantIdOrLabel] ?? variantIdOrLabel;
      await onRestock?.call(variantId, quantity);
    }
  }
}

class _AdminReadOnlyNotice extends StatelessWidget {
  const _AdminReadOnlyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('admin-read-only-notice'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFECE7DB),
        border: Border.all(color: WireframeColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: WireframeColors.tobacco,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'READ-ONLY / NOT AVAILABLE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                    color: WireframeColors.tobacco,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: WireframeColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminStatusRow extends StatelessWidget {
  const _AdminStatusRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: WireframeColors.paper,
          border: Border.all(color: WireframeColors.border),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: WireframeColors.ink.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WireframeColors.selected,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: WireframeColors.brassInk),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.check_circle_outline,
              size: 17,
              color: WireframeColors.olive,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminInfoRow extends StatelessWidget {
  const _AdminInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WireframeColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: WireframeColors.muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrdersSummary extends StatelessWidget {
  const _AdminOrdersSummary({
    required this.pendingOrders,
    required this.activeOrders,
    required this.completedOrders,
  });

  final int pendingOrders;
  final int activeOrders;
  final int completedOrders;

  @override
  Widget build(BuildContext context) {
    return WireSurface(
      color: WireframeColors.darkSurface,
      border: false,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: WireEyebrow(
                  'Fulfillment monitor',
                  color: WireframeColors.goldSoft,
                ),
              ),
              Text(
                '$pendingOrders pending review',
                style: const TextStyle(
                  fontSize: 12,
                  color: WireframeColors.goldSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Keep payment checks and delivery movement visible at a glance.',
            style: TextStyle(fontSize: 14, color: WireframeColors.paper),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AdminMonitorMetric(
                  label: 'Review',
                  value: '$pendingOrders',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _AdminMonitorMetric(
                  label: 'In progress',
                  value: '$activeOrders',
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _AdminMonitorMetric(
                  label: 'Delivered',
                  value: '$completedOrders',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminMonitorMetric extends StatelessWidget {
  const _AdminMonitorMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WireframeColors.tobacco,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                color: WireframeColors.paper,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: WireframeColors.paper,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    super.key,
    required this.order,
    required this.actionLabel,
    required this.isBusy,
    required this.onAction,
  });

  final Order order;
  final String? actionLabel;
  final bool isBusy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final statuses = _orderProgressStatuses(order);
    final activeIndex = statuses.indexOf(order.status);
    final itemSummary = order.items
        .map((item) => '${item.productName} ×${item.quantity}')
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WireSurface(
        key: ValueKey('admin-order-card-${order.id}'),
        color: WireframeColors.paper,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '#${order.id}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _orderStatusColor(order.status),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _orderStatusLabel(order.status),
                    style: const TextStyle(
                      fontSize: 12,
                      color: WireframeColors.paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              itemSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var index = 0; index < statuses.length; index++) ...[
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= activeIndex
                            ? _orderStatusColor(order.status)
                            : WireframeColors.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  if (index < statuses.length - 1) const SizedBox(width: 3),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${activeIndex + 1} of ${statuses.length} fulfillment stages',
              style: const TextStyle(
                fontSize: 12,
                color: WireframeColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Customer ${order.userId} · ${formatPrice(order.total.centavos ~/ 100)}',
              style: const TextStyle(
                fontSize: 12,
                color: WireframeColors.muted,
              ),
            ),
            if (order.status == OrderStatus.pendingConfirmation)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Customer totals are estimates. Verify catalog prices and stock before confirming.',
                  style: TextStyle(
                    fontSize: 12,
                    color: WireframeColors.tobacco,
                  ),
                ),
              ),
            if (order.paymentReference != null) ...[
              const SizedBox(height: 3),
              Text(
                'Payment ref: ${order.paymentReference}',
                style: const TextStyle(
                  fontSize: 12,
                  color: WireframeColors.muted,
                ),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 10),
              WireButton(
                key: ValueKey('admin-action-${order.id}'),
                label: isBusy ? 'Updating...' : actionLabel!,
                onPressed: isBusy ? null : onAction,
                height: 40,
                radius: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminMetric extends StatelessWidget {
  const AdminMetric({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: WireframeColors.paper,
        border: Border.all(color: WireframeColors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: WireframeColors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Container(
              width: 31,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: WireframeColors.selected,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: WireframeColors.tobacco),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WireframeColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
