import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/attendance/attendance_calendar.dart';
import 'package:growmont_crm/features/attendance/attendance_models.dart';
import 'package:growmont_crm/features/attendance/attendance_providers.dart';
import 'package:growmont_crm/features/attendance/attendance_screen.dart';
import 'package:growmont_crm/features/attendance/attendance_summary_card.dart';
import 'package:growmont_crm/features/attendance/dashboard_ring.dart';
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
  UserRole role = UserRole.employee,
  Size size = const Size(390, 800),
  double textScale = 1.0,
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
        locationGatewayProvider.overrideWithValue(FakeLocation()),
        biometricGatewayProvider.overrideWithValue(FakeBiometric()),
        canMarkAttendanceProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: AttendanceScreen()),
        ),
      ),
    ),
  );
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openTab(WidgetTester t, String label) async {
  final tab = find.descendant(of: find.byType(TabBar), matching: find.text(label));
  await t.ensureVisible(tab);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(tab);
  await _settle(t);
}

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.dragUntilVisible(f, find.byType(ListView).first, const Offset(0, -200));
  await t.pump(const Duration(milliseconds: 300));
}

Widget _calendarHarness(DateTime month, MonthData data, {String today = '2026-11-19', double width = 320}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AttendanceCalendar(
              month: month,
              data: data,
              today: today,
              onDayTap: (_) {},
            ),
          ),
        ),
      ),
    );

MonthDay _kind(String date, String kind, {Map<String, dynamic>? rec}) => MonthDay(
  date: date,
  type: 'working',
  status: 'present',
  kind: kind,
  record: rec == null ? null : AttendanceRecord.fromJson(rec),
);

