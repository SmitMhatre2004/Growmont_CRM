import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/cloud_callables.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/attendance/attendance_models.dart';
import 'package:growmont_crm/features/attendance/attendance_providers.dart';
import 'package:growmont_crm/features/attendance/attendance_screen.dart';
import 'package:growmont_crm/features/attendance/attendance_summary_card.dart';
import 'package:growmont_crm/features/attendance/device_gateways.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_fakes.dart';

class _Auth extends AuthNotifier {
  _Auth(this.role);
  final UserRole role;

  @override
  AuthState build() => AuthState(
    user: AppUser(id: 'emp1', email: 'a@growmont.com', name: 'Asha', role: role),
    isLoading: false,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeAttendanceService service,
  FakeLocation? location,
  FakeBiometric? biometric,
  UserRole role = UserRole.employee,
  bool canMark = true,
  Size size = const Size(390, 800),
  double textScale = 1.0,
  Widget? home,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _Auth(role)),
        attendanceServiceProvider.overrideWithValue(service),
        locationGatewayProvider.overrideWithValue(location ?? FakeLocation()),
        biometricGatewayProvider.overrideWithValue(biometric ?? FakeBiometric()),
        canMarkAttendanceProvider.overrideWithValue(canMark),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: home ?? const AttendanceScreen()),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openTab(WidgetTester t, String label) async {
  final tab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text(label),
  );
  await t.ensureVisible(tab);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(tab);
  await _settle(t);
}

