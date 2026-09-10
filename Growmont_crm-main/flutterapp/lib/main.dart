import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'firebase_options.dart';
import 'core/router/app_router.dart';
import 'core/storage/app_paths.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const ProviderScope(child: GrowmontApp()));
}

class GrowmontApp extends ConsumerWidget {
  const GrowmontApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final auth = ref.watch(authProvider);

    return MaterialApp.router(
      title: 'Growmont Employee Portal',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
