import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/attendance/attendance_models.dart';
import 'package:growmont_crm/features/attendance/attendance_providers.dart';
import 'package:growmont_crm/features/attendance/attendance_screen.dart';
import 'package:growmont_crm/features/attendance/employee_month_view.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_fakes.dart';

class _Auth extends AuthNotifier {
  _Auth(this.role);
  final UserRole role;

  @override
  AuthState build() => AuthState(
    user: AppUser(
      id: 'boss',
      email: 'b@growmont.com',
      name: 'Boss',
      role: role,
    ),
    isLoading: false,
  );
}

String _k(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

MonthDay _day(String date, String kind, {Map<String, dynamic>? rec}) =>
    MonthDay(
      date: date,
      type: 'working',
      status: 'present',
      kind: kind,
      record: rec == null ? null : AttendanceRecord.fromJson(rec),
    );

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester t, {
  required FakeAttendanceService service,
  required UserRole role,
  required Widget home,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _Auth(role)),
        attendanceServiceProvider.overrideWithValue(service),
        canMarkAttendanceProvider.overrideWithValue(false),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await _settle(t);
  addTearDown(() async => t.pumpWidget(const SizedBox()));
}

const _view = Scaffold(
  body: SingleChildScrollView(
    child: EmployeeMonthView(employeeId: 'emp7', employeeName: 'Ravi Patil'),
  ),
);

void main() {
  final now = DateTime.now();
  final firstKey = _k(DateTime(now.year, now.month, 1));
  final edit = find.byKey(const ValueKey('day-edit-times'));

  Future<void> openDay(WidgetTester t, String date) async {
    final cell = find.byKey(ValueKey('day-$date'));
    await t.ensureVisible(cell);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(cell);
    await _settle(t);
    expect(find.byKey(const ValueKey('day-sheet')), findsOneWidget);
  }

  MonthData month({
    Map<String, dynamic>? rec,
    String kind = DayKind.missedCheckout,
  }) => MonthData(
    summary: const MonthSummary(workingDays: 10),
    days: [
      _day(firstKey, kind, rec: rec),
      _day(_k(DateTime(now.year, now.month, 28)), DayKind.upcoming),
    ],
  );

  Future<void> pickTime(WidgetTester t, String placeholder) async {
    await t.tap(find.text(placeholder));
    await _settle(t);
    await t.tap(find.text('OK'));
    await _settle(t);
  }

  group('admin employee month', () {
    testWidgets('admin edits a past check-out for that employee', (t) async {
      final service = FakeAttendanceService()
        ..monthData = month(
          rec: recJson(date: firstKey, inT: '10:02'),
        );
      await _pump(t, service: service, role: UserRole.admin, home: _view);
      expect(service.monthEmployeeIds, contains('emp7'));
      await openDay(t, firstKey);
      expect(find.text('Write note'), findsNothing);
      await t.tap(edit);
      await _settle(t);
      await pickTime(t, 'No check-out');
      await t.enterText(find.byType(TextField), 'Forgot to mark out');
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(service.editCalls, hasLength(1));
      final c = service.editCalls.single;
      expect(c.employeeId, 'emp7');
      expect(c.date, firstKey);
      expect(c.checkIn, '10:02');
      expect(c.checkOut, isNotNull);
      expect(c.reason, 'Forgot to mark out');
    });

    testWidgets('a reason is required and the error is shown', (t) async {
      final service = FakeAttendanceService()
        ..monthData = month(
          rec: recJson(date: firstKey, inT: '10:02'),
        );
      await _pump(t, service: service, role: UserRole.admin, home: _view);
      await openDay(t, firstKey);
      await t.tap(edit);
      await _settle(t);
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(find.textContaining('reason of 3 to 300'), findsOneWidget);
      expect(service.editCalls, isEmpty);
    });

    testWidgets('admin adds timing to an absent day', (t) async {
      final service = FakeAttendanceService()
        ..monthData = month(kind: DayKind.absent);
      await _pump(t, service: service, role: UserRole.admin, home: _view);
      await openDay(t, firstKey);
      expect(
        find.descendant(of: edit, matching: find.text('Add timing')),
        findsOneWidget,
      );
      await t.tap(edit);
      await _settle(t);
      await pickTime(t, 'No check-in');
      await t.enterText(find.byType(TextField), 'Worked, was not marked');
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(service.editCalls, hasLength(1));
      final c = service.editCalls.single;
      expect(c.employeeId, 'emp7');
      expect(c.date, firstKey);
      expect(c.checkIn, isNotNull);
      expect(c.checkOut, isNull);
    });

    testWidgets('a future day is never editable', (t) async {
      if (now.day >= 28) {
        markTestSkipped('no future day left in this month');
        return;
      }
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service, role: UserRole.admin, home: _view);
      await openDay(t, _k(DateTime(now.year, now.month, 28)));
      expect(edit, findsNothing);
    });

    testWidgets('a non-admin sees no calendar and loads nothing', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service, role: UserRole.employee, home: _view);
      expect(find.byKey(ValueKey('day-$firstKey')), findsNothing);
      expect(edit, findsNothing);
      expect(service.monthCalls, 0);
    });

    testWidgets('the employee screen says admins only for a non-admin', (
      t,
    ) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(
        t,
        service: service,
        role: UserRole.employee,
        home: const EmployeeMonthScreen(
          employeeId: 'emp7',
          employeeName: 'Ravi',
        ),
      );
      expect(find.text('Only admins can view this.'), findsOneWidget);
      expect(service.monthCalls, 0);
    });

    test('the provider refuses another person for a non-admin', () async {
      final service = FakeAttendanceService();
      final c = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => _Auth(UserRole.employee)),
          attendanceServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(c.dispose);
      await expectLater(
        c.read(
          attendanceMonthProvider((
            employeeId: 'emp7',
            month: '2026-11',
          )).future,
        ),
        throwsStateError,
      );
      expect(service.monthCalls, 0);
    });

    testWidgets('Team tab opens an employee month for an admin', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(
        t,
        service: service,
        role: UserRole.admin,
        home: const Scaffold(body: AttendanceScreen()),
      );
      await t.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('Team')),
      );
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('team-month-emp1')));
      await _settle(t);
      expect(find.byType(EmployeeMonthScreen), findsOneWidget);
      expect(service.monthEmployeeIds, contains('emp1'));
    });

    testWidgets('a non-admin has no Team tab', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(
        t,
        service: service,
        role: UserRole.employee,
        home: const Scaffold(body: AttendanceScreen()),
      );
      expect(find.text('Team'), findsNothing);
      expect(find.byKey(const ValueKey('team-month-emp1')), findsNothing);
    });
  });
}
