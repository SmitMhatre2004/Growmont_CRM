import 'dart:async';

import '../../core/firebase/cloud_callables.dart';
import 'attendance_models.dart';
import 'attendance_service.dart';
import 'device_gateways.dart';

/// What the person can do about a failed mark.
enum MarkFix { none, retry, openAppSettings, openLocationSettings }

sealed class MarkOutcome {
  const MarkOutcome();
}

class MarkSuccess extends MarkOutcome {
  const MarkSuccess(this.result, this.action);
  final MarkResult result;
  final String action;
}

/// The person backed out (biometric dismissed, early check-out declined).
/// Nothing was sent and nothing should be shown.
class MarkCancelled extends MarkOutcome {
  const MarkCancelled();
}

class MarkFailed extends MarkOutcome {
  const MarkFailed(this.message, {this.fix = MarkFix.none, this.code});
  final String message;
  final MarkFix fix;
  final String? code;
}

/// The mark sequence, one step at a time:
/// server config -> location access -> fresh GPS -> local distance check ->
/// early-leave confirmation -> biometric -> server.
///
/// The server repeats every check; the local ones only spare the person a
/// fingerprint prompt that was going to be refused anyway.
class MarkFlow {
  MarkFlow({
    required this.service,
    required this.location,
    required this.biometric,
    required this.deviceId,
    this.gpsTimeout = const Duration(seconds: 20),
  });

  final AttendanceService service;
  final LocationGateway location;
  final BiometricGateway biometric;
  final Future<String> Function() deviceId;
  final Duration gpsTimeout;

  /// [action] is 'in' or 'out'. [onStatus] reports progress text;
  /// [confirmEarly] is asked, with the minutes early, before an early
  /// check-out and must return true to go on.
  Future<MarkOutcome> run({
    required String action,
    required void Function(String status) onStatus,
    required Future<bool> Function(int minutesEarly) confirmEarly,
  }) async {
    // 1. Server config check (also gives us the office and the server time).
    onStatus('Checking attendance setup...');
    final TodayInfo today;
    try {
      today = await service.getToday();
    } catch (e) {
      return _fromError(e);
    }
    if (!today.configured || today.settings.office == null) {
      return MarkFailed(
        attendanceErrorMessage(
          const BackendException('', code: 'not_configured'),
        ),
        code: 'not_configured',
      );
    }

    // 2. Location service and permission.
    onStatus('Checking location permission...');
    final LocationAccess access;
    try {
      access = await location.ensureAccess();
    } catch (_) {
      return const MarkFailed(
        'Could not check the location settings on this phone. Please try '
        'again.',
        fix: MarkFix.retry,
      );
    }
    switch (access) {
      case LocationAccess.serviceOff:
        return const MarkFailed(
          'Location is turned off on this phone. Turn it on to mark '
          'attendance.',
          fix: MarkFix.openLocationSettings,
        );
      case LocationAccess.denied:
        return const MarkFailed(
          'Location permission is needed to confirm you are at the office. '
          'Please allow it and try again.',
          fix: MarkFix.retry,
        );
      case LocationAccess.deniedForever:
        return const MarkFailed(
          'Location permission is blocked for this app. Open settings and '
          'allow location to mark attendance.',
          fix: MarkFix.openAppSettings,
        );
      case LocationAccess.granted:
        break;
    }

    // 3. Fresh high-accuracy GPS.
    onStatus('Getting your location...');
    final GpsFix fix;
    try {
      fix = await location.currentFix(timeout: gpsTimeout);
    } on TimeoutException {
      return const MarkFailed(
        'Could not get a GPS reading in time. Move near a window or '
        'outdoors and try again.',
        fix: MarkFix.retry,
      );
    } catch (_) {
      return const MarkFailed(
        'Could not read your location. Check that location is on and try '
        'again.',
        fix: MarkFix.retry,
      );
    }

    // 4. Local pre-check.
    final office = today.settings.office!;
    final distance = location.distanceM(
      fix.lat,
      fix.lng,
      office.lat,
      office.lng,
    );
    final away = distance.round();
    onStatus('You are $away m away from the office.');
    if (distance > today.settings.radiusM) {
      return MarkFailed(
        'You are $away m away from the office. You need to be within '
        '${today.settings.radiusM} m.',
        fix: MarkFix.retry,
        code: 'outside_radius',
      );
    }
    if (fix.accuracyM > today.settings.maxAccuracyM) {
      return MarkFailed(
        'Your GPS signal is too weak (${fix.accuracyM.round()} m accuracy, '
        '${today.settings.maxAccuracyM} m needed). Move near a window or '
        'outdoors and try again.',
        fix: MarkFix.retry,
        code: 'poor_accuracy',
      );
    }
    if (fix.isMocked) {
      return MarkFailed(
        attendanceErrorMessage(
          const BackendException('', code: 'mock_location'),
        ),
        code: 'mock_location',
      );
    }

    // 5. Early check-out needs an explicit yes.
    if (action == 'out') {
      final early = minutesEarly(
        now: today.time,
        leave: today.record?.leave ?? today.settings.leave,
        grace: today.record?.graceMinutes ?? today.settings.graceMinutes,
      );
      if (early > 0 && !await confirmEarly(early)) {
        return const MarkCancelled();
      }
    }

    // 6. Biometric. Cancelling is quiet; anything else is explained.
    onStatus('Confirm it is you...');
    final bio = await biometric.authenticate(
      action == 'in'
          ? 'Confirm it is you to mark attendance'
          : 'Confirm it is you to mark check-out',
    );
    switch (bio) {
      case BiometricResult.cancelled:
        return const MarkCancelled();
      case BiometricResult.notEnrolled:
        return const MarkFailed(
          'No fingerprint or face is set up on this phone. Add one in the '
          'phone\'s security settings, or ask an admin for help.',
        );
      case BiometricResult.unavailable:
        return const MarkFailed(
          'Fingerprint or face confirmation is not available on this '
          'phone. Ask an admin for help.',
        );
      case BiometricResult.lockedOut:
        return const MarkFailed(
          'Fingerprint or face confirmation is locked after too many '
          'attempts. Unlock your phone with its PIN, then try again, or ask '
          'an admin for help.',
          fix: MarkFix.retry,
        );
      case BiometricResult.passed:
        break;
    }

    // 7. Server.
    onStatus('Saving...');
    try {
      final result = await service.mark(
        MarkPayload(
          action: action,
          lat: fix.lat,
          lng: fix.lng,
          accuracyM: fix.accuracyM,
          isMocked: fix.isMocked,
          positionAgeMs: fix.positionAgeMs,
          deviceId: await deviceId(),
          biometricPassed: true,
        ),
      );
      return MarkSuccess(result, action);
    } catch (e) {
      return _fromError(e);
    }
  }

  MarkFailed _fromError(Object e) {
    final code = e is BackendException ? e.code : null;
    return MarkFailed(
      attendanceErrorMessage(e),
      // No code means the request never got a proper answer (offline,
      // timeout): offer Retry. Retrying a check-in is safe - the server
      // returns the existing record - and a check-out just overwrites.
      fix: code == null ? MarkFix.retry : MarkFix.none,
      code: code,
    );
  }
}

/// Whole minutes before (leave - grace) that [now] falls, 0 when not early.
/// Both are "HH:mm" office-time strings from the server.
int minutesEarly({
  required String now,
  required String leave,
  required int grace,
}) {
  final n = _minutes(now);
  final l = _minutes(leave);
  if (n == null || l == null) return 0;
  final threshold = l - grace;
  return n < threshold ? l - n : 0;
}

int? _minutes(String hhmm) {
  final p = hhmm.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}
