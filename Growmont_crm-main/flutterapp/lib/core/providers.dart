import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../features/auth/auth_provider.dart';
import 'firebase/firestore_service.dart';
import 'local/crm_repository.dart';
import 'local/startup_sync.dart';
import 'local/sync_engine.dart';
import 'storage/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});

/// Declared type stays `Provider<FirestoreService>` — only the concrete
/// instance changes (to CrmRepository, its local-first subclass) so every
/// existing call site keeps compiling and behaving exactly as before for
/// every member CrmRepository doesn't override.
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final authUser = ref.watch(authProvider).user;
  return CrmRepository(
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

final firestoreProvider = Provider<FirebaseFirestore?>((ref) {
  try {
    return FirebaseFirestore.instance;
  } catch (_) {
    return null;
  }
});

/// Starts/stops SyncEngine as the signed-in user changes. Must be watched
/// somewhere alive for the app's lifetime (see GrowmontApp.build in
/// main.dart) for the engine to actually run — a Provider is only built
/// while something is watching it.
///
/// Declared as [Provider], not [ChangeNotifierProvider]: [SyncEngine.instance]
/// is a process-lifetime singleton. [ChangeNotifierProvider] automatically
/// calls dispose() when recomputed or torn down, which permanently breaks
/// a singleton ChangeNotifier.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final uid = ref.watch(authProvider.select((s) => s.user?.id));
  final engine = SyncEngine.instance;
  if (uid == null) {
    unawaited(engine.stop());
  } else {
    final fs = ref.watch(firestoreProvider);
    if (fs != null) {
      StartupSync.runInBackground(fs, uid);
    }
  }
  return engine;
});
