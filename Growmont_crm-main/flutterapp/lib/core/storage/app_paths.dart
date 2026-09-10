// lib/core/storage/app_paths.dart
//
// Centralized resolver for where Growmont CRM's own persistent local data
// lives on desktop (Windows/Linux/macOS), plus a diagnostic snapshot helper
// (AppStorageInfo) for the Profile screen's "Data Storage Location" card.
//
// ── The problem ──────────────────────────────────────────────────────────
//
//   sqflite_common_ffi's getDatabasesPath() has what its own maintainer
//   calls a "lame implementation" on desktop: unless overridden, it
//   defaults to Directory.current — which, for a normally-launched .exe,
//   IS the install folder. Any file written there is lost the moment the
//   app is replaced or updated in place.
//
// ── The fix ──────────────────────────────────────────────────────────────
//
//   Resolve a stable, per-user, OS-correct directory via path_provider's
//   getApplicationSupportDirectory() instead, cache it (so we only hit the
//   platform channel once), and expose helpers so call sites don't reinvent
//   path‑joining and directory creation.
//
//   Typical resolved locations (subject to the app's own bundle identity):
//     Windows: C:\Users\<user>\AppData\Roaming\…\GrowmontCRM
//     Linux:   ~/.local/share/growmont_crm/GrowmontCRM
//     macOS:   ~/Library/Application Support/growmont_crm/GrowmontCRM
//
// ── Diagnostic snapshot ─────────────────────────────────────────────────
//
//   AppPaths.resolveStorageInfo() returns an AppStorageInfo object that
//   contains the exact file path for growmont.db, its size, modification
//   date, how many local backups exist, and the executable's location.
//   This is used by the DataLocationCard to show the full, copyable paths.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─── Stat info for a single file ──────────────────────────────────────────

class AppFileInfo {
  const AppFileInfo({
    required this.path,
    required this.exists,
    this.sizeBytes,
    this.lastModified,
  });

  final String path;
  final bool exists;
  final int? sizeBytes;
  final DateTime? lastModified;

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

// ─── Snapshot of every storage location Growmont CRM currently touches ───

class AppStorageInfo {
  const AppStorageInfo({
    required this.databaseDirectory,
    required this.database,
    required this.executableDirectory,
    required this.backupCount,
  });

  /// The folder where Growmont CRM's local database lives (from
  /// AppPaths.directory, i.e. the fixed per-user application support
  /// folder).
  final String databaseDirectory;

  final AppFileInfo database;

  /// Folder growmont_crm.exe is running from — never where user data
  /// belongs.
  final String executableDirectory;

  /// Number of growmont.backup.*.db files currently kept alongside
  /// growmont.db.
  final int backupCount;

  String toDiagnosticText() => '''
Growmont CRM Storage Diagnostic
--------------------------------
Database folder : $databaseDirectory
Database file    : ${database.path}
                    (${database.exists ? "${database.sizeLabel}, updated ${database.lastModified}" : "not created yet"})
Local backups     : $backupCount kept
Program folder   : $executableDirectory
''';
}

// ─── Centralised path resolver ────────────────────────────────────────────

class AppPaths {
  AppPaths._();

  /// Fixed subfolder name under the platform's application-support directory.
  static const String _appFolderName = 'GrowmontCRM';

  static Directory? _cachedDir;
  static Future<Directory>? _resolving;

  /// The directory all persistent Growmont CRM data should live under.
  ///
  /// Resolved once and cached — safe to call repeatedly from anywhere.
  static Future<Directory> get directory async {
    final cached = _cachedDir;
    if (cached != null) return cached;

    return _resolving ??= _resolve().then((dir) {
      _cachedDir = dir;
      _resolving = null;
      return dir;
    });
  }

  static Future<Directory> _resolve() async {
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } catch (e) {
      debugPrint(
        'AppPaths: getApplicationSupportDirectory failed, '
        'falling back to documents directory: $e',
      );
      base = await getApplicationDocumentsDirectory();
    }

    final dir = Directory(p.join(base.path, _appFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Full absolute path to a named file/folder inside the app data
  /// directory, e.g. `await AppPaths.childPath('growmont.db')`.
  static Future<String> childPath(String name) async {
    final dir = await directory;
    return p.join(dir.path, name);
  }

  // ── Diagnostic snapshot (used by DataLocationCard) ─────────────────────

  /// Returns a live snapshot of Growmont CRM's storage locations, including
  /// the exact path to growmont.db, its size, the number of local backups,
  /// and the program folder. Safe to call repeatedly — does not create or
  /// move files.
  static Future<AppStorageInfo> resolveStorageInfo() async {
    final dbDir = (await directory).path;

    final dbPath = p.join(dbDir, 'growmont.db');
    final executableDir = File(Platform.resolvedExecutable).parent.path;

    int backupCount = 0;
    try {
      final dir = Directory(dbDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('growmont.backup.') && name.endsWith('.db')) {
              backupCount++;
            }
          }
        }
      }
    } catch (_) {
      // Non-fatal — diagnostic only.
    }

    return AppStorageInfo(
      databaseDirectory: dbDir,
      database: _statFile(dbPath),
      executableDirectory: executableDir,
      backupCount: backupCount,
    );
  }

  static AppFileInfo _statFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return AppFileInfo(path: path, exists: false);
      }
      final stat = file.statSync();
      return AppFileInfo(
        path: path,
        exists: true,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    } catch (_) {
      return AppFileInfo(path: path, exists: false);
    }
  }
}
