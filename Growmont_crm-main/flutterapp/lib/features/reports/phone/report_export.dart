// lib/features/reports/phone/report_export.dart
//
// Export for the phone Reports screens: a small bottom sheet (PDF report,
// and Excel in month mode) and the code that builds and saves the file.
//
// Saving goes through the same FileSaver / ExcelIO calls the wide layout's
// export uses, so the result lands (or is shared) exactly the same way.

import 'package:flutter/material.dart';

import '../../../core/excel/excel_io.dart';
import '../../../core/io/file_saver.dart';
import '../../../core/reports/employee_report.dart';
import '../../../core/reports/monthly_report.dart';
import '../../../core/reports/monthly_report_builder.dart';
import '../../../core/reports/monthly_report_excel.dart';
import '../../../core/reports/performance_report_pdf.dart';
import '../../../core/reports/period_summary_builder.dart';
import '../../../core/theme/app_theme.dart';
import 'employee_report_view.dart' show ReportData;
import 'period_selection.dart';
import 'phone_style.dart';
import 'team_tab.dart' show TeamSort, sortTeam;

enum PhoneExportChoice { pdf, excel }

/// Bottom sheet with "PDF report" (primary) and, when [allowExcel], "Excel".
Future<PhoneExportChoice?> showPhoneExportSheet(
  BuildContext context, {
  required bool allowExcel,
}) {
  return showModalBottomSheet<PhoneExportChoice>(
    constraints: const BoxConstraints(maxWidth: 560),
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(sheetContext, PhoneExportChoice.pdf),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF report'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            ),
            if (allowExcel) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(sheetContext, PhoneExportChoice.excel),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text('Excel', style: PhoneText.label),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Builds and saves the chosen file. Errors are reported in a SnackBar, never
/// thrown. The caller shows its own progress indicator while this runs.
///
/// [employeeId] is the one person a report is about; null is the company
/// report ([ReportData] is already scoped to what the user may see).
Future<void> exportPhoneReport(
  BuildContext context, {
  required PhoneExportChoice choice,
  required ReportData data,
  required ReportPeriodSelection selection,
  required String generatedBy,
  String? employeeId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String message, {bool error = false}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  try {
    final shareText = 'Growmont CRM report — ${selection.label}';
    final String? path;

    if (choice == PhoneExportChoice.pdf) {
      final summary = PeriodSummaryBuilder.build(
        range: selection.range,
        previous: selection.previousRange,
        sales: data.sales,
        interactions: data.interactions,
        clients: data.clients,
        employeeNames: data.employeeNames,
      );
      final companyScope = employeeId == null;
      final List<EmployeeReport> employees = companyScope
          ? [
              for (final row in sortTeam(summary.employees, TeamSort.revenue))
                data.employeeReport(row.employeeId, selection),
            ]
          : [data.employeeReport(employeeId, selection)];

      final bytes = await PerformanceReportPdf.build(
        periodLabel: selection.label,
        summary: summary,
        employees: employees,
        companyScope: companyScope,
        generatedAt: DateTime.now(),
        generatedBy: generatedBy,
      );
      path = await FileSaver.save(
        filename: PerformanceReportPdf.fileName(
          periodLabel: selection.label,
          employeeName: companyScope ? null : employees.first.name,
        ),
        bytes: bytes,
        extensions: const ['pdf'],
        shareText: shareText,
      );
    } else {
      final report = monthlyReportFor(
        data: data,
        month: selection.month,
        employeeId: employeeId,
        scopeLabel: employeeId == null
            ? 'Whole company'
            : (data.employeeNames[employeeId] ?? 'Employee'),
      );
      path = await ExcelIO.exportMultiSheetWorkbook(
        filename: MonthlyReportExcel.filename(report),
        sheets: MonthlyReportExcel.sheets(report),
        shareText: shareText,
      );
    }

    if (path != null) toast('Report saved to $path');
  } catch (e) {
    toast('Could not export the report: $e', error: true);
  }
}

/// The monthly report (what Excel writes and the 12-month chart reads) for
/// the whole of [data], or for one person in it.
MonthlyReport monthlyReportFor({
  required ReportData data,
  required ReportMonth month,
  required String scopeLabel,
  String? employeeId,
}) {
  final id = employeeId;
  return MonthlyReportBuilder.build(
    period: month,
    scope: id == null ? ReportScope.company : ReportScope.individual,
    scopeLabel: scopeLabel,
    sales: id == null
        ? data.sales
        : [
            for (final s in data.sales)
              if (MonthlyReportBuilder.repIdOf(s) == id) s,
          ],
    interactions: id == null
        ? data.interactions
        : [
            for (final i in data.interactions)
              if ((i.employeeId ?? i.employee).trim() == id) i,
          ],
    clients: id == null
        ? data.clients
        : [
            for (final c in data.clients)
              if (c.employeeId.trim() == id) c,
          ],
    employeeNames: data.employeeNames,
  );
}
