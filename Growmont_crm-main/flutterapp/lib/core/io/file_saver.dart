import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes generated files (spreadsheets, JSON) out to the user.
///
/// Every export goes through here so the "don't clobber, don't fail" rule is
/// in one place: if the target name is taken, the file lands beside it as
/// `name (1).ext` rather than overwriting or - when the existing file is open
/// in Excel and locked by Windows - failing the export outright.
class FileSaver {
  FileSaver._();

  /// Highest suffix tried before giving up; a directory with this many
  /// collisions means something is wrong upstream, not that we should spin.
  static const int _maxAttempts = 999;

  /// [path] if nothing is there, otherwise the same name with ` (n)` inserted
  /// before the extension, counting up until it is free.
  static String uniquePath(String path) {
    if (!File(path).existsSync()) return path;

    final dir = p.dirname(path);
    final ext = p.extension(path);
    final stem = p.basenameWithoutExtension(path);

    for (var n = 1; n <= _maxAttempts; n++) {
      final candidate = p.join(dir, '$stem ($n)$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    // Astronomically unlikely; a timestamp is still better than throwing away
    // the user's export.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir, '$stem-$stamp$ext');
  }

  /// Hands [bytes] to the user as [filename].
  ///
  /// On desktop this opens a native Save As dialog and writes the file to the
  /// chosen location. On mobile it writes to a temp file and opens the share
  /// sheet, which is the idiomatic hand-off there.
  ///
  /// Returns the path actually written on desktop - which may differ from
  /// what the user typed, if that name was taken - and null on mobile or if
  /// the dialog was cancelled.
  static Future<String?> save({
    required String filename,
    required Uint8List bytes,
    required List<String> extensions,
    String? shareText,
  }) async {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop) {
      // Deliberately no `bytes:` here. Letting file_picker write means a
      // locked or existing target fails silently; taking the path back and
      // writing it ourselves is what lets uniquePath do its job.
      final chosen = await FilePicker.saveFile(
        dialogTitle: 'Save $filename',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      if (chosen == null) return null;

      final target = uniquePath(chosen);
      await File(target).writeAsBytes(bytes, flush: true);
      return target;
    }

    final dir = await getTemporaryDirectory();
    final target = uniquePath(p.join(dir.path, filename));
    await File(target).writeAsBytes(bytes, flush: true);
    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(target)], text: shareText ?? filename);
    return null;
  }
}