void main() {
  group('calendar grid', () {
    test('leading blanks for a Monday-first week', () {
      expect(calendarLeadingBlanks(DateTime(2026, 6)), 0); // Mon 1 Jun
      expect(calendarLeadingBlanks(DateTime(2028, 2)), 1); // Tue 1 Feb
      expect(calendarLeadingBlanks(DateTime(2026, 1)), 3); // Thu 1 Jan
      expect(calendarLeadingBlanks(DateTime(2026, 11)), 6); // Sun 1 Nov
      expect(calendarLeadingBlanks(DateTime(2025, 12)), 0); // Mon 1 Dec
    });

    for (final c in [
      (DateTime(2026, 6), 0, 30),
      (DateTime(2028, 2), 1, 29),
      (DateTime(2026, 1), 3, 31),
      (DateTime(2026, 11), 6, 30),
    ]) {
      testWidgets('${c.$1.year}-${c.$1.month}: day 1 sits in column ${c.$2}', (t) async {
        await t.pumpWidget(_calendarHarness(c.$1, const MonthData(summary: MonthSummary(), days: [])));
        final key = dateKeyOf(c.$1);
        final first = find.byKey(ValueKey('day-$key'));
        expect(first, findsOneWidget);
        final grid = t.getRect(find.byKey(const ValueKey('attendance-calendar')));
        final colW = grid.width / 7;
        final cx = t.getCenter(first).dx - grid.left;
        expect((cx - (c.$2 + 0.5) * colW).abs(), lessThan(1.0));
        final last = '${key.substring(0, 8)}${c.$3.toString().padLeft(2, '0')}';
        expect(find.byKey(ValueKey('day-$last')), findsOneWidget);
        final past = '${key.substring(0, 8)}${(c.$3 + 1).toString().padLeft(2, '0')}';
        expect(find.byKey(ValueKey('day-$past')), findsNothing);
      });
    }

    testWidgets('every kind is drawn, and only today has the ring', (t) async {
      const kinds = [
        DayKind.full, DayKind.half, DayKind.missedCheckout, DayKind.inProgress,
        DayKind.holiday, DayKind.extra, DayKind.absent, DayKind.weeklyOff,
        DayKind.upcoming, DayKind.notTracked,
      ];
      final days = [
        for (var i = 0; i < kinds.length; i++)
          _kind('2026-11-${(i + 1).toString().padLeft(2, '0')}', kinds[i]),
      ];
      await t.pumpWidget(
        _calendarHarness(DateTime(2026, 11), MonthData(summary: const MonthSummary(), days: days), today: '2026-11-04'),
      );
      final painters = t
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<DayCellPainter>()
          .toList();
      for (final k in kinds) {
        expect(painters.any((p) => p.kind == k), isTrue, reason: k);
      }
      expect(painters.where((p) => p.isToday), hasLength(1));
      expect(painters.firstWhere((p) => p.isToday).kind, DayKind.inProgress);
    });

    testWidgets('a 320 px wide calendar does not overflow', (t) async {
      await t.pumpWidget(
        _calendarHarness(
          DateTime(2026, 11),
          MonthData(summary: const MonthSummary(), days: [
            _kind('2026-11-17', DayKind.full),
            _kind('2026-11-18', DayKind.missedCheckout,
                rec: recJson(date: '2026-11-18', inT: '10:00', late: 20, lateStatus: 'needs_note')),
          ]),
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('my month on the Today tab', () {
    MonthData sample() => MonthData(
      summary: const MonthSummary(workingDays: 12, fullDays: 7, halfDays: 2, absent: 1, late: 3, attendedValue: 8),
      days: [
        _kind('2026-11-16', DayKind.full, rec: recJson(date: '2026-11-16', inT: '10:02', outT: '19:01')),
        _kind('2026-11-17', DayKind.missedCheckout,
            rec: recJson(date: '2026-11-17', inT: '10:00')),
        _kind('2026-11-12', DayKind.half,
            rec: recJson(
              date: '2026-11-12',
              inT: '10:30',
              outT: '14:00',
              late: 30,
              early: 300,
              lateStatus: 'approved',
              lateNote: 'Bus broke down',
              comment: 'Fine, thanks',
              earlyStatus: 'needs_note',
            )),
        const MonthDay(date: '2026-11-08', type: 'holiday', status: 'off', kind: DayKind.holiday, holidayName: 'Diwali'),
      ],
    );

    testWidgets('shows the summary strip, the grid, the legend and no day list', (t) async {
      final service = FakeAttendanceService()..monthData = sample();
      await _pump(t, service: service);
      await _scrollTo(t, find.byType(AttendanceSummaryStrip));
      expect(find.text('Full'), findsWidgets);
      expect(find.text('Half'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('Late'), findsWidgets);
      expect(
        find.descendant(of: find.byType(AttendanceSummaryStrip), matching: find.text('7')),
        findsOneWidget,
      ); // full days
      expect(find.byType(AttendanceCalendar), findsOneWidget);
      expect(find.byType(AttendanceCalendarLegend), findsOneWidget);
      expect(find.text('MY MONTH'), findsNothing);
    });

    testWidgets('tapping a day opens its sheet with times, worked time, note and admin comment', (t) async {
      final service = FakeAttendanceService()
        ..monthData = MonthData(
          summary: const MonthSummary(),
          days: [
            _kind('2026-11-12', DayKind.half,
                rec: {
                  ...recJson(
                    date: '2026-11-12',
                    inT: '10:30',
                    outT: '14:00',
                    late: 30,
                    lateStatus: 'approved',
                    lateNote: 'Bus broke down',
                    comment: 'Fine, thanks',
                  ),
                  'worked_minutes': 210,
                }),
          ],
        );
      await _pump(t, service: service);
      final day = find.byKey(const ValueKey('day-2026-11-12'));
      await _scrollTo(t, day);
      await t.tap(day);
      await _settle(t);
      final sheet = find.byKey(const ValueKey('day-sheet'));
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Half day')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('10:30')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('14:00')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Worked 3 h 30 min')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('Late 30 min')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('Bus broke down')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('Fine, thanks')), findsOneWidget);
    });

    testWidgets('a holiday sheet shows the holiday name', (t) async {
      final service = FakeAttendanceService()..monthData = sample();
      await _pump(t, service: service);
      final day = find.byKey(const ValueKey('day-2026-11-08'));
      await _scrollTo(t, day);
      await t.tap(day);
      await _settle(t);
      expect(find.descendant(of: find.byKey(const ValueKey('day-sheet')), matching: find.text('Diwali')), findsOneWidget);
    });

    testWidgets('a missed check-out sheet says it counts as a half day until an admin adds the time', (t) async {
      final service = FakeAttendanceService()..monthData = sample();
      await _pump(t, service: service);
      final day = find.byKey(const ValueKey('day-2026-11-17'));
      await _scrollTo(t, day);
      await t.tap(day);
      await _settle(t);
      expect(find.text('Missed check-out'), findsOneWidget);
      expect(find.textContaining('counts as a half day until an admin adds the time'), findsOneWidget);
      expect(find.text('No check-out'), findsOneWidget);
    });

    testWidgets('a day needing a note carries a dot, and its sheet offers Write note', (t) async {
      final service = FakeAttendanceService()
        ..monthData = MonthData(summary: const MonthSummary(), days: [
          _kind('2026-11-12', DayKind.half,
              rec: recJson(date: '2026-11-12', inT: '10:30', outT: '14:00', late: 30, lateStatus: 'needs_note')),
        ]);
      await _pump(t, service: service);
      final day = find.byKey(const ValueKey('day-2026-11-12'));
      await _scrollTo(t, day);
      // The banner above the calendar and the dot on the day.
      expect(find.text('Please write a note'), findsOneWidget);
      await t.tap(day);
      await _settle(t);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('day-sheet')), matching: find.text('Write note')));
      await _settle(t);
      expect(find.text('Why were you late?'), findsOneWidget);
    });

    testWidgets('fits a 320 px phone at large text', (t) async {
      final service = FakeAttendanceService()
        ..today = todayJson(record: recJson(inT: '10:40', late: 40, lateStatus: 'needs_note'))
        ..monthData = sample();
      await _pump(t, service: service, size: const Size(320, 700), textScale: 1.3);
      await _scrollTo(t, find.byType(AttendanceCalendar));
      expect(t.takeException(), isNull);
    });
  });

  group('today card', () {
    testWidgets('status and key time follow the day', (t) async {
      final service = FakeAttendanceService();
      await _pump(t, service: service);
      expect(find.text('Not marked'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('today-key-time'))).data, '10:05');

      service.today = todayJson(record: recJson(inT: '10:02'));
      ProviderScope.containerOf(t.element(find.byType(AttendanceScreen))).invalidate(attendanceTodayProvider);
      await _settle(t);
      expect(find.text('Checked in'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('today-key-time'))).data, '10:02');

      service.today = todayJson(record: {...recJson(inT: '10:02', outT: '19:01'), 'worked_minutes': 539});
      ProviderScope.containerOf(t.element(find.byType(AttendanceScreen))).invalidate(attendanceTodayProvider);
      await _settle(t);
      expect(find.text('Day complete'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('today-key-time'))).data, '8 h 59 min');
      expect(find.byKey(const ValueKey('worked-time')), findsOneWidget);
    });

    testWidgets('the day type is an icon with a tooltip, not a row of text', (t) async {
      final service = FakeAttendanceService()..today = todayJson(dayType: 'weekly_off');
      await _pump(t, service: service);
      expect(find.byTooltip('Weekly off'), findsOneWidget);
      expect(find.text('Day type'), findsNothing);
      expect(find.text('Weekly off'), findsNothing);
    });

    testWidgets('no all-caps panel headers on attendance screens', (t) async {
      final service = FakeAttendanceService();
      await _pump(t, service: service, role: UserRole.admin);
      await _openTab(t, 'Settings');
      expect(find.text('ATTENDANCE SETTINGS'), findsNothing);
      expect(find.text('Attendance settings'), findsOneWidget);
    });
  });

  group('settings layout', () {
    for (final width in [320.0, 390.0, 800.0]) {
      testWidgets('fields pair up side by side at $width px', (t) async {
        final service = FakeAttendanceService();
        await _pump(t, service: service, role: UserRole.admin, size: Size(width, 900));
        await _openTab(t, 'Settings');
        double top(String label) => t.getTopLeft(find.text(label)).dy;
        double left(String label) => t.getTopLeft(find.text(label)).dx;
        for (final pair in [
          ('Arrival', 'Leave'),
          ('Grace (min)', 'Full day after (h)'),
          ('Radius (m)', 'Max accuracy (m)'),
          ('Latitude', 'Longitude'),
        ]) {
          await t.ensureVisible(find.text(pair.$1));
          expect(top(pair.$1), top(pair.$2), reason: '${pair.$1} | ${pair.$2}');
          expect(left(pair.$2), greaterThan(left(pair.$1)));
        }
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('seven tappable weekday chips, and the full day maps to minutes', (t) async {
      final service = FakeAttendanceService();
      await _pump(t, service: service, role: UserRole.admin, size: const Size(320, 900));
      await _openTab(t, 'Settings');
      for (var d = 1; d <= 7; d++) {
        expect(find.byKey(ValueKey('off-$d')), findsOneWidget);
      }
      // Saturday on, Sunday stays on.
      await t.ensureVisible(find.byKey(const ValueKey('off-6')));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey('off-6')));
      await t.pump();

      final hours = find.widgetWithText(TextField, '6');
      expect(hours, findsOneWidget);
      await t.enterText(hours, '7.5');
      await t.ensureVisible(find.text('Save settings'));
      await _settle(t);
      await t.tap(find.text('Save settings'));
      await _settle(t);
      expect(service.lastSaved, isNotNull);
      expect(service.lastSaved!.fullDayMinutes, 450);
      expect(service.lastSaved!.weeklyOff, [6, 7]);
    });

    testWidgets('a full day outside 1 to 24 hours is refused', (t) async {
      final service = FakeAttendanceService();
      await _pump(t, service: service, role: UserRole.admin);
      await _openTab(t, 'Settings');
      await t.enterText(find.widgetWithText(TextField, '6'), '30');
      await t.ensureVisible(find.text('Save settings'));
      await _settle(t);
      await t.tap(find.text('Save settings'));
      await _settle(t);
      expect(service.lastSaved, isNull);
      expect(find.textContaining('1 to 24 hours'), findsOneWidget);
    });
  });

  group('approvals: missed check-outs', () {
    testWidgets('lists them, opens the timing editor and counts them in the badge', (t) async {
      final service = FakeAttendanceService()
        ..missed = const [
          MissedCheckout(employeeId: 'e3', employeeName: 'Meera Shah', date: '2026-11-17', checkIn: '10:03'),
        ];
      await _pump(t, service: service, role: UserRole.admin);
      expect(find.text('1'), findsOneWidget); // the tab badge counts it

      await _openTab(t, 'Approvals');
      expect(find.text('Missed check-outs'), findsOneWidget);
      expect(find.text('Meera Shah'), findsOneWidget);
      expect(find.textContaining('in at 10:03'), findsOneWidget);
      expect(find.text('Notes to review'), findsNothing);

      await t.tap(find.byKey(const ValueKey('missed-e3-2026-11-17')));
      await _settle(t);
      // The existing timing editor, with the check-in filled in.
      expect(find.text('Check-in'), findsOneWidget);
      expect(find.text('Check-out'), findsOneWidget);
      expect(find.textContaining('10:03'), findsWidgets);
    });
  });

  group('admin edit from the My Month day sheet', () {
    MonthData month() => MonthData(
      summary: const MonthSummary(workingDays: 12),
      days: [
        _kind('2026-11-16', DayKind.full, rec: recJson(date: '2026-11-16', inT: '10:02', outT: '19:01')),
        _kind('2026-11-18', DayKind.absent),
        _kind('2026-11-19', DayKind.inProgress, rec: recJson(date: '2026-11-19', inT: '10:00')),
        _kind('2026-11-25', DayKind.upcoming),
      ],
    );

    Future<void> openDay(WidgetTester t, String date) async {
      final day = find.byKey(ValueKey('day-$date'));
      await _scrollTo(t, day);
      await t.tap(day);
      await _settle(t);
      expect(find.byKey(const ValueKey('day-sheet')), findsOneWidget);
    }

    final edit = find.byKey(const ValueKey('day-edit-times'));

    testWidgets('an admin sees Edit times on a past day and it opens the existing editor, saving for that date', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service, role: UserRole.admin);
      await openDay(t, '2026-11-16');
      expect(edit, findsOneWidget);
      expect(find.descendant(of: edit, matching: find.text('Edit times')), findsOneWidget);
      await t.tap(edit);
      await _settle(t);
      // The sheet closed and the existing timing editor opened with the times.
      expect(find.byKey(const ValueKey('day-sheet')), findsNothing);
      expect(find.text('Check-in'), findsOneWidget);
      expect(find.text('Check-out'), findsOneWidget);
      expect(find.textContaining('10:02'), findsWidgets);
      await t.enterText(find.byType(TextField), 'Forgot to mark in time');
      await t.tap(find.text('Save'));
      await _settle(t);
      expect(service.editCalls, hasLength(1));
      expect(service.editCalls.single.employeeId, 'emp1'); // the admin's own record
      expect(service.editCalls.single.date, '2026-11-16');
      expect(service.editCalls.single.checkIn, '10:02');
      expect(service.editCalls.single.reason, 'Forgot to mark in time');
      expect(find.text('Check-in'), findsNothing); // closed after saving
    });

    testWidgets('a past day with no record offers Add timing', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service, role: UserRole.admin);
      await openDay(t, '2026-11-18');
      expect(find.descendant(of: edit, matching: find.text('Add timing')), findsOneWidget);
    });

    testWidgets('an admin can also edit today', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service, role: UserRole.admin);
      await openDay(t, '2026-11-19');
      expect(edit, findsOneWidget);
    });

    testWidgets('a future day never has an Edit action, even for an admin', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service, role: UserRole.admin);
      await openDay(t, '2026-11-25');
      expect(edit, findsNothing);
    });

    testWidgets('a non-admin never sees the action', (t) async {
      final service = FakeAttendanceService()..monthData = month();
      await _pump(t, service: service);
      await openDay(t, '2026-11-16');
      expect(edit, findsNothing);
      expect(find.text('Edit times'), findsNothing);
      expect(find.text('Add timing'), findsNothing);
    });

    test('canEditDayTimes: today and past only', () {
      expect(canEditDayTimes('2026-11-18', '2026-11-19'), isTrue);
      expect(canEditDayTimes('2026-11-19', '2026-11-19'), isTrue);
      expect(canEditDayTimes('2026-11-20', '2026-11-19'), isFalse);
    });
  });

  group('profile attendance pill', () {
    testWidgets('the summary card leads with the same 64 x 44 pill, display-only without a handler', (t) async {
      final service = FakeAttendanceService()
        ..monthData = MonthData(summary: const MonthSummary(workingDays: 10, present: 8), days: const []);
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            attendanceServiceProvider.overrideWithValue(service),
            authProvider.overrideWith(() => _Auth(UserRole.admin)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SingleChildScrollView(child: AttendanceSummaryCard())),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final pill = find.byKey(const ValueKey('attendance-pill-badge'));
      expect(t.getSize(pill), const Size(kAttendancePillWidth, kAttendancePillHeight));
      expect(find.byKey(const ValueKey('attendance-pill-tap')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('with a handler (own profile) tapping the pill opens Attendance and marks nothing', (t) async {
      final service = FakeAttendanceService()..monthData = MonthData(summary: const MonthSummary(), days: const []);
      var opened = 0;
      await t.pumpWidget(
        ProviderScope(
          overrides: [attendanceServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: SingleChildScrollView(child: AttendanceSummaryCard(onOpenAttendance: () => opened++))),
          ),
        ),
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('attendance-pill-tap')));
      expect(opened, 1);
      expect(service.markCalls, isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('typography', () {
    test('display is Manrope and text is Schibsted Grotesk', () {
      expect(AppTypography.display, 'Manrope');
      expect(AppTypography.text, 'SchibstedGrotesk');
      expect(AppTypography.pageTitle.fontFamily, 'Manrope');
      expect(AppTypography.pageTitle.fontWeight, FontWeight.w700);
      expect(AppTypography.pageTitle.fontSize, inInclusiveRange(32, 34));
      expect(AppTypography.sectionTitle.fontFamily, 'Manrope');
      expect(AppTypography.sectionTitle.fontWeight, FontWeight.w600);
      expect(AppTypography.heroNumber.fontSize, inInclusiveRange(40, 48));
      expect(AppTypography.heroNumber.fontFamily, 'Manrope');
      expect(AppTypography.heroNumber.fontWeight, FontWeight.w700);
      expect(AppTypography.bodyPrimary.fontFamily, 'SchibstedGrotesk');
      expect(AppTypography.bodyPrimary.fontWeight, FontWeight.w400);
      expect(AppTypography.fieldLabel.fontSize, 13);
      expect(AppTypography.fieldLabel.fontWeight, FontWeight.w600);
      expect(AppTypography.caption.fontSize, 12);
      expect(AppTypography.tableCellNumeric.fontFeatures, isNotEmpty);
      expect(AppTheme.light.textTheme.bodyMedium?.fontFamily, 'SchibstedGrotesk');
    });
  });
}
