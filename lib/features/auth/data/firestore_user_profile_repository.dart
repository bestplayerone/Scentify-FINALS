import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scentify/features/auth/domain/models/user_profile.dart';
import 'package:scentify/features/auth/domain/repositories/user_profile_repository.dart';

class FirestoreUserProfileRepository implements UserProfileRepository {
  FirestoreUserProfileRepository({
    FirebaseFirestore? firestore,
    String collectionName = 'users',
  }) : _collection = (firestore ?? FirebaseFirestore.instance).collection(
         collectionName,
       );

  final CollectionReference<Map<String, dynamic>> _collection;

  @override
  Future<UserProfile?> findById(String userId) async {
    final document = await _collection.doc(userId).get();
    return _decode(document);
  }

  @override
  Stream<UserProfile?> watch(String userId) {
    return _collection.doc(userId).snapshots().map(_decode);
  }

  @override
  Future<void> save(UserProfile profile) {
    return _collection.doc(profile.id).set({
      'email': profile.email,
      'displayName': profile.displayName,
      'role': profile.role.wireValue,
      'createdAt': profile.createdAt,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  UserProfile? _decode(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    if (!document.exists || data == null) {
      return null;
    }

    final roleValue = data['role'];
    final role = UserRole.values.firstWhere(
      (candidate) => candidate.wireValue == roleValue,
      orElse: () => UserRole.customer,
    );
    final createdAt = _dateValue(data['createdAt']) ?? DateTime.now();

    return UserProfile(
      id: document.id,
      email: data['email'] is String ? data['email'] as String : '',
      displayName: data['displayName'] is String
          ? data['displayName'] as String
          : '',
      role: role,
      createdAt: createdAt,
    );
  }

  DateTime? _dateValue(Object? value) {
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }
}
