// The Firebase SDK's test doubles are sealed in the current package version;
// this file intentionally keeps its minimal fakes until they can be replaced
// with a supported fake backend.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:test/test.dart';
import 'package:scentify/features/wishlist/data/firestore_wishlist_repository.dart';
import 'package:scentify/features/wishlist/domain/services/wishlist_service.dart';

void main() {
  test(
    'wishlist save rejects product IDs outside the Firestore ID syntax',
    () async {
      final firestore = _FakeFirestore();
      final repository = FirestoreWishlistRepository(firestore: firestore);

      for (final productId in ['', 'bad/id', List.filled(129, 'a').join()]) {
        await expectLater(
          repository.save('customer-1', {productId}),
          throwsA(isA<FormatException>()),
        );
      }

      expect(firestore.collectionReference.document.writes, isEmpty);
      await repository.save('customer-1', {'scent-1'});
      expect(firestore.collectionReference.document.writes.single, {
        'productIds': ['scent-1'],
      });
    },
  );

  test('wishlist toggle drops invalid legacy values before saving', () async {
    final firestore = _FakeFirestore(
      data: {
        'productIds': ['scent-1', 'bad/id', 42, ''],
      },
    );
    final repository = FirestoreWishlistRepository(firestore: firestore);
    final service = WishlistService(repository);

    expect(await service.toggle(userId: 'customer-1', productId: 'scent-2'), {
      'scent-1',
      'scent-2',
    });
    expect(firestore.collectionReference.document.writes.single, {
      'productIds': ['scent-1', 'scent-2'],
    });
  });

  test(
    'wishlist save rejects more than 100 product IDs before writing',
    () async {
      final firestore = _FakeFirestore();
      final repository = FirestoreWishlistRepository(firestore: firestore);

      await expectLater(
        repository.save(
          'customer-1',
          List.generate(101, (index) => 'scent-$index').toSet(),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(firestore.collectionReference.document.writes, isEmpty);
    },
  );
}

class _FakeFirestore implements FirebaseFirestore {
  _FakeFirestore({Map<String, dynamic>? data})
    : collectionReference = _FakeCollectionReference(data: data);

  final _FakeCollectionReference collectionReference;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return collectionReference;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCollectionReference
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionReference({Map<String, dynamic>? data})
    : document = _FakeDocumentReference(data);

  final _FakeDocumentReference document;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => document;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocumentSnapshot(this._data);

  final Map<String, dynamic>? _data;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDocumentReference
    implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentReference(this._data);

  final Map<String, dynamic>? _data;
  final writes = <Map<String, dynamic>>[];

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _FakeDocumentSnapshot(_data);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    writes.add(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
