/// Plain data classes for the attendance callables.
///
/// The server decides every time, date and status; these classes only carry
/// its strings. Parsing is deliberately forgiving: a missing or oddly typed
/// field becomes null/0 rather than throwing, so one bad field cannot blank a
/// whole screen.
library;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(Object? v) =>
    v is List ? v.whereType<Map>().map(_map).toList() : const [];

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _intOrNull(Object? v) {
  if (v is num && v.isFinite) return v.round();
  return null;
}

int _int(Object? v) => _intOrNull(v) ?? 0;

int? _hhmm(String v) {
  final p = v.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  return h == null || m == null ? null : h * 60 + m;
}

double? _dblOrNull(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

int? _firstInt(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = _intOrNull(m[k]);
    if (v != null) return v;
  }
  return null;
}

/// 'none' | 'needs_note' | 'pending' | 'approved' | 'rejected'.
class ReviewInfo {
  const ReviewInfo({
    this.status = 'none',
    this.note,
    this.decidedByName,
    this.comment,
  });

  final String status;
  final String? note;
  final String? decidedByName;
  final String? comment;

  bool get needsNote => status == 'needs_note';
  bool get isPending => status == 'pending';
  bool get isDecided => status == 'approved' || status == 'rejected';

  factory ReviewInfo.fromJson(Object? json) {
    final m = _map(json);
    return ReviewInfo(
      status: _str(m['status']) ?? 'none',
      note: _str(m['note']),
      decidedByName: _str(m['decided_by_name']),
      comment: _str(m['comment']),
    );
  }
}

class GeoStamp {
  const GeoStamp({this.distanceM, this.accuracyM});

  final double? distanceM;
  final double? accuracyM;

  factory GeoStamp.fromJson(Object? json) {
    final m = _map(json);
    return GeoStamp(
      distanceM: _dblOrNull(m['distance_m']),
      accuracyM: _dblOrNull(m['accuracy_m']),
    );
  }
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.date,
    this.employeeId,
    this.employeeName,
    this.arrival,
    this.leave,
    this.graceMinutes,
    this.fullDayMinutes,
    this.checkInLocal,
    this.checkOutLocal,
    this.workedMinutes,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.late = const ReviewInfo(),
    this.early = const ReviewInfo(),
    this.needsReview = false,
    this.source,
    this.adminEdited = false,
    this.checkInGeo,
  });

  final String date;
  final String? employeeId;
  final String? employeeName;
  final String? arrival;
  final String? leave;
  final int? graceMinutes;
  final int? fullDayMinutes;
  final String? checkInLocal;
  final String? checkOutLocal;
  final int? workedMinutes;
  final int lateMinutes;
  final int earlyMinutes;
  final ReviewInfo late;
  final ReviewInfo early;
  final bool needsReview;
  final String? source;
  final bool adminEdited;
  final GeoStamp? checkInGeo;

  bool get hasCheckIn => checkInLocal != null;
  bool get hasCheckOut => checkOutLocal != null;
  bool get isLate => lateMinutes > 0;
  bool get isEarly => earlyMinutes > 0;
  bool get hasNeedsNote => late.needsNote || early.needsNote;

  factory AttendanceRecord.fromJson(Object? json) {
    final m = _map(json);
    final shift = _map(m['shift']);
    return AttendanceRecord(
      date: _str(m['date']) ?? '',
      employeeId: _str(m['employee_id']),
      employeeName: _str(m['employee_name']),
      arrival: _str(shift['arrival']),
      leave: _str(shift['leave']),
      graceMinutes: _intOrNull(shift['grace_minutes']),
      fullDayMinutes: _intOrNull(shift['full_day_minutes']),
      checkInLocal: _str(m['check_in_local']),
      checkOutLocal: _str(m['check_out_local']),
      workedMinutes: _intOrNull(m['worked_minutes']),
      lateMinutes: _int(m['late_minutes']),
      earlyMinutes: _int(m['early_minutes']),
      late: ReviewInfo.fromJson(m['late']),
      early: ReviewInfo.fromJson(m['early']),
      needsReview: m['needs_review'] == true,
      source: _str(m['source']),
      adminEdited: m['admin_edited'] == true,
      checkInGeo: m['check_in_geo'] == null
          ? null
          : GeoStamp.fromJson(m['check_in_geo']),
    );
  }

  static AttendanceRecord? maybe(Object? json) =>
      json is Map ? AttendanceRecord.fromJson(json) : null;
}

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

