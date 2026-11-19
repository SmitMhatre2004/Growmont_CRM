import 'dart:async';

import 'package:growmont_crm/features/attendance/attendance_models.dart';
import 'package:growmont_crm/features/attendance/attendance_service.dart';
import 'package:growmont_crm/features/attendance/device_gateways.dart';

Map<String, dynamic> recJson({
  String date = '2026-11-19',
  String? inT,
  String? outT,
  int late = 0,
  int early = 0,
  String lateStatus = 'none',
  String earlyStatus = 'none',
  String? lateNote,
  String? comment,
}) => {
  'date': date,
  'employee_id': 'emp1',
  'shift': {'arrival': '10:00', 'leave': '19:00', 'grace_minutes': 15},
  'check_in_local': inT,
  'check_out_local': outT,
  'late_minutes': late,
  'early_minutes': early,
  'late': {'status': lateStatus, 'note': lateNote, 'comment': comment},
  'early': {'status': earlyStatus},
};

Map<String, dynamic> todayJson({
  Map<String, dynamic>? record,
  String time = '10:05',
  bool configured = true,
  String dayType = 'working',
}) => {
  'date': '2026-11-19',
  'time': time,
  'configured': configured,
  'settings': {
    'arrival': '10:00',
    'leave': '19:00',
    'grace_minutes': 15,
    'radius_m': 30,
    'max_accuracy_m': 25,
    'office': {'lat': 18.5, 'lng': 73.8},
  },
  'day': {'type': dayType},
  'record': record,
};

MonthData monthWith(List<MonthDay> days, {MonthSummary? summary}) =>
    MonthData(summary: summary ?? const MonthSummary(), days: days);

MonthDay dayWith(Map<String, dynamic> rec, {String status = 'present'}) =>
    MonthDay(
      date: rec['date'] as String,
      type: 'working',
      status: status,
      record: AttendanceRecord.fromJson(rec),
    );

class FakeAttendanceService implements AttendanceService {
  Map<String, dynamic> today = todayJson();
  Object? todayError;
  Object? markError;
  Completer<void>? markGate;
  MonthData monthData = monthWith(const []);
  Object? monthError;
  List<ApprovalItem> approvals = [];
  List<MissedCheckout> missed = [];
  Object? reviewError;

  /// What a successful mark writes onto [today].
  Map<String, dynamic> Function(String action)? onMark;

  AttendanceSettings? lastSaved;
  final markCalls = <MarkPayload>[];
  final notes = <String>[];
  var monthCalls = 0;

  /// The employee id of every month() call (null = the signed-in person).
  final monthEmployeeIds = <String?>[];
  var todayCalls = 0;
  var reviewCalls = 0;

  @override
  Future<TodayInfo> getToday() async {
    todayCalls++;
    if (todayError != null) throw todayError!;
    return TodayInfo.fromJson(today);
  }

  @override
  Future<MarkResult> mark(MarkPayload payload) async {
    markCalls.add(payload);
    if (markGate != null) await markGate!.future;
    if (markError != null) throw markError!;
    final rec =
        onMark?.call(payload.action) ??
        recJson(inT: '10:05', outT: payload.action == 'out' ? '19:00' : null);
    today = {...today, 'record': rec};
    return MarkResult(record: AttendanceRecord.fromJson(rec), already: false);
  }

  @override
  Future<AttendanceRecord> submitNote({
    required String date,
    required String kind,
    required String note,
  }) async {
    notes.add('$date|$kind|$note');
    return AttendanceRecord.fromJson(recJson(date: date));
  }

  @override
  Future<MonthData> month(String m, {String? employeeId}) async {
    monthCalls++;
    monthEmployeeIds.add(employeeId);
    if (monthError != null) throw monthError!;
    return monthData;
  }

