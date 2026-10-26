import 'package:scentify/features/checkout/domain/models/shipping_address.dart';

class SavedAddress {
  SavedAddress({
    required this.id,
    required this.address,
    this.label = 'Home',
    this.isDefault = true,
    this.latitude,
    this.longitude,
    this.placeId,
    this.addressSource = 'manual',
    required this.createdAt,
    required this.updatedAt,
  }) {
    if (id.isEmpty || !const {'Home', 'Work', 'Other'}.contains(label)) {
      throw ArgumentError('Saved address id or label is invalid.');
    }
    if (!const {'manual', 'autocomplete'}.contains(addressSource)) {
      throw ArgumentError.value(addressSource, 'addressSource');
    }
    if ((latitude == null) != (longitude == null) ||
        (latitude != null && (latitude! < -90 || latitude! > 90)) ||
        (longitude != null && (longitude! < -180 || longitude! > 180))) {
      throw ArgumentError('Saved address coordinates are invalid.');
    }
  }

  final String id;
  final ShippingAddress address;
  final String label;
  final bool isDefault;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  final String addressSource;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavedAddress copyWith({
    ShippingAddress? address,
    String? label,
    bool? isDefault,
    double? latitude,
    double? longitude,
    String? placeId,
    String? addressSource,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SavedAddress(
      id: id,
      address: address ?? this.address,
      label: label ?? this.label,
      isDefault: isDefault ?? this.isDefault,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeId: placeId ?? this.placeId,
      addressSource: addressSource ?? this.addressSource,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
