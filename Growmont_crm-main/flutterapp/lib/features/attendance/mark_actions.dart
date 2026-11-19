import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_widgets.dart';
import 'mark_flow.dart';

/// Asks before an early check-out. True means go on.
Future<bool> confirmEarlyCheckout(BuildContext context, int minutes) async {
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Check out early?'),
      content: Text(
        'You are leaving $minutes minutes before the end of your shift. '
        'This will need a note and an admin\'s review.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Check out'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Refreshes everything that shows today's attendance.
void refreshAttendance(ProviderContainer container) {
  container.invalidate(attendanceTodayProvider);
  container.invalidate(attendanceMonthProvider);
}

/// Opens the note dialog for a late/early item and refreshes after a save.
Future<void> writeAttendanceNote(
  BuildContext context, {
  required String date,
  required String kind,
  required AttendanceRecord record,
}) async {
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context);
  final saved = await showAttendanceNoteDialog(
    context,
    service: container.read(attendanceServiceProvider),
    date: date,
    kind: kind,
    minutes: kind == 'late' ? record.lateMinutes : record.earlyMinutes,
    existingNote: (kind == 'late' ? record.late : record.early).note,
  );
  if (saved) refreshAttendance(container);
}

/// The whole mark, shared by the Attendance screen and the Dashboard ring:
/// GPS, distance, early confirmation, biometric, server; then a refresh of
/// every attendance provider, the confirmation snackbar and, for a late or
/// early result, the note prompt.
///
/// Returns null when another mark is already running. Failures are returned
/// for the caller to present; nothing is shown for them here.
Future<MarkOutcome?> performMark(
  BuildContext context,
  String action, {
  void Function(String status)? onStatus,
}) async {
  final container = ProviderScope.containerOf(context);
  final busy = container.read(attendanceMarkBusyProvider.notifier);
  if (busy.state) return null;
  busy.state = true;

  final flow = MarkFlow(
    service: container.read(attendanceServiceProvider),
    location: container.read(locationGatewayProvider),
    biometric: container.read(biometricGatewayProvider),
    deviceId: container.read(deviceIdStoreProvider).get,
  );
  MarkOutcome outcome;
  try {
    outcome = await flow.run(
      action: action,
      onStatus: (s) => onStatus?.call(s),
      confirmEarly: (m) => confirmEarlyCheckout(context, m),
    );
  } catch (_) {
    // Anything the flow did not foresee must not leave the button stuck on
    // "busy" for the rest of the session.
    outcome = const MarkFailed(
      'Something went wrong. Please try again.',
      fix: MarkFix.retry,
    );
  }
  busy.state = false;

  if (outcome is MarkSuccess) {
    refreshAttendance(container);
    if (!context.mounted) return outcome;
    final r = outcome.result.record;
    final message = outcome.result.already
        ? 'You are already marked present.'
        : action == 'in'
        ? 'Marked present at ${r.checkInLocal ?? ''}.'
        : 'Check-out saved at ${r.checkOutLocal ?? ''}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    // A late or early mark needs a note, so ask for it straight away.
    final kind = action == 'in' ? 'late' : 'early';
    final item = kind == 'late' ? r.late : r.early;
    if (item.needsNote && context.mounted) {
      await writeAttendanceNote(context, date: r.date, kind: kind, record: r);
    }
  }
  return outcome;
}

/// Label for the button that fixes a failed mark, or null.
String? markFixLabel(MarkFix fix) => switch (fix) {
  MarkFix.retry => 'Retry',
  MarkFix.openAppSettings => 'Open app settings',
  MarkFix.openLocationSettings => 'Open location settings',
  MarkFix.none => null,
};
