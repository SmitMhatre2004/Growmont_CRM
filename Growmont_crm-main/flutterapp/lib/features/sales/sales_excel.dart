import '../../core/excel/excel_io.dart';
import '../../core/io/record_import.dart';
import '../../models/sale.dart';

/// Shared row (export) / payload (import) builders for the Sales Excel
/// sheet, reused by the Sales screen and the Info Portal's Sales tab so
/// both stay in lockstep with a single column layout.
const salesExcelHeaders = [
  'Date',
  'Client Name',
  'Sales Representative',
  'Product',
  'Company',
  'Scheme',
  'Amount (Rs)',
  'Frequency',
  'Remarks',
];

/// JSON field names, in the same column order as [salesExcelHeaders], so a
/// JSON record and a spreadsheet row feed the same payload builder.
const salesJsonKeys = [
  'date',
  'client_name',
  'sales_rep_name',
  'product',
  'company',
  'scheme',
  'amount',
  'frequency',
  'remarks',
];

List<Object?> saleExportRow(Sale s) {
  final date = DateTime.tryParse(s.date);
  return [
    date,
    s.clientName,
    s.salesRepName ?? s.salesRep,
    s.productDisplay ?? s.product,
    s.company,
    s.scheme,
    double.tryParse(s.amount) ?? (s.amountPaise / 100.0),
    s.frequencyDisplay ?? s.frequency,
    s.remarks,
  ];
}

/// Builds the payload for [FirestoreService.createSale] from one imported
/// row, or returns null if the row is blank or has no usable amount.
/// The sale is always attributed to the importing user, matching how a
/// manually-added sale is attributed.
Map<String, dynamic>? saleImportPayload(
  List<Object?> row, {
  required String currentUserName,
}) {
  if (ExcelIO.isBlankRow(row)) return null;

  final amountVal = double.tryParse(ExcelIO.text(row, 6));
  if (amountVal == null || amountVal <= 0) return null;

  final dateIso = ExcelIO.isoDate(row, 0);
  final clientName = ExcelIO.text(row, 1);
  final product = ExcelIO.text(row, 3);
  final company = ExcelIO.text(row, 4);
  final scheme = ExcelIO.text(row, 5);
  final frequency = ExcelIO.text(row, 7);
  final remarks = ExcelIO.text(row, 8);

  return {
    'date': dateIso.isNotEmpty
        ? dateIso
        : DateTime.now().toIso8601String().split('T').first,
    'client_name': clientName.isEmpty ? 'Unknown Client' : clientName,
    'sales_rep_name': currentUserName,
    'product': product.isEmpty ? 'MF' : product,
    'company': company,
    'scheme': scheme,
    'amount': amountVal.toString(),
    'frequency': frequency.isEmpty ? 'O' : frequency,
    'remarks': remarks,
  };
}

/// Fields that identify a sale on import. Remarks are deliberately left out:
/// everything else matching means it is the same sale, so a re-import with
/// reworded remarks should update that record rather than duplicate it.
const salesSignatureFields = [
  'date',
  'client_name',
  'sales_rep_name',
  'product',
  'company',
  'scheme',
  'amount',
  'frequency',
];

/// The signature of a sale already in the list, built to line up exactly with
/// what [saleImportPayload] produces for the same record - including its
/// fallbacks, or an existing sale with a blank client would never match an
/// imported row that became 'Unknown Client'.
String saleSignatureOf(Sale s) {
  final product = s.productDisplay ?? s.product;
  final frequency = s.frequencyDisplay ?? s.frequency;
  return recordSignature({
    'date': s.date,
    'client_name': s.clientName.isEmpty ? 'Unknown Client' : s.clientName,
    'sales_rep_name': s.salesRepName ?? s.salesRep,
    'product': product.isEmpty ? 'MF' : product,
    'company': s.company,
    'scheme': s.scheme,
    'amount': double.tryParse(s.amount) ?? (s.amountPaise / 100.0),
    'frequency': frequency.isEmpty ? 'O' : frequency,
  }, salesSignatureFields);
}
