import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../features/auth/auth_provider.dart';
import 'firebase/firestore_service.dart';
import 'local/startup_sync.dart';
import 'local/sync_engine.dart';
import 'storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final authUser = ref.watch(authProvider).user;
  return FirestoreService(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    functions: FirebaseFunctions.instance,
    storage: FirebaseStorage.instance,
    devUid: authUser?.id,
  );
});

/// Backwards compatibility provider for screens calling apiServiceProvider
final apiServiceProvider = Provider<FirestoreService>((ref) {
  return ref.watch(firestoreServiceProvider);
});

/// Starts/stops SyncEngine as the signed-in user changes. Must be watched
/// somewhere alive for the app's lifetime (see GrowmontApp.build in
/// main.dart) for the engine to actually run — a Provider is only built
/// while something is watching it.
final syncEngineProvider = ChangeNotifierProvider<SyncEngine>((ref) {
  final uid = ref.watch(authProvider).user?.id;
  final engine = SyncEngine.instance;
  if (uid == null) {
    unawaited(engine.stop());
  } else {
    StartupSync.runInBackground(FirebaseFirestore.instance, uid);
  }
  return engine;
});