LatLng? _office(Object? v) {
  final m = _map(v);
  final lat = _dblOrNull(m['lat']);
  final lng = _dblOrNull(m['lng']);
  return lat == null || lng == null ? null : LatLng(lat, lng);
}

class TodaySettings {
  const TodaySettings({
    this.arrival = '10:00',
    this.leave = '19:00',
    this.graceMinutes = 15,
    this.radiusM = 10,
    this.maxAccuracyM = 25,
    this.fullDayMinutes = 360,
    this.office,
  });

  final String arrival;
  final String leave;
  final int graceMinutes;
  final int radiusM;
  final int maxAccuracyM;
  final int fullDayMinutes;
  final LatLng? office;

  factory TodaySettings.fromJson(Object? json) {
    final m = _map(json);
    return TodaySettings(
      arrival: _str(m['arrival']) ?? '10:00',
      leave: _str(m['leave']) ?? '19:00',
      graceMinutes: _intOrNull(m['grace_minutes']) ?? 15,
      radiusM: _intOrNull(m['radius_m']) ?? 10,
      maxAccuracyM: _intOrNull(m['max_accuracy_m']) ?? 25,
      fullDayMinutes: _intOrNull(m['full_day_minutes']) ?? 360,
      office: _office(m['office']),
    );
  }
}

class TodayInfo {
  const TodayInfo({
    required this.date,
    required this.time,
    required this.configured,
    required this.settings,
    required this.dayType,
    this.holidayName,
    this.record,
  });

  final String date;
  final String time;
  final bool configured;
  final TodaySettings settings;

  /// 'working' | 'holiday' | 'weekly_off'.
  final String dayType;
  final String? holidayName;
  final AttendanceRecord? record;

  bool get isWorkingDay => dayType == 'working';

  /// A working day whose shift has ended with no check-in: the server
  /// refuses a check-in now (shift_over).
  bool get shiftOver {
    if (!isWorkingDay || record?.hasCheckIn == true) return false;
    final n = _hhmm(time);
    final l = _hhmm(settings.leave);
    return n != null && l != null && n >= l;
  }

  factory TodayInfo.fromJson(Map<String, dynamic> json) {
    final day = _map(json['day']);
    return TodayInfo(
      date: _str(json['date']) ?? '',
      time: _str(json['time']) ?? '',
      configured: json['configured'] == true,
      settings: TodaySettings.fromJson(json['settings']),
      dayType: _str(day['type']) ?? 'working',
      holidayName: _str(day['holiday_name']),
      record: AttendanceRecord.maybe(json['record']),
    );
  }
}

class MonthSummary {
  const MonthSummary({
    this.workingDays = 0,
    this.present = 0,
    this.absent = 0,
    this.extraDays = 0,
    this.late = 0,
    this.early = 0,
    this.pending = 0,
    this.excused = 0,
    this.missedCheckout = 0,
    this.fullDays = 0,
    this.halfDays = 0,
    this.attendedValue,
    this.percent,
    this.stars,
    this.rank,
    this.rankedOf,
  });

  final int workingDays;
  final int present;
  final int absent;
  final int extraDays;
  final int late;
  final int early;
  final int pending;
  final int excused;
  final int missedCheckout;
  final int fullDays;
  final int halfDays;
  final double? attendedValue;
  final int? percent;
  final double? stars;
  final int? rank;
  final int? rankedOf;

  bool get isRated => percent != null && stars != null;

  factory MonthSummary.fromJson(Object? json) {
    final m = _map(json);
    return MonthSummary(
      workingDays: _firstInt(m, ['working_days', 'working']) ?? 0,
      present: _firstInt(m, ['present', 'present_days']) ?? 0,
      absent: _firstInt(m, ['absent', 'absent_days']) ?? 0,
      extraDays: _int(m['extra_days']),
      late: _int(m['late']),
      early: _int(m['early']),
      pending: _int(m['pending']),
      excused: _int(m['excused']),
      missedCheckout: _int(m['missed_checkout']),
      fullDays: _int(m['full_days']),
      halfDays: _int(m['half_days']),
      attendedValue: _dblOrNull(m['attended_value']),
      percent: _intOrNull(m['percent']),
      stars: _dblOrNull(m['stars']),
      rank: _intOrNull(m['rank']),
      rankedOf: _intOrNull(m['ranked_of']),
    );
  }
}

/// The kind values the server puts on every month day and team row.
class DayKind {
  DayKind._();
  static const notTracked = 'not_tracked';
  static const upcoming = 'upcoming';
  static const holiday = 'holiday';
  static const weeklyOff = 'weekly_off';
  static const extra = 'extra';
  static const absent = 'absent';
  static const inProgress = 'in_progress';
  static const missedCheckout = 'missed_checkout';
  static const full = 'full';
  static const half = 'half';
}

