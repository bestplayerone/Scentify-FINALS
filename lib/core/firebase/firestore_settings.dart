import 'package:cloud_firestore/cloud_firestore.dart';

/// Finite local cache target for Firestore's built-in mobile persistence.
///
/// Android and Apple already enable persistence by default. This helper only
/// sets a bounded LRU cleanup threshold and must be called immediately after
/// Firebase initialization, before any repository performs a Firestore read.
const scentifyFirestoreCacheSizeBytes = 100 * 1024 * 1024;

final _configuredFirestore = Expando<bool>('scentify.firestore.configured');

void configureScentifyFirestore({
  FirebaseFirestore? firestore,
  int cacheSizeBytes = scentifyFirestoreCacheSizeBytes,
}) {
  if (cacheSizeBytes <= 0) {
    throw ArgumentError.value(
      cacheSizeBytes,
      'cacheSizeBytes',
      'The Firestore cache target must be positive.',
    );
  }
  final database = firestore ?? FirebaseFirestore.instance;
  if (_configuredFirestore[database] == true) {
    return;
  }
  database.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: cacheSizeBytes,
  );
  _configuredFirestore[database] = true;
}