  @override
  Future<TeamDay> teamDay(String date) async => TeamDay.fromJson({
    'date': date,
    'day': {'type': 'working'},
    'rows': [
      {
        'employee_id': 'emp1',
        'name': 'Asha Rao',
        'status': 'present',
        'record': recJson(inT: '10:02', outT: '19:01'),
      },
    ],
  });

  @override
  Future<List<TeamMonthRow>> teamMonth(String m) async => [
    TeamMonthRow(
      employeeId: 'emp1',
      name: 'Asha Rao',
      summary: const MonthSummary(workingDays: 10, present: 9, rank: 1, rankedOf: 3, percent: 90, stars: 4.5),
    ),
  ];

  @override
  Future<ApprovalsData> listApprovals() async =>
      ApprovalsData(items: approvals, missedCheckouts: missed);

  @override
  Future<void> review({
    required String employeeId,
    required String date,
    required String kind,
    required String decision,
    String? comment,
  }) async {
    reviewCalls++;
    if (reviewError != null) {
      final e = reviewError!;
      reviewError = null;
      approvals = [];
      throw e;
    }
    approvals = [];
  }

  @override
  Future<AttendanceRecord?> adminEdit({
    required String employeeId,
    required String date,
    required String? checkIn,
    required String? checkOut,
    required String reason,
  }) async {
    editCalls.add((
      employeeId: employeeId,
      date: date,
      checkIn: checkIn,
      checkOut: checkOut,
      reason: reason,
    ));
    return null;
  }

  /// Every attendanceAdminEdit the app made.
  final List<({String employeeId, String date, String? checkIn, String? checkOut, String reason})> editCalls = [];

  @override
  Future<AttendanceSettings> getSettings() async => const AttendanceSettings(
    office: LatLng(18.5, 73.8),
    radiusM: 10,
  );

  @override
  Future<AttendanceSettings> saveSettings(AttendanceSettings settings) async {
    lastSaved = settings;
    return settings;
  }

  @override
  Future<List<Holiday>> listHolidays(int year) async => const [
    Holiday(date: '2026-11-08', name: 'Diwali'),
  ];

  @override
  Future<void> setHoliday(String date, String name) async {}

  @override
  Future<void> removeHoliday(String date) async {}
}

class FakeLocation implements LocationGateway {
  LocationAccess access = LocationAccess.granted;
  bool timeout = false;
  Object? accessError;
  GpsFix fix = const GpsFix(
    lat: 18.5,
    lng: 73.8,
    accuracyM: 8,
    isMocked: false,
    positionAgeMs: 300,
  );

  /// Metres reported between the fix and the office.
  double distance = 5;
  var accessCalls = 0;
  var checkCalls = 0;
  var watchStarts = 0;
  var watchCancels = 0;
  StreamController<GpsFix>? _live;

  /// Pushes a live reading to whoever is watching.
  void emit(GpsFix fix) => _live?.add(fix);
  bool get watching => _live != null && _live!.hasListener;

  @override
  Future<LocationAccess> checkAccess() async {
    checkCalls++;
    return access;
  }

  @override
  Stream<GpsFix> watchFix({int distanceFilterM = 5}) {
    _live = StreamController<GpsFix>(
      onListen: () => watchStarts++,
      onCancel: () => watchCancels++,
    );
    return _live!.stream;
  }
  var fixCalls = 0;
  var openedAppSettings = 0;
  var openedLocationSettings = 0;

  @override
  Future<LocationAccess> ensureAccess() async {
    accessCalls++;
    if (accessError != null) throw accessError!;
    return access;
  }

  @override
  Future<GpsFix> currentFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    fixCalls++;
    if (this.timeout) throw TimeoutException('gps');
    return fix;
  }

  @override
  double distanceM(double a, double b, double c, double d) => distance;

  @override
  Future<void> openAppSettings() async => openedAppSettings++;

  @override
  Future<void> openLocationSettings() async => openedLocationSettings++;
}

class FakeBiometric implements BiometricGateway {
  BiometricResult result = BiometricResult.passed;
  Object? error;
  var calls = 0;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}
