import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scentify/features/checkout/domain/models/saved_address.dart';
import 'package:scentify/features/checkout/domain/models/shipping_address.dart';
import 'package:scentify/features/checkout/domain/repositories/saved_address_repository.dart';

class FirestoreSavedAddressRepository implements SavedAddressRepository {
  FirestoreSavedAddressRepository({
    FirebaseFirestore? firestore,
    String usersCollectionName = 'users',
  }) : _users = (firestore ?? FirebaseFirestore.instance).collection(
         usersCollectionName,
       );

  static const primaryAddressId = 'primary';

  final CollectionReference<Map<String, dynamic>> _users;

  DocumentReference<Map<String, dynamic>> _address(String userId) =>
      _users.doc(userId).collection('addresses').doc(primaryAddressId);

  @override
  Future<SavedAddress?> findForUser(String userId) async {
    final document = await _address(userId).get();
    return _decode(document);
  }

  @override
  Stream<SavedAddress?> watchForUser(String userId) {
    return _address(userId).snapshots().map(_decode);
  }

  @override
  Future<void> saveForUser(String userId, SavedAddress address) async {
    final reference = _address(userId);
    final current = await reference.get();
    final createdAt = current.exists
        ? _date(current.data()?['createdAt']) ?? address.createdAt
        : address.createdAt;
    final value = address.copyWith(createdAt: createdAt);
    await reference.set({
      'fullName': value.address.fullName,
      'phoneNumber': value.address.phoneNumber,
      'addressLine1': value.address.addressLine1,
      'barangay': value.address.barangay,
      'city': value.address.city,
      'province': value.address.province,
      'postalCode': value.address.postalCode,
      'label': value.label,
      'isDefault': value.isDefault,
      'latitude': value.latitude,
      'longitude': value.longitude,
      'placeId': value.placeId,
      'addressSource': value.addressSource,
      'notes': value.address.notes,
      'createdAt': value.createdAt,
      'updatedAt': value.updatedAt,
    });
  }

  @override
  Future<void> deleteForUser(String userId) => _address(userId).delete();

  SavedAddress? _decode(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (!document.exists || data == null) return null;
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    return SavedAddress(
      id: document.id,
      address: ShippingAddress(
        fullName: _string(data['fullName'], 'fullName'),
        phoneNumber: _string(data['phoneNumber'], 'phoneNumber'),
        addressLine1: _string(data['addressLine1'], 'addressLine1'),
        barangay: _string(data['barangay'], 'barangay'),
        city: _string(data['city'], 'city'),
        province: _string(data['province'], 'province'),
        postalCode: _string(data['postalCode'], 'postalCode'),
        notes: _optionalString(data['notes']),
      ),
      label: data['label'] is String ? data['label'] as String : 'Home',
      isDefault: data['isDefault'] == true,
      latitude: latitude is num ? latitude.toDouble() : null,
      longitude: longitude is num ? longitude.toDouble() : null,
      placeId: data['placeId'] is String ? data['placeId'] as String : null,
      addressSource: data['addressSource'] is String
          ? data['addressSource'] as String
          : 'manual',
      createdAt: _date(data['createdAt']) ?? DateTime.now(),
      updatedAt: _date(data['updatedAt']) ?? DateTime.now(),
    );
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    return null;
  }

  String _string(Object? value, String field) {
    if (value is String) return value;
    throw FormatException('Expected $field to be a string.');
  }

  String _optionalString(Object? value) => value is String ? value : '';
}
