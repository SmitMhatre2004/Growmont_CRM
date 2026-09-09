import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Generic .xlsx read/write helpers used by every screen's Export/Import
/// buttons. All parsing/building runs on-device — there is no server
/// component involved.
class ExcelIO {
  ExcelIO._();

  /// Builds a single-sheet .xlsx workbook in memory. Cell values may be
  /// [String], [num], [bool], [DateTime], or null.
  static Uint8List buildBytes({
    required String sheetName,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    final workbook = xls.Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.rename(defaultSheet, sheetName);
    }
    final sheet = workbook[sheetName];

    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(_toCellValue).toList());
    }

    // Size every column to its longest cell (header included), the same
    // way Excel's own "AutoFit Column Width" does — no column here was
    // getting a deliberate width before, so every sheet used Excel's
    // generic default regardless of content.
    for (var i = 0; i < headers.length; i++) {
      sheet.setColumnAutoFit(i);
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('Failed to encode workbook');
    }
    return Uint8List.fromList(bytes);
  }

  /// Builds a workbook and hands it to the user.
  ///
  /// On desktop (Windows/macOS/Linux) this opens a native "Save As" dialog
  /// and writes the file straight to the chosen path — `share_plus`'s
  /// share sheet doesn't save a file there, it just opens the OS share
  /// flyout, which is why Export used to look like it did nothing on
  /// Windows. On mobile/web the OS share sheet is the right, idiomatic
  /// place to hand off a generated file, so that path is unchanged.
  ///
  /// Returns the saved file path when the desktop dialog was used and the
  /// user picked a location; null otherwise (mobile/web share, or the
  /// user cancelled the save dialog).
  static Future<String?> exportWorkbook({
    required String filename,
    required String sheetName,
    required List<String> headers,
    required List<List<Object?>> rows,
    String? shareText,
  }) async {
    final bytes = buildBytes(
      sheetName: sheetName,
      headers: headers,
      rows: rows,
    );

    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      return FilePicker.platform.saveFile(
        dialogTitle: 'Save $filename',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: bytes,
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)], text: shareText ?? filename);
    return null;
  }

  static xls.CellValue? _toCellValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) {
      return xls.DateCellValue(
        year: value.year,
        month: value.month,
        day: value.day,
      );
    }
    if (value is int) return xls.IntCellValue(value);
    if (value is double) return xls.DoubleCellValue(value);
    if (value is bool) return xls.BoolCellValue(value);
    return xls.TextCellValue(value.toString());
  }

  /// Reads the first sheet of an .xlsx file and returns its data rows
  /// (the header row is skipped). Each cell comes back as [String], [num],
  /// [bool], [DateTime], or null, aligned to its column position.
  static Future<List<List<Object?>>> readDataRows(String path) async {
    final bytes = await File(path).readAsBytes();
    final workbook = xls.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];
    final sheet = workbook.tables[workbook.tables.keys.first]!;
    final rows = sheet.rows;
    if (rows.length <= 1) return [];
    return rows.skip(1).map((row) {
      return row.map(_fromCellData).toList();
    }).toList();
  }

  static Object? _fromCellData(xls.Data? data) {
    final value = data?.value;
    if (value == null) return null;
    if (value is xls.IntCellValue) return value.value;
    if (value is xls.DoubleCellValue) return value.value;
    if (value is xls.BoolCellValue) return value.value;
    if (value is xls.DateCellValue) return value.asDateTimeLocal();
    if (value is xls.DateTimeCellValue) return value.asDateTimeLocal();
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// True if every cell in [row] is null or an empty/whitespace string —
  /// used to skip blank trailing rows some spreadsheet apps leave behind.
  static bool isBlankRow(List<Object?> row) {
    return row.every((c) => c == null || c.toString().trim().isEmpty);
  }

  /// Cell at [index], or null if the row is too short / the value is blank.
  static Object? cell(List<Object?> row, int index) {
    if (index < 0 || index >= row.length) return null;
    return row[index];
  }

  /// Cell at [index] as trimmed text, or '' if absent.
  static String text(List<Object?> row, int index) {
    final v = cell(row, index);
    return v == null ? '' : v.toString().trim();
  }

  /// Parses a date-like cell value. A native Excel date comes back from
  /// [readDataRows] as a [DateTime] already; typed text is parsed as
  /// dd/mm/yyyy (matching what [buildBytes] produces) rather than with
  /// [DateTime.parse], which expects yyyy-mm-dd and would otherwise
  /// silently swap day and month for ambiguous input.
  static DateTime? date(List<Object?> row, int index) {
    final value = cell(row, index);
    if (value == null) return null;
    if (value is DateTime) return value;

    final str = value.toString().trim();
    if (str.isEmpty) return null;

    final dmy = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$').firstMatch(str);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!);
      final month = int.parse(dmy.group(2)!);
      final year = int.parse(dmy.group(3)!);
      return _safeDate(year, month, day);
    }

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(str);
    if (iso != null) {
      return _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    return DateTime.tryParse(str);
  }

  /// Cell at [index] parsed as a date and formatted 'yyyy-MM-dd', or ''.
  static String isoDate(List<Object?> row, int index) {
    final d = date(row, index);
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final d = DateTime(year, month, day);
    return d;
  }
}
