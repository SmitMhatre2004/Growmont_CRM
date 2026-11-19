import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/cloud_callables.dart';
import '../auth/auth_provider.dart';
import 'attendance_models.dart';
import 'attendance_service.dart';
import 'device_gateways.dart';

final attendanceServiceProvider = Provider<AttendanceService>(
  (ref) => CallableAttendanceService(CloudCallables()),
);

final locationGatewayProvider = Provider<LocationGateway>(
  (ref) => GeolocatorGateway(),
);

final biometricGatewayProvider = Provider<BiometricGateway>(
  (ref) => LocalAuthGateway(),
);

final deviceIdStoreProvider = Provider<DeviceIdStore>((ref) => DeviceIdStore());

/// True on Android and iOS only. Overridden in tests.
final canMarkAttendanceProvider = Provider<bool>(
  (ref) => platformCanMarkAttendance(),
);

final attendanceTodayProvider = FutureProvider.autoDispose<TodayInfo>(
  (ref) => ref.watch(attendanceServiceProvider).getToday(),
);

/// A month's summary and days. [employeeId] null means the signed-in person.
typedef MonthKey = ({String? employeeId, String month});

final attendanceMonthProvider = FutureProvider.autoDispose
    .family<MonthData, MonthKey>((ref, key) {
      // Another person's month is for admins only (the server enforces it
      // too); a non-admin can only ever load their own.
      final id = key.employeeId;
      if (id != null) {
        final user = ref.watch(authProvider).user;
        if (user == null || (!user.isAdmin && user.id != id)) {
          throw StateError('Only an admin can view another month.');
        }
      }
      return ref
          .watch(attendanceServiceProvider)
          .month(key.month, employeeId: id);
    });

final attendanceTeamDayProvider = FutureProvider.autoDispose
    .family<TeamDay, String>(
      (ref, date) => ref.watch(attendanceServiceProvider).teamDay(date),
    );

final attendanceTeamMonthProvider = FutureProvider.autoDispose
    .family<List<TeamMonthRow>, String>(
      (ref, month) => ref.watch(attendanceServiceProvider).teamMonth(month),
    );

/// True while a mark (from the Attendance screen or the Dashboard ring) is
/// in flight, so the two never send one at the same time.
final attendanceMarkBusyProvider = StateProvider<bool>((ref) => false);

final attendanceApprovalsProvider = FutureProvider.autoDispose<ApprovalsData>(
  (ref) => ref.watch(attendanceServiceProvider).listApprovals(),
);

final attendanceHolidaysProvider = FutureProvider.autoDispose
    .family<List<Holiday>, int>(
      (ref, year) => ref.watch(attendanceServiceProvider).listHolidays(year),
    );

final attendanceSettingsProvider =
    FutureProvider.autoDispose<AttendanceSettings>(
      (ref) => ref.watch(attendanceServiceProvider).getSettings(),
    );

/// 'YYYY-MM' for [d].
String monthKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// The month to show after the day rolls over from [oldDay] to [newDay]
/// (both 'YYYY-MM-DD'). Someone looking at the month that just ended is moved
/// to the new one; someone who browsed to another month is left where they are.
DateTime monthAfterDayChange(DateTime viewed, String oldDay, String newDay) {
  if (monthKeyOf(viewed) != oldDay.substring(0, 7)) return viewed;
  return DateTime(
    int.parse(newDay.substring(0, 4)),
    int.parse(newDay.substring(5, 7)),
  );
}

/// 'YYYY-MM-DD' for [d].
String dateKeyOf(DateTime d) =>
    '${monthKeyOf(d)}-${d.day.toString().padLeft(2, '0')}';
