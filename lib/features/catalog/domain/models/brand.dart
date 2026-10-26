class Brand {
  Brand({required this.id, required this.name, required this.slug});

  final String id;
  final String name;
  final String slug;

  Brand copyWith({String? id, String? name, String? slug}) {
    return Brand(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
    );
  }
}
