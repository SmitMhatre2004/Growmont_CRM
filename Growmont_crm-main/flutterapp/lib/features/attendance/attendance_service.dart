import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/firebase/cloud_callables.dart';
import 'attendance_models.dart';

/// Everything the attendance screens ask of the server. Screens depend on
/// this interface so tests can supply a fake.
abstract class AttendanceService {
  Future<TodayInfo> getToday();
  Future<MarkResult> mark(MarkPayload payload);
  Future<AttendanceRecord> submitNote({
    required String date,
    required String kind,
    required String note,
  });
  Future<MonthData> month(String month, {String? employeeId});
  Future<TeamDay> teamDay(String date);
  Future<List<TeamMonthRow>> teamMonth(String month);
  Future<ApprovalsData> listApprovals();
  Future<void> review({
    required String employeeId,
    required String date,
    required String kind,
    required String decision,
    String? comment,
  });
  Future<AttendanceRecord?> adminEdit({
    required String employeeId,
    required String date,
    required String? checkIn,
    required String? checkOut,
    required String reason,
  });
  Future<AttendanceSettings> getSettings();
  Future<AttendanceSettings> saveSettings(AttendanceSettings settings);
  Future<List<Holiday>> listHolidays(int year);
  Future<void> setHoliday(String date, String name);
  Future<void> removeHoliday(String date);
}

class CallableAttendanceService implements AttendanceService {
  CallableAttendanceService(this._callables);

  final CloudCallables _callables;

  @override
  Future<TodayInfo> getToday() async =>
      TodayInfo.fromJson(await _callables.call('attendanceGetToday'));

  @override
  Future<MarkResult> mark(MarkPayload payload) async {
    final r = await _callables.call('attendanceMark', payload.toJson());
    return MarkResult(
      record: AttendanceRecord.fromJson(r['record']),
      already: r['already'] == true,
    );
  }

  @override
  Future<AttendanceRecord> submitNote({
    required String date,
    required String kind,
    required String note,
  }) async {
    final r = await _callables.call('attendanceSubmitNote', {
      'date': date,
      'kind': kind,
      'note': note,
    });
    return AttendanceRecord.fromJson(r['record']);
  }

  @override
  Future<MonthData> month(String month, {String? employeeId}) async =>
      MonthData.fromJson(
        await _callables.call('attendanceMonth', {
          'month': month,
          'employee_id': ?employeeId,
        }),
      );

  @override
  Future<TeamDay> teamDay(String date) async => TeamDay.fromJson(
    await _callables.call('attendanceTeamDay', {'date': date}),
  );

  @override
  Future<List<TeamMonthRow>> teamMonth(String month) async => parseTeamMonth(
    await _callables.call('attendanceTeamMonth', {'month': month}),
  );

  @override
  Future<ApprovalsData> listApprovals() async =>
      parseApprovals(await _callables.call('attendanceListApprovals'));

  @override
  Future<void> review({
    required String employeeId,
    required String date,
    required String kind,
    required String decision,
    String? comment,
  }) async {
    await _callables.call('attendanceReview', {
      'employee_id': employeeId,
      'date': date,
      'kind': kind,
      'decision': decision,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    });
  }

  @override
  Future<AttendanceRecord?> adminEdit({
    required String employeeId,
    required String date,
    required String? checkIn,
    required String? checkOut,
    required String reason,
  }) async {
    final r = await _callables.call('attendanceAdminEdit', {
      'employee_id': employeeId,
      'date': date,
      'check_in': checkIn,
      'check_out': checkOut,
      'reason': reason,
    });
    return AttendanceRecord.maybe(r['record']);
  }

  @override
  Future<AttendanceSettings> getSettings() async => AttendanceSettings.fromJson(
    await _callables.call('attendanceGetSettings'),
  );

  @override
  Future<AttendanceSettings> saveSettings(AttendanceSettings settings) async =>
      AttendanceSettings.fromJson(
        await _callables.call('attendanceSaveSettings', settings.toPayload()),
      );

  @override
  Future<List<Holiday>> listHolidays(int year) async => parseHolidays(
    await _callables.call('attendanceListHolidays', {'year': year}),
  );

  @override
  Future<void> setHoliday(String date, String name) async {
    await _callables.call('attendanceSetHoliday', {'date': date, 'name': name});
  }

  @override
  Future<void> removeHoliday(String date) async {
    await _callables.call('attendanceRemoveHoliday', {'date': date});
  }
}

/// A random id generated once and kept on the device, so the server can tell
/// when one phone is used to mark for two different people on the same day.
class DeviceIdStore {
  DeviceIdStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const key = 'attendance_device_id';

  final Future<SharedPreferences> Function() _prefs;
  String? _cached;

  Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await _prefs();
    var id = prefs.getString(key);
    if (id == null || id.length < 16) {
      final rng = math.Random.secure();
      id = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString(key, id);
    }
    return _cached = id;
  }
}

/// Plain-language text for every failure the attendance callables report.
/// Falls back to the server's own message, which is written for users.
String attendanceErrorMessage(Object error) {
  if (error is! BackendException) {
    return 'Something went wrong. Please try again.';
  }
  final d = error.details;
  String whole(Object? v) => v is num ? v.round().toString() : '?';
  switch (error.code) {
    case 'not_configured':
      return 'Attendance is not set up yet. Ask an admin to set the office '
          'location first.';
    case 'outside_radius':
      return 'You are ${whole(d['distance_m'])} m from the office, but you '
          'must be within ${whole(d['radius_m'])} m. Move closer and try again.';
    case 'poor_accuracy':
      return 'Your GPS signal is too weak (${whole(d['accuracy_m'])} m '
          'accuracy). Step outside or near a window and try again.';
    case 'mock_location':
      return 'A fake or mock location was detected. Turn it off and try '
          'again.';
    case 'stale_location':
      return 'Your location reading was too old. Please try again.';
    case 'biometric_required':
      return 'Fingerprint or face confirmation is required to mark '
          'attendance.';
    case 'device_in_use':
      return 'This phone has already been used to mark attendance for '
          'someone else today.';
    case 'shift_over':
      return 'The working day is over, so you can no longer check in.';
    case 'not_checked_in':
      return 'You have not checked in today, so there is nothing to check '
          'out of.';
    case 'too_soon':
      return 'You checked in less than a minute ago. Wait a moment before '
          'checking out.';
    case 'locked_by_admin':
      return 'An admin has edited today\'s times, so they can no longer be '
          'changed here.';
    case 'already_decided':
      return 'This early check-out has already been reviewed, so it cannot '
          'be changed.';
    case 'note_not_allowed':
      return 'A note cannot be added or changed for this item any more.';
    case 'not_pending':
      return 'This item was already reviewed. The list has been refreshed.';
    case 'self_review':
      return 'You cannot review your own item while another admin can. Ask '
          'another admin.';
    case 'invalid_input':
      return error.message.isNotEmpty
          ? error.message
          : 'Some of the details are not valid. Please check and try again.';
    default:
      return error.message;
  }
}