/// Best guess from the older status when a server does not send kind.
String _kindFromStatus(String status) {
  switch (status) {
    case 'present':
      return DayKind.full;
    case 'absent':
      return DayKind.absent;
    case 'off':
      return DayKind.weeklyOff;
    default:
      return DayKind.upcoming;
  }
}

class MonthDay {
  const MonthDay({
    required this.date,
    required this.type,
    required this.status,
    String? kind,
    this.holidayName,
    this.record,
  }) : _kind = kind;

  final String date;
  final String type;

  /// 'present' | 'absent' | 'off' | 'upcoming'.
  final String status;

  final String? _kind;

  /// How the day counts: see [DayKind].
  String get kind => _kind ?? _kindFromStatus(status);
  final String? holidayName;
  final AttendanceRecord? record;

  factory MonthDay.fromJson(Object? json) {
    final m = _map(json);
    return MonthDay(
      date: _str(m['date']) ?? '',
      type: _str(m['type']) ?? 'working',
      status: _str(m['status']) ?? 'upcoming',
      kind: _str(m['kind']),
      holidayName: _str(m['holiday_name']),
      record: AttendanceRecord.maybe(m['record']),
    );
  }
}

class MonthData {
  const MonthData({required this.summary, required this.days});

  final MonthSummary summary;
  final List<MonthDay> days;

  factory MonthData.fromJson(Map<String, dynamic> json) => MonthData(
    summary: MonthSummary.fromJson(json['summary']),
    days: _list(json['days']).map(MonthDay.fromJson).toList(),
  );
}

class TeamRow {
  const TeamRow({
    required this.employeeId,
    required this.name,
    required this.status,
    String? kind,
    this.record,
  }) : _kind = kind;

  final String employeeId;
  final String name;
  final String status;
  final String? _kind;
  String get kind => _kind ?? _kindFromStatus(status);
  final AttendanceRecord? record;
}

class TeamDay {
  const TeamDay({
    required this.date,
    required this.dayType,
    required this.rows,
  });

  final String date;
  final String dayType;
  final List<TeamRow> rows;

  factory TeamDay.fromJson(Map<String, dynamic> json) => TeamDay(
    date: _str(json['date']) ?? '',
    dayType: _str(_map(json['day'])['type']) ?? 'working',
    rows: _list(json['rows'])
        .map(
          (r) => TeamRow(
            employeeId: _str(r['employee_id']) ?? '',
            name: _str(r['name']) ?? 'Unknown',
            status: _str(r['status']) ?? 'absent',
            kind: _str(r['kind']),
            record: AttendanceRecord.maybe(r['record']),
          ),
        )
        .toList(),
  );
}

class TeamMonthRow {
  const TeamMonthRow({
    required this.employeeId,
    required this.name,
    required this.summary,
  });

  final String employeeId;
  final String name;
  final MonthSummary summary;
}

List<TeamMonthRow> parseTeamMonth(Map<String, dynamic> json) =>
    _list(json['rows'])
        .map(
          (r) => TeamMonthRow(
            employeeId: _str(r['employee_id']) ?? '',
            name: _str(r['name']) ?? 'Unknown',
            summary: MonthSummary.fromJson(r['summary']),
          ),
        )
        .toList();

class ApprovalItem {
  const ApprovalItem({
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.kind,
    required this.minutes,
    this.note,
    this.expected,
    this.actual,
  });

  final String employeeId;
  final String employeeName;
  final String date;

  /// 'late' | 'early'.
  final String kind;
  final int minutes;
  final String? note;
  final String? expected;
  final String? actual;

  factory ApprovalItem.fromJson(Map<String, dynamic> m) => ApprovalItem(
    employeeId: _str(m['employee_id']) ?? '',
    employeeName: _str(m['employee_name']) ?? 'Unknown',
    date: _str(m['date']) ?? '',
    kind: _str(m['kind']) ?? 'late',
    minutes: _int(m['minutes']),
    note: _str(m['note']),
    expected: _str(m['expected']),
    actual: _str(m['actual']),
  );
}

/// A working day someone checked in but never checked out.
class MissedCheckout {
  const MissedCheckout({
    required this.employeeId,
    required this.employeeName,
    required this.date,
    this.checkIn,
  });

  final String employeeId;
  final String employeeName;
  final String date;
  final String? checkIn;

