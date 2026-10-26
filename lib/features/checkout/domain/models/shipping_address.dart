import 'package:scentify/core/errors/app_exception.dart';

class ShippingAddress {
  ShippingAddress({
    required this.fullName,
    required this.phoneNumber,
    required this.addressLine1,
    required this.barangay,
    required this.city,
    required String province,
    required this.postalCode,
    this.notes = '',
  }) : province = normalizePhilippineRegion(province, city) {
    final values = [
      fullName,
      phoneNumber,
      addressLine1,
      barangay,
      city,
      this.province,
      postalCode,
    ];
    if (values.any((value) => value.trim().isEmpty)) {
      throw const ValidationException(
        'All required address fields are needed.',
      );
    }
    if (!RegExp(r'^\d{4}$').hasMatch(postalCode)) {
      throw const ValidationException('Postal code must contain four digits.');
    }
  }

  final String fullName;
  final String phoneNumber;
  final String addressLine1;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;
  final String notes;

  ShippingAddress copyWith({
    String? fullName,
    String? phoneNumber,
    String? addressLine1,
    String? barangay,
    String? city,
    String? province,
    String? postalCode,
    String? notes,
  }) {
    return ShippingAddress(
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      addressLine1: addressLine1 ?? this.addressLine1,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      province: province ?? this.province,
      postalCode: postalCode ?? this.postalCode,
      notes: notes ?? this.notes,
    );
  }
}

String normalizePhilippineRegion(String region, String city) {
  if (_normalizeAreaName(region) == 'manila' &&
      _ncrCityNames.contains(_normalizeAreaName(city))) {
    return 'National Capital Region';
  }
  return region.trim();
}

String _normalizeAreaName(String value) => value
    .toLowerCase()
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'\b(city|municipality)\s+of\b'), '')
    .replaceAll(RegExp(r'\b(city|municipality)\b'), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

const _ncrCityNames = {
  'caloocan',
  'las pinas',
  'makati',
  'malabon',
  'mandaluyong',
  'manila',
  'marikina',
  'muntinlupa',
  'navotas',
  'paranaque',
  'pasay',
  'pasig',
  'pateros',
  'quezon',
  'san juan',
  'taguig',
  'valenzuela',
};
