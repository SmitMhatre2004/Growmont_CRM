import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/cloud_callables.dart';
import 'package:growmont_crm/features/attendance/attendance_models.dart';
import 'package:growmont_crm/features/attendance/attendance_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Contract between the app and the real server.
///
/// fixtures/attendance_contract.json is what the REAL attendance handlers
/// returned against the Firestore emulator (functions/test/attendance.emulator
/// .test.js writes it). fixtures/attendance_requests.json is the request the
/// app must send for each callable; functions/test/attendance.test.js feeds
/// the very same file to the real handlers. Neither side uses a fake of the
/// other here.
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final responses = _load('attendance_contract.json');
  final requests = _load('attendance_requests.json');

  const byCallable = {
    'attendanceGetToday': 'today_configured',
    'attendanceMark': 'mark_in',
    'attendanceSubmitNote': 'submit_note',
    'attendanceMonth': 'month_self',
    'attendanceTeamDay': 'team_day',
    'attendanceTeamMonth': 'team_month',
    'attendanceListApprovals': 'approvals',
    'attendanceReview': 'review',
    'attendanceAdminEdit': 'admin_edit',
    'attendanceGetSettings': 'get_settings',
    'attendanceSaveSettings': 'save_settings',
    'attendanceListHolidays': 'list_holidays',
    'attendanceSetHoliday': 'set_holiday',
    'attendanceRemoveHoliday': 'remove_holiday',
  };

  final sent = <String, Map<String, dynamic>>{};

  CallableAttendanceService serviceReturning(
    Map<String, dynamic> Function(String name) respond, {
    int status = 200,
  }) {
    final client = MockClient((http.Request req) async {
      final name = req.url.pathSegments.last;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      sent[name] = Map<String, dynamic>.from(body['data'] as Map);
      return http.Response(jsonEncode(respond(name)), status);
    });
    return CallableAttendanceService(
      CloudCallables(
        client: client,
        idToken: () async => 'token',
        projectId: 'demo-growmont',
      ),
    );
  }

  CallableAttendanceService ok() => serviceReturning(
    (name) => {'result': responses[byCallable[name]]},
  );

  group('responses captured from the real server parse correctly', () {
    test('getToday: unconfigured and configured', () async {
      final unconfigured = TodayInfo.fromJson(
        responses['today_unconfigured'] as Map<String, dynamic>,
      );
      expect(unconfigured.configured, isFalse);
      expect(unconfigured.settings.office, isNull);
      expect(unconfigured.dayType, 'working');

      final t = await ok().getToday();
      expect(t.date, '2026-11-18');
      expect(t.time, '10:00');
      expect(t.configured, isTrue);
      expect(t.settings.office!.lat, 18.5204);
      expect(t.settings.radiusM, 50);
      expect(t.settings.maxAccuracyM, 25);
      expect(t.settings.graceMinutes, 15);
      expect(t.record, isNull);
      expect(t.holidayName, isNull);
    });

    test('mark: record fields, late object, geo and already flag', () async {
      final r = await ok().mark(
        MarkPayload(
          action: 'in',
          lat: 18.5204,
          lng: 73.8567,
          accuracyM: 8.5,
          isMocked: false,
          positionAgeMs: 1500,
          deviceId: 'd' * 32,
          biometricPassed: true,
        ),
      );
      expect(r.already, isFalse);
      expect(r.record.employeeId, 'emp1');
      expect(r.record.checkInLocal, '10:00');
      expect(r.record.checkOutLocal, isNull);
      expect(r.record.arrival, '10:00');
      expect(r.record.leave, '19:00');
      expect(r.record.graceMinutes, 15);
      expect(r.record.late.status, 'none');
      expect(r.record.checkInGeo!.distanceM, 0);
      expect(r.record.checkInGeo!.accuracyM, 8);
      expect(r.record.source, 'self');

      final late = AttendanceRecord.fromJson(
        (responses['mark_in_late'] as Map)['record'],
      );
      expect(late.lateMinutes, 60);
      expect(late.late.needsNote, isTrue);
      expect(late.hasNeedsNote, isTrue);
      expect(late.needsReview, isFalse);

      final early = AttendanceRecord.fromJson(
        (responses['mark_out_early'] as Map)['record'],
      );
      expect(early.earlyMinutes, greaterThan(0));
      expect(early.early.needsNote, isTrue);
      expect(early.checkOutLocal, isNotNull);
      expect(early.workedMinutes, isNotNull);
    });

    test('submit note and review: pending and decided review objects', () async {
      final noted = AttendanceRecord.fromJson(
        (responses['submit_note'] as Map)['record'],
      );
      expect(noted.late.isPending, isTrue);
      expect(noted.late.note, 'Bus broke down');
      expect(noted.needsReview, isTrue);

      final decided = AttendanceRecord.fromJson(
        (responses['review'] as Map)['record'],
      );
      expect(decided.late.status, 'approved');
      expect(decided.late.isDecided, isTrue);
      expect(decided.late.decidedByName, 'Asha Admin');
      expect(decided.late.comment, 'ok');
    });

    test('month: summary numbers (int percent, whole-number stars) and days',
        () async {
      final m = await ok().month('2026-11');
      final s = m.summary;
      expect(s.workingDays, 1);
      expect(s.present, 1);
      expect(s.absent, 0);
      expect(s.extraDays, 0);
      expect(s.percent, 100);
      expect(s.stars, 5.0);
      expect(s.isRated, isTrue);
      expect(s.rank, 1);
      expect(s.rankedOf, 3);
      expect(m.days, hasLength(30));
      expect(m.days.first.type, 'weekly_off');
      expect(m.days.first.status, 'off');
      final today = m.days.firstWhere((d) => d.date == '2026-11-18');
      expect(today.status, 'present');
      expect(today.record!.checkInLocal, '10:00');
      expect(
        m.days.map((d) => d.status).toSet().difference(
          {'present', 'absent', 'off', 'upcoming'},
        ),
        isEmpty,
      );
    });

    test('month of someone else with a rejected-free summary keeps excused',
        () {
      final m = MonthData.fromJson(
        responses['month_other_as_admin'] as Map<String, dynamic>,
      );
      expect(m.summary.excused, 1);
      expect(m.summary.late, 0);
    });

    test('team day rows, team month ranking, approvals, holidays', () async {
      final day = await ok().teamDay('2026-11-18');
      expect(day.dayType, 'working');
      expect(day.rows.map((r) => r.employeeId), contains('emp1'));
      final emp1 = day.rows.firstWhere((r) => r.employeeId == 'emp1');
      expect(emp1.status, 'present');
      expect(emp1.record!.checkOutLocal, '19:05');
      expect(day.rows.firstWhere((r) => r.employeeId == 'admin1').status,
          'absent');

      final team = await ok().teamMonth('2026-11');
      expect(team.map((r) => r.summary.rank), [1, 1, 3]);
      expect(team.first.summary.rankedOf, 3);

      final items = (await ok().listApprovals()).items;
      expect(items, hasLength(1));
      expect(items.single.employeeId, 'emp2');
      expect(items.single.kind, 'late');
      expect(items.single.minutes, 60);
      expect(items.single.expected, '10:00');
      expect(items.single.actual, '11:00');
      expect(items.single.note, 'Bus broke down');

      final holidays = await ok().listHolidays(2026);
      expect(holidays.single.date, '2026-11-20');
      expect(holidays.single.name, 'Diwali');
    });

    test('settings use weekly_off, not the history', () async {
      final s = await ok().getSettings();
      expect(s.weeklyOff, [7]);
      expect(s.office!.lng, 73.8567);
      expect(s.radiusM, 50);
      final saved = await ok().saveSettings(s);
      expect(saved.weeklyOff, [7]);
      // And the history alone is understood too.
      final fromHistory = AttendanceSettings.fromJson({
        'weekly_off_history': [
          {'from': '2026-01-01', 'days': [7]},
          {'from': '2026-11-01', 'days': [6, 7]},
        ],
      });
      expect(fromHistory.weeklyOff, [6, 7]);
    });

    test('admin edit returns a record, delete returns null', () async {
      final edited = await ok().adminEdit(
        employeeId: 'emp1',
        date: '2026-11-17',
        checkIn: '09:30',
        checkOut: '18:00',
        reason: 'Forgot to mark',
      );
      expect(edited!.source, 'admin');
      expect(edited.adminEdited, isTrue);
      expect(edited.checkInGeo, isNull);

      final deleting = serviceReturning(
        (_) => {'result': responses['admin_delete']},
      );
      expect(
        await deleting.adminEdit(
          employeeId: 'emp1',
          date: '2026-11-17',
          checkIn: null,
          checkOut: null,
          reason: 'Mistake',
        ),
        isNull,
      );
    });

    test('set, remove (existing and missing) and note calls do not throw',
        () async {
      final s = ok();
      await s.setHoliday('2026-11-20', 'Diwali');
      await s.removeHoliday('2026-11-20');
      final missing = serviceReturning(
        (_) => {'result': responses['remove_holiday_missing']},
      );
      await missing.removeHoliday('2026-11-21');
      final n = await s.submitNote(
        date: '2026-11-18',
        kind: 'late',
        note: 'Bus broke down',
      );
      expect(n.late.isPending, isTrue);
    });
  });

  group('requests the app sends match what the server accepts', () {
    test('every callable sends exactly the agreed JSON', () async {
      final s = ok();
      sent.clear();
      await s.getToday();
      await s.mark(
        MarkPayload(
          action: 'in',
          lat: 18.5204,
          lng: 73.8567,
          accuracyM: 8.5,
          isMocked: false,
          positionAgeMs: 1500,
          deviceId: '0123456789abcdef0123456789abcdef',
          biometricPassed: true,
        ),
      );
      await s.submitNote(date: '2026-11-18', kind: 'late', note: 'Bus broke down');
      await s.month('2026-11');
      await s.teamDay('2026-11-18');
      await s.teamMonth('2026-11');
      await s.listApprovals();
      await s.review(
        employeeId: 'emp2',
        date: '2026-11-18',
        kind: 'late',
        decision: 'approved',
        comment: ' ok ',
      );
      await s.adminEdit(
        employeeId: 'emp1',
        date: '2026-11-17',
        checkIn: '09:30',
        checkOut: null,
        reason: 'Forgot to mark',
      );
      await s.getSettings();
      await s.saveSettings(
        const AttendanceSettings(
          office: LatLng(18.5204, 73.8567),
          radiusM: 50,
          maxAccuracyM: 25,
          weeklyOff: [6, 7],
        ),
      );
      await s.listHolidays(2026);
      await s.setHoliday('2026-11-20', 'Diwali');
      await s.removeHoliday('2026-11-20');

      for (final name in byCallable.keys) {
        expect(sent[name], requests[name], reason: name);
      }
    });

    test('month for another employee sends employee_id', () async {
      sent.clear();
      await ok().month('2026-11', employeeId: 'emp2');
      expect(sent['attendanceMonth'], requests['attendanceMonthOther']);
    });

    test('a cleared office is sent as null, never omitted', () {
      expect(
        const AttendanceSettings().toPayload(),
        containsPair('office', null),
      );
    });
  });

  group('error details survive the HTTP callable layer', () {
    BackendException? caught;

    Future<void> failWith(Map<String, dynamic> error, {int status = 400}) async {
      final s = serviceReturning((_) => {'error': error}, status: status);
      try {
        await s.getToday();
        fail('should have thrown');
      } on BackendException catch (e) {
        caught = e;
      }
    }

    test('outside_radius keeps code, distance and radius', () async {
      await failWith(responses['error_outside_radius'] as Map<String, dynamic>);
      expect(caught!.code, 'outside_radius');
      expect(caught!.details['distance_m'], 53329.1);
      expect(caught!.details['radius_m'], 50);
      final text = attendanceErrorMessage(caught!);
      expect(text, contains('53329 m'));
      expect(text, contains('50 m'));
    });

    test('every documented code has its own wording, not the raw server text',
        () async {
      const codes = [
        'not_configured', 'outside_radius', 'poor_accuracy', 'mock_location',
        'stale_location', 'biometric_required', 'device_in_use', 'shift_over',
        'not_checked_in', 'too_soon', 'locked_by_admin', 'already_decided',
        'note_not_allowed', 'not_pending', 'self_review',
      ];
      for (final code in codes) {
        await failWith({
          'status': 'FAILED_PRECONDITION',
          'message': 'RAW SERVER TEXT',
          'details': {'code': code},
        });
        expect(caught!.code, code);
        expect(attendanceErrorMessage(caught!), isNot(contains('RAW')),
            reason: code);
      }
    });

    test('invalid_input shows the server sentence', () async {
      await failWith({
        'status': 'INVALID_ARGUMENT',
        'message': 'Radius must be a whole number from 10 to 500.',
        'details': {'code': 'invalid_input'},
      });
      expect(caught!.code, 'invalid_input');
      expect(attendanceErrorMessage(caught!), contains('Radius must be'));
    });

    test('admin_only / inactive (permission-denied) still show a sentence',
        () async {
      await failWith({
        'status': 'PERMISSION_DENIED',
        'message': 'Only administrators can do this.',
        'details': {'code': 'admin_only'},
      }, status: 403);
      expect(caught!.code, 'admin_only');
      expect(attendanceErrorMessage(caught!), 'Only administrators can do this.');
    });

    test('an error without details has no code (offline-style retry path)',
        () async {
      await failWith({'status': 'INTERNAL', 'message': 'INTERNAL'});
      expect(caught!.code, isNull);
    });
  });
}