void main() {
  testWidgets('today shows date, shift, times and the mark button', (t) async {
    final service = FakeAttendanceService();
    await _pump(t, service: service);

    expect(find.text('Thu 19 Nov 2026'), findsOneWidget);
    expect(find.textContaining('10:00 – 19:00'), findsOneWidget);
    expect(find.textContaining('15 min grace'), findsOneWidget);
    expect(find.byTooltip('Working day'), findsOneWidget);
    expect(find.text('Not marked'), findsOneWidget);
    expect(find.text('Mark present'), findsOneWidget);
    expect(find.text('--:--'), findsNWidgets(2));
  });

  testWidgets('button follows the day: check-out, then Done + update',
      (t) async {
    final service = FakeAttendanceService()
      ..today = todayJson(record: recJson(inT: '10:02'));
    await _pump(t, service: service);
    expect(find.text('Mark check-out'), findsOneWidget);
    expect(find.text('Mark present'), findsNothing);

    service.today = todayJson(record: recJson(inT: '10:02', outT: '19:01'));
    final ctx = t.element(find.byType(AttendanceScreen));
    ProviderScope.containerOf(ctx).invalidate(attendanceTodayProvider);
    await _settle(t);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Update check-out'), findsOneWidget);
  });

  testWidgets('PC shows status but no mark button and never touches GPS',
      (t) async {
    final location = FakeLocation();
    final biometric = FakeBiometric();
    await _pump(
      t,
      service: FakeAttendanceService(),
      location: location,
      biometric: biometric,
      canMark: false,
      size: const Size(1280, 800),
    );
    expect(find.text('Mark attendance from the phone app'), findsOneWidget);
    expect(find.text('Mark present'), findsNothing);
    expect(find.text('Mark check-out'), findsNothing);
    expect(find.textContaining('10:00 – 19:00'), findsOneWidget);
    expect(location.accessCalls + location.fixCalls, 0);
    expect(biometric.calls, 0);
  });

  testWidgets('non-admin sees no admin tabs', (t) async {
    await _pump(t, service: FakeAttendanceService());
    for (final label in ['Team', 'Approvals', 'Holidays', 'Settings']) {
      expect(find.text(label), findsNothing, reason: label);
    }
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('admin sees every tab, with the pending count on Approvals',
      (t) async {
    final service = FakeAttendanceService()
      ..approvals = const [
        ApprovalItem(
          employeeId: 'e2',
          employeeName: 'Ravi',
          date: '2026-11-18',
          kind: 'late',
          minutes: 25,
          note: 'Bus broke down',
          expected: '10:00',
          actual: '10:25',
        ),
      ];
    await _pump(t, service: service, role: UserRole.admin);
    for (final label in ['Today', 'Team', 'Approvals', 'Holidays', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('1'), findsOneWidget); // the badge
  });

  testWidgets('a successful mark refreshes and shows the new state', (t) async {
    final service = FakeAttendanceService();
    await _pump(t, service: service);

    await t.tap(find.text('Mark present'));
    await _settle(t);

    expect(service.markCalls, hasLength(1));
    expect(find.text('Mark check-out'), findsOneWidget);
    expect(find.textContaining('Marked present at 10:05'), findsOneWidget);
  });

  testWidgets('double tap sends exactly one mark', (t) async {
    final service = FakeAttendanceService()..markGate = Completer<void>();
    await _pump(t, service: service);

    await t.tap(find.text('Mark present'));
    // No pump between taps: the second lands on the not-yet-rebuilt button.
    await t.tap(find.text('Mark present'), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byType(FilledButton).first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 100));

    service.markGate!.complete();
    await _settle(t);
    expect(service.markCalls, hasLength(1));
  });

  testWidgets('network failure shows Retry, no false success, then recovers',
      (t) async {
    final service = FakeAttendanceService()
      ..markError = const BackendException(
        'Could not reach the server. Check your internet connection and try '
        'again.',
      );
    await _pump(t, service: service);

    await t.tap(find.text('Mark present'));
    await _settle(t);
    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Marked present'), findsNothing);

    service.markError = null;
    await t.tap(find.text('Retry'));
    await _settle(t);
    expect(find.textContaining('Marked present at'), findsOneWidget);
    expect(service.markCalls, hasLength(2));
  });

  testWidgets('too far: shows distance, no biometric prompt', (t) async {
    final location = FakeLocation()..distance = 250;
    final biometric = FakeBiometric();
    await _pump(
      t,
      service: FakeAttendanceService(),
      location: location,
      biometric: biometric,
    );
    await t.tap(find.text('Mark present'));
    await _settle(t);
    expect(find.textContaining('You are 250 m away'), findsOneWidget);
    expect(biometric.calls, 0);
  });

  testWidgets('permission denied forever offers Open app settings', (t) async {
    final location = FakeLocation()..access = LocationAccess.deniedForever;
    await _pump(t, service: FakeAttendanceService(), location: location);
    await t.tap(find.text('Mark present'));
    await _settle(t);
    await t.tap(find.text('Open app settings'));
    await t.pump();
    expect(location.openedAppSettings, 1);
  });

  testWidgets('biometric cancelled leaves the screen quiet', (t) async {
    final service = FakeAttendanceService();
    await _pump(
      t,
      service: service,
      biometric: FakeBiometric()..result = BiometricResult.cancelled,
    );
    await t.tap(find.text('Mark present'));
    await _settle(t);
    expect(service.markCalls, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('fingerprint'), findsNothing);
    expect(find.text('Mark present'), findsOneWidget);
  });

  testWidgets('no biometrics enrolled shows a clear message', (t) async {
    await _pump(
      t,
      service: FakeAttendanceService(),
      biometric: FakeBiometric()..result = BiometricResult.notEnrolled,
    );
    await t.tap(find.text('Mark present'));
    await _settle(t);
    expect(find.textContaining('set up on this phone'), findsOneWidget);
  });

  testWidgets('early check-out asks for confirmation naming the minutes',
      (t) async {
    final service = FakeAttendanceService()
      ..today = todayJson(time: '17:30', record: recJson(inT: '10:00'));
    await _pump(t, service: service);

    await t.tap(find.text('Mark check-out'));
    await _settle(t);
    expect(find.text('Check out early?'), findsOneWidget);
    expect(find.textContaining('90 minutes'), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await _settle(t);
    expect(service.markCalls, isEmpty);
  });

  testWidgets('a late mark opens the note prompt straight away', (t) async {
    final service = FakeAttendanceService()
      ..onMark = (_) => recJson(
        inT: '10:40',
        late: 40,
        lateStatus: 'needs_note',
      );
    await _pump(t, service: service);

    await t.tap(find.text('Mark present'));
    await _settle(t);
    expect(find.text('Why were you late?'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'Bus broke down');
    await t.tap(find.text('Send note'));
    await _settle(t);
    expect(service.notes, ['2026-11-19|late|Bus broke down']);
  });

  testWidgets('note must be at least 3 characters', (t) async {
    final service = FakeAttendanceService()
      ..onMark = (_) => recJson(inT: '10:40', late: 40, lateStatus: 'needs_note');
    await _pump(t, service: service);
    await t.tap(find.text('Mark present'));
    await _settle(t);
    await t.enterText(find.byType(TextField), 'a');
    await t.tap(find.text('Send note'));
    await _settle(t);
    expect(find.textContaining('between 3 and 500'), findsOneWidget);
    expect(service.notes, isEmpty);
  });

  testWidgets('items needing a note are prompted for in the month list',
      (t) async {
    final service = FakeAttendanceService()
      ..today = todayJson(
        record: recJson(inT: '10:40', late: 40, lateStatus: 'needs_note'),
      )
      ..monthData = monthWith([
        dayWith(recJson(date: '2026-11-17', inT: '10:30', late: 30, lateStatus: 'needs_note')),
        dayWith(recJson(
          date: '2026-11-16',
          inT: '10:20',
          late: 20,
          lateStatus: 'rejected',
          lateNote: 'Traffic',
          comment: 'Please leave earlier',
        )),
      ]);
    await _pump(t, service: service);

    expect(find.text('Please write a note'), findsNWidgets(2));
    expect(find.text('Note needed'), findsWidgets);

    // The calendar marks the day; its sheet carries the rejection.
    final day = find.byKey(const ValueKey('day-2026-11-16'));
    await t.dragUntilVisible(day, find.byType(ListView).first, const Offset(0, -200));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(day);
    await _settle(t);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.textContaining('Please leave earlier'), findsOneWidget);
  });

  testWidgets('loading, error with retry, then data', (t) async {
    final service = FakeAttendanceService()
      ..todayError = const BackendException('Could not reach the server.');
    await _pump(t, service: service);
    expect(find.text('Retry'), findsOneWidget);

    service.todayError = null;
    await t.tap(find.text('Retry'));
    await _settle(t);
    expect(find.text('Mark present'), findsOneWidget);
  });

  testWidgets('empty month shows an empty state, not a blank gap', (t) async {
    await _pump(t, service: FakeAttendanceService());
    expect(find.text('No days to show'), findsOneWidget);
  });

  testWidgets('approvals: not_pending refreshes the list', (t) async {
    final service = FakeAttendanceService()
      ..reviewError = const BackendException(
        'x',
        code: 'not_pending',
      )
      ..approvals = const [
        ApprovalItem(
          employeeId: 'e2',
          employeeName: 'Ravi',
          date: '2026-11-18',
          kind: 'late',
          minutes: 25,
          note: 'Bus broke down',
          expected: '10:00',
          actual: '10:25',
        ),
      ];
    await _pump(t, service: service, role: UserRole.admin);
    await _openTab(t, 'Approvals');

    expect(find.text('Ravi'), findsOneWidget);
    expect(find.textContaining('Bus broke down'), findsOneWidget);
    await t.tap(find.text('Approve'));
    await _settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await _settle(t);

    expect(service.reviewCalls, 1);
    expect(find.textContaining('already reviewed'), findsOneWidget);
    expect(find.text('Nothing to approve'), findsOneWidget);
  });

  testWidgets('settings warn about a radius under 20 m', (t) async {
    await _pump(t, service: FakeAttendanceService(), role: UserRole.admin);
    await _openTab(t, 'Settings');
    expect(find.textContaining('under 20 m is risky'), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
  });

  group('phone widths', () {
    for (final width in [320.0, 360.0]) {
      testWidgets('every tab fits at $width wide with large text', (t) async {
        final service = FakeAttendanceService()
          ..today = todayJson(
            record: recJson(inT: '10:40', late: 40, lateStatus: 'needs_note'),
          )
          ..monthData = monthWith([
            dayWith(recJson(date: '2026-11-17', inT: '10:30', outT: '16:00', late: 30, early: 180, lateStatus: 'pending', earlyStatus: 'needs_note', lateNote: 'A long explanation about the very slow bus ride into the city')),
            const MonthDay(date: '2026-11-08', type: 'holiday', status: 'off', holidayName: 'Diwali Lakshmi Pujan'),
          ])
          ..approvals = const [
            ApprovalItem(
              employeeId: 'e2',
              employeeName: 'Ravindra Subramaniam-Kulkarni',
              date: '2026-11-18',
              kind: 'early',
              minutes: 125,
              note: 'Family emergency that needed me at home right away',
              expected: '19:00',
              actual: '16:55',
            ),
          ];
        await _pump(
          t,
          service: service,
          role: UserRole.admin,
          size: Size(width, 720),
          textScale: 1.3,
        );
        expect(t.takeException(), isNull);

        for (final label in ['Team', 'Approvals', 'Holidays', 'Settings']) {
          await _openTab(t, label);
          expect(t.takeException(), isNull, reason: label);
        }
      });
    }
  });

  testWidgets('summary card: nulls read as Not rated yet', (t) async {
    final service = FakeAttendanceService()
      ..monthData = monthWith(
        const [],
        summary: const MonthSummary(workingDays: 5, present: 3),
      );
    await _pump(
      t,
      service: service,
      home: const SingleChildScrollView(child: AttendanceSummaryCard()),
    );
    expect(find.text('3 of 5 working days present'), findsOneWidget);
    expect(find.text('Not rated yet'), findsNWidgets(2));
    expect(find.text('Not ranked'), findsOneWidget);
  });

  testWidgets('summary card: full numbers, rank and stars', (t) async {
    final service = FakeAttendanceService()
      ..monthData = monthWith(
        const [],
        summary: const MonthSummary(
          workingDays: 20,
          present: 18,
          late: 2,
          early: 1,
          absent: 2,
          percent: 90,
          stars: 4.5,
          rank: 3,
          rankedOf: 12,
        ),
      );
    await _pump(
      t,
      service: service,
      size: const Size(320, 700),
      home: const SingleChildScrollView(child: AttendanceSummaryCard()),
    );
    expect(find.text('#3 of 12'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.textContaining('4.5'), findsOneWidget);
    expect(find.text('Late 2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('summary card failure stays inside the card and can retry',
      (t) async {
    final service = FakeAttendanceService()
      ..monthError = const BackendException('Could not reach the server.');
    await _pump(
      t,
      service: service,
      home: const Column(
        children: [Text('host screen'), AttendanceSummaryCard()],
      ),
    );
    expect(find.text('host screen'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(t.takeException(), isNull);

    service.monthError = null;
    service.monthData = monthWith(
      const [],
      summary: const MonthSummary(workingDays: 4, present: 4, percent: 100, stars: 5.0),
    );
    await t.tap(find.text('Retry'));
    await _settle(t);
    expect(find.text('4 of 4 working days present'), findsOneWidget);
  });

  test('platform check is phone-only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(platformCanMarkAttendance(), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(platformCanMarkAttendance(), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an unexpected error mid-mark does not leave the button stuck busy',
      (t) async {
    final service = FakeAttendanceService();
    final biometric = FakeBiometric()..error = StateError('prompt crashed');
    await _pump(t, service: service, biometric: biometric);

    await t.tap(find.text('Mark present'));
    await _settle(t);
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(service.markCalls, isEmpty);

    // The button works again: nothing is left disabled or spinning.
    biometric.error = null;
    await t.tap(find.text('Retry'));
    await _settle(t);
    expect(find.textContaining('Marked present at'), findsOneWidget);
  });

}
