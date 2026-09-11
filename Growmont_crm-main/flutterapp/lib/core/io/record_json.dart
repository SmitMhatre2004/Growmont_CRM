import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// JSON import/export that speaks the same shape as the spreadsheet path.
///
/// Records are read back as column-ordered rows aligned to [keys], so the
/// per-screen payload builders written for .xlsx apply unchanged - the two
/// formats cannot drift apart in how they normalize a record.
class RecordJson {
  RecordJson._();

  /// Current envelope version. Bumped only if the on-disk shape changes in a
  /// way older builds could not read.
  static const int version = 1;

  /// Encodes [rows] as a JSON document, each row keyed by [keys].
  static Uint8List encode({
    required String type,
    required List<String> keys,
    required List<List<Object?>> rows,
  }) {
    final records = rows.map((row) {
      final record = <String, Object?>{};
      for (var i = 0; i < keys.length; i++) {
        record[keys[i]] = _toJsonValue(i < row.length ? row[i] : null);
      }
      return record;
    }).toList();

    final document = {
      'type': type,
      'version': version,
      'exported_at': DateTime.now().toIso8601String(),
      'count': records.length,
      'records': records,
    };

    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(document)),
    );
  }

  /// Reads a document written by [encode] and returns its records as rows
  /// ordered by [keys].
  ///
  /// Also accepts a bare top-level array, so a hand-written or third-party
  /// file does not have to carry the envelope.
  static Future<List<List<Object?>>> readRows(
    String path,
    List<String> keys,
  ) async {
    final decoded = jsonDecode(await File(path).readAsString());

    final List<dynamic> records;
    if (decoded is List) {
      records = decoded;
    } else if (decoded is Map && decoded['records'] is List) {
      records = decoded['records'] as List;
    } else {
      throw const FormatException(
        'Not a Growmont export: expected a list of records.',
      );
    }

    return records.whereType<Map>().map((record) {
      return keys.map<Object?>((k) => record[k]).toList();
    }).toList();
  }

  /// True if [path] should be read as JSON rather than as a workbook.
  static bool isJsonPath(String path) => path.toLowerCase().endsWith('.json');

  static Object? _toJsonValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';
    }
    if (value is num || value is bool || value is String) return value;
    return value.toString();
  }
}