  factory MissedCheckout.fromJson(Map<String, dynamic> m) => MissedCheckout(
    employeeId: _str(m['employee_id']) ?? '',
    employeeName: _str(m['employee_name']) ?? 'Unknown',
    date: _str(m['date']) ?? '',
    checkIn: _str(m['check_in']),
  );
}

/// Everything the Approvals tab shows: notes to decide, and missed
/// check-outs to complete.
class ApprovalsData {
  const ApprovalsData({this.items = const [], this.missedCheckouts = const []});

  final List<ApprovalItem> items;
  final List<MissedCheckout> missedCheckouts;

  /// What the tab badge counts.
  int get total => items.length + missedCheckouts.length;
}

ApprovalsData parseApprovals(Map<String, dynamic> json) => ApprovalsData(
  items: _list(json['items']).map(ApprovalItem.fromJson).toList(),
  missedCheckouts: _list(
    json['missed_checkouts'],
  ).map(MissedCheckout.fromJson).toList(),
);

class Holiday {
  const Holiday({required this.date, required this.name});
  final String date;
  final String name;
}

List<Holiday> parseHolidays(Map<String, dynamic> json) =>
    _list(json['holidays'])
        .map(
          (h) =>
              Holiday(date: _str(h['date']) ?? '', name: _str(h['name']) ?? ''),
        )
        .where((h) => h.date.isNotEmpty)
        .toList();

class AttendanceSettings {
  const AttendanceSettings({
    this.office,
    this.radiusM = 10,
    this.maxAccuracyM = 25,
    this.arrival = '10:00',
    this.leave = '19:00',
    this.graceMinutes = 15,
    this.fullDayMinutes,
    this.weeklyOff = const [7],
  });

  final LatLng? office;
  final int radiusM;
  final int maxAccuracyM;
  final String arrival;
  final String leave;
  final int graceMinutes;

  /// Worked minutes that make a full day (60-1440). Null when unknown; a save
  /// without it leaves the server's value alone.
  final int? fullDayMinutes;

  /// ISO weekdays that are off, 1 = Monday .. 7 = Sunday.
  final List<int> weeklyOff;

  factory AttendanceSettings.fromJson(Map<String, dynamic> json) {
    final m = _map(json['settings'] ?? json);
    var off = const <int>[7];
    final direct = m['weekly_off'];
    final history = m['weekly_off_history'];
    if (direct is List) {
      off = direct.whereType<num>().map((e) => e.toInt()).toList();
    } else if (history is List && history.isNotEmpty) {
      final last = _map(history.last);
      final days = last['days'];
      if (days is List) {
        off = days.whereType<num>().map((e) => e.toInt()).toList();
      }
    }
    return AttendanceSettings(
      office: _office(m['office']),
      radiusM: _intOrNull(m['radius_m']) ?? 10,
      maxAccuracyM: _intOrNull(m['max_accuracy_m']) ?? 25,
      arrival: _str(m['arrival']) ?? '10:00',
      leave: _str(m['leave']) ?? '19:00',
      graceMinutes: _intOrNull(m['grace_minutes']) ?? 15,
      fullDayMinutes: _intOrNull(m['full_day_minutes']) ?? 360,
      weeklyOff: off,
    );
  }

  Map<String, dynamic> toPayload() => {
    'office': office == null ? null : {'lat': office!.lat, 'lng': office!.lng},
    'radius_m': radiusM,
    'max_accuracy_m': maxAccuracyM,
    'arrival': arrival,
    'leave': leave,
    'grace_minutes': graceMinutes,
    'full_day_minutes': ?fullDayMinutes,
    'weekly_off': weeklyOff,
  };
}

/// What the phone sends with a mark.
class MarkPayload {
  const MarkPayload({
    required this.action,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.isMocked,
    required this.positionAgeMs,
    required this.deviceId,
    required this.biometricPassed,
  });

  /// 'in' | 'out'.
  final String action;
  final double lat;
  final double lng;
  final double accuracyM;
  final bool isMocked;
  final int positionAgeMs;
  final String deviceId;
  final bool biometricPassed;

  Map<String, dynamic> toJson() => {
    'action': action,
    'lat': lat,
    'lng': lng,
    'accuracy_m': accuracyM,
    'is_mocked': isMocked,
    'position_age_ms': positionAgeMs,
    'device_id': deviceId,
    'biometric_passed': biometricPassed,
  };
}

class MarkResult {
  const MarkResult({required this.record, required this.already});
  final AttendanceRecord record;
  final bool already;
}
