import 'package:scentify/core/models/money.dart';

enum GenderPreference { men, women, unisex }

enum FragranceFamily {
  citrus,
  floral,
  woody,
  oriental,
  fresh,
  gourmand,
  chypre,
  aquatic,
  leather,
  aromatic,
}

enum ScentVibe {
  clean,
  romantic,
  bold,
  elegant,
  playful,
  calming,
  mysterious,
  energetic,
}

enum Occasion { everyday, office, dateNight, formal, travel, evening, special }

enum Concentration { edt, edp, parfum, extrait, cologne }

extension GenderPreferenceWireValue on GenderPreference {
  String get wireValue => switch (this) {
    GenderPreference.men => 'men',
    GenderPreference.women => 'women',
    GenderPreference.unisex => 'unisex',
  };
}

extension FragranceFamilyWireValue on FragranceFamily {
  String get wireValue => name;
}

extension ScentVibeWireValue on ScentVibe {
  String get wireValue => name;
}

extension OccasionWireValue on Occasion {
  String get wireValue => name;
}

extension ConcentrationWireValue on Concentration {
  String get wireValue => name;
}

class PerfumeVariant {
  PerfumeVariant({
    required this.id,
    required this.label,
    required this.volumeMl,
    required this.price,
    required this.stock,
  }) : assert(volumeMl > 0),
       assert(stock >= 0);

  final String id;
  final String label;
  final int volumeMl;
  final Money price;
  final int stock;

  bool get isAvailable => stock > 0;

  PerfumeVariant copyWith({
    String? id,
    String? label,
    int? volumeMl,
    Money? price,
    int? stock,
  }) {
    return PerfumeVariant(
      id: id ?? this.id,
      label: label ?? this.label,
      volumeMl: volumeMl ?? this.volumeMl,
      price: price ?? this.price,
      stock: stock ?? this.stock,
    );
  }
}

class Perfume {
  Perfume({
    required this.id,
    required this.brandId,
    required this.brandName,
    required this.name,
    required this.description,
    required this.gender,
    required this.family,
    required this.concentration,
    required this.occasions,
    required this.vibes,
    required this.topNotes,
    required this.heartNotes,
    required this.baseNotes,
    required this.variants,
    this.imageUrls = const [],
    this.tags = const [],
    this.authenticityNote = '',
    this.isPublished = true,
  });

  final String id;
  final String brandId;
  final String brandName;
  final String name;
  final String description;
  final GenderPreference gender;
  final FragranceFamily family;
  final Concentration concentration;
  final List<Occasion> occasions;
  final List<ScentVibe> vibes;
  final List<String> topNotes;
  final List<String> heartNotes;
  final List<String> baseNotes;
  final List<PerfumeVariant> variants;
  final List<String> imageUrls;
  final List<String> tags;
  final String authenticityNote;
  final bool isPublished;

  PerfumeVariant? variantById(String variantId) {
    for (final variant in variants) {
      if (variant.id == variantId) {
        return variant;
      }
    }
    return null;
  }

  bool get hasAvailableStock => variants.any((variant) => variant.isAvailable);

  Money get lowestPrice {
    if (variants.isEmpty) {
      return Money(0);
    }
    return variants
        .map((variant) => variant.price)
        .reduce((current, next) => current < next ? current : next);
  }

  Perfume copyWith({
    String? id,
    String? brandId,
    String? brandName,
    String? name,
    String? description,
    GenderPreference? gender,
    FragranceFamily? family,
    Concentration? concentration,
    List<Occasion>? occasions,
    List<ScentVibe>? vibes,
    List<String>? topNotes,
    List<String>? heartNotes,
    List<String>? baseNotes,
    List<PerfumeVariant>? variants,
    List<String>? imageUrls,
    List<String>? tags,
    String? authenticityNote,
    bool? isPublished,
  }) {
    return Perfume(
      id: id ?? this.id,
      brandId: brandId ?? this.brandId,
      brandName: brandName ?? this.brandName,
      name: name ?? this.name,
      description: description ?? this.description,
      gender: gender ?? this.gender,
      family: family ?? this.family,
      concentration: concentration ?? this.concentration,
      occasions: occasions ?? this.occasions,
      vibes: vibes ?? this.vibes,
      topNotes: topNotes ?? this.topNotes,
      heartNotes: heartNotes ?? this.heartNotes,
      baseNotes: baseNotes ?? this.baseNotes,
      variants: variants ?? this.variants,
      imageUrls: imageUrls ?? this.imageUrls,
      tags: tags ?? this.tags,
      authenticityNote: authenticityNote ?? this.authenticityNote,
      isPublished: isPublished ?? this.isPublished,
    );
  }
}
