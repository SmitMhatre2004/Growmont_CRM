import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'firebase_options.dart';
import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/storage/app_paths.dart';
import 'core/theme/app_theme.dart';
import 'core/updater/update_notifier.dart';
import 'features/auth/auth_provider.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Decode the splash mark alongside Firebase init rather than after it, so
  // the first Flutter frame paints it immediately. The native launch screen
  // shows the same mark in the same spot; if Flutter had to decode it first
  // there would be a blank white frame between the two.
  final splashMarkReady = _precacheSplashMark();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Enable offline persistence for Firestore
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firebase initialization note: $e');
  }

  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    // Resolve the canonical, per-user app-data directory (via path_provider
    // — NOT the install folder, see AppPaths) before anything touches the
    // local database.
    final appDataDir = await AppPaths.directory;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Defense-in-depth: sqflite_common_ffi's getDatabasesPath() otherwise
    // defaults to Directory.current (the install folder). This neutralizes
    // that default for any code that still calls getDatabasesPath()
    // directly, on top of LocalDatabase resolving its own path explicitly
    // via AppPaths.
    await databaseFactory.setDatabasesPath(appDataDir.path);
  }

  if (!kIsWeb && Platform.isWindows) {
    // Deliberately not awaited — startup must never block on a network
    // call. The Profile -> System tab's UpdateCard is the notification
    // surface; this just warms the check so it's ready when opened.
    UpdateNotifier.instance.checkForUpdate();
  }

  await splashMarkReady.timeout(
    const Duration(milliseconds: 300),
    onTimeout: () {},
  );

  runApp(const ProviderScope(child: GrowmontApp()));
}

/// Resolves once the splash mark is decoded into the image cache. Never
/// throws: a missing/broken asset just means the splash paints it a frame
/// late, which must not block startup.
Future<void> _precacheSplashMark() {
  final completer = Completer<void>();
  final stream = const AssetImage(
    kSplashMarkAsset,
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void done() {
    stream.removeListener(listener);
    if (!completer.isCompleted) completer.complete();
  }

  listener = ImageStreamListener(
    (_, _) => done(),
    onError: (_, _) => done(),
  );
  stream.addListener(listener);
  return completer.future;
}

class GrowmontApp extends ConsumerWidget {
  const GrowmontApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authProvider);
    // Keeps syncEngineProvider alive for the app's lifetime so SyncEngine
    // starts/stops as the signed-in user changes — see providers.dart.
    ref.watch(syncEngineProvider);

    return MaterialApp.router(
      title: 'Growmont CRM',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return SplashGate(
          isAuthenticated: auth.isAuthenticated,
          child: auth.isLoading
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
