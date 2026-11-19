import 'package:local_auth/local_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/cloud_callables.dart';
import 'package:growmont_crm/features/attendance/attendance_models.dart';
import 'package:growmont_crm/features/attendance/attendance_providers.dart';
import 'package:growmont_crm/features/attendance/attendance_service.dart';
import 'package:growmont_crm/features/attendance/device_gateways.dart';
import 'package:growmont_crm/features/attendance/mark_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_fakes.dart';

void main() {
  late FakeAttendanceService service;
  late FakeLocation location;
  late FakeBiometric biometric;

  setUp(() {
    service = FakeAttendanceService();
    location = FakeLocation();
    biometric = FakeBiometric();
  });

  Future<MarkOutcome> run({
    String action = 'in',
    bool confirm = true,
    List<int>? asked,
  }) {
    final flow = MarkFlow(
      service: service,
      location: location,
      biometric: biometric,
      deviceId: () async => 'device-1',
    );
    return flow.run(
      action: action,
      onStatus: (_) {},
      confirmEarly: (m) async {
        asked?.add(m);
        return confirm;
      },
    );
  }

  group('mark flow', () {
    test('happy path sends the fix, device id and biometric result', () async {
      final outcome = await run();
      expect(outcome, isA<MarkSuccess>());
      final sent = service.markCalls.single;
      expect(sent.action, 'in');
      expect(sent.deviceId, 'device-1');
      expect(sent.biometricPassed, isTrue);
      expect(sent.accuracyM, 8);
      expect(sent.positionAgeMs, 300);
    });

    test('server says not configured: stops before any phone prompt', () async {
      service.today = todayJson(configured: false);
      final outcome = await run();
      expect(outcome, isA<MarkFailed>());
      expect((outcome as MarkFailed).code, 'not_configured');
      expect(location.accessCalls, 0);
      expect(biometric.calls, 0);
    });

    test('location permission denied can be retried', () async {
      location.access = LocationAccess.denied;
      final outcome = await run() as MarkFailed;
      expect(outcome.fix, MarkFix.retry);
      expect(outcome.message, contains('permission'));
      expect(location.fixCalls, 0);
      expect(service.markCalls, isEmpty);
    });

    test('denied forever offers app settings', () async {
      location.access = LocationAccess.deniedForever;
      final outcome = await run() as MarkFailed;
      expect(outcome.fix, MarkFix.openAppSettings);
    });

    test('location service off offers location settings', () async {
      location.access = LocationAccess.serviceOff;
      final outcome = await run() as MarkFailed;
      expect(outcome.fix, MarkFix.openLocationSettings);
    });

    test('GPS timeout is explained and retryable', () async {
      location.timeout = true;
      final outcome = await run() as MarkFailed;
      expect(outcome.fix, MarkFix.retry);
      expect(outcome.message, contains('GPS'));
      expect(biometric.calls, 0);
    });

    test('too far shows "You are X m away" and never asks for a fingerprint',
        () async {
      location.distance = 142.4;
      final outcome = await run() as MarkFailed;
      expect(outcome.message, contains('You are 142 m away'));
      expect(outcome.code, 'outside_radius');
      expect(biometric.calls, 0);
      expect(service.markCalls, isEmpty);
    });

    test('weak GPS accuracy is refused locally', () async {
      location.fix = const GpsFix(
        lat: 18.5,
        lng: 73.8,
        accuracyM: 60,
        isMocked: false,
        positionAgeMs: 0,
      );
      final outcome = await run() as MarkFailed;
      expect(outcome.code, 'poor_accuracy');
      expect(biometric.calls, 0);
    });

    test('biometric cancelled is quiet and sends nothing', () async {
      biometric.result = BiometricResult.cancelled;
      final outcome = await run();
      expect(outcome, isA<MarkCancelled>());
      expect(service.markCalls, isEmpty);
    });

    test('no biometrics enrolled tells the person what to do', () async {
      biometric.result = BiometricResult.notEnrolled;
      final outcome = await run() as MarkFailed;
      expect(outcome.message, contains('set up'));
      expect(outcome.message, contains('admin'));
      expect(service.markCalls, isEmpty);
    });

    test('biometrics unavailable and locked out are explained', () async {
      biometric.result = BiometricResult.unavailable;
      expect((await run() as MarkFailed).message, contains('admin'));
      biometric.result = BiometricResult.lockedOut;
      final locked = await run() as MarkFailed;
      expect(locked.message, contains('locked'));
      expect(service.markCalls, isEmpty);
    });

    test('early check-out asks first, stating the minutes', () async {
      service.today = todayJson(
        time: '17:30',
        record: recJson(inT: '10:00'),
      );
      final asked = <int>[];
      final declined = await run(action: 'out', confirm: false, asked: asked);
      expect(declined, isA<MarkCancelled>());
      expect(asked, [90]);
      expect(biometric.calls, 0);

      final accepted = await run(action: 'out', asked: asked);
      expect(accepted, isA<MarkSuccess>());
    });

    test('check-out inside the grace window does not ask', () async {
      service.today = todayJson(time: '18:50', record: recJson(inT: '10:00'));
      final asked = <int>[];
      await run(action: 'out', asked: asked);
      expect(asked, isEmpty);
    });

    test('network failure offers retry and is never a success', () async {
      service.markError = const BackendException(
        'Could not reach the server. Check your internet connection and try '
        'again.',
      );
      final outcome = await run();
      expect(outcome, isA<MarkFailed>());
      expect((outcome as MarkFailed).fix, MarkFix.retry);

      service.markError = null;
      expect(await run(), isA<MarkSuccess>());
    });

    test('a failure reading today also offers retry', () async {
      service.todayError = const BackendException('Could not reach the server.');
      final outcome = await run() as MarkFailed;
      expect(outcome.fix, MarkFix.retry);
    });
  });

  group('server error codes', () {
    const codes = [
      'not_configured',
      'outside_radius',
      'poor_accuracy',
      'mock_location',
      'stale_location',
      'biometric_required',
      'device_in_use',
      'shift_over',
      'not_checked_in',
      'too_soon',
      'locked_by_admin',
      'already_decided',
      'note_not_allowed',
      'not_pending',
      'self_review',
    ];

    for (final code in codes) {
      test('$code has its own plain message and is not retryable', () async {
        service.markError = BackendException(
          'raw server text',
          code: code,
          details: const {'distance_m': 41.6, 'radius_m': 30, 'accuracy_m': 52},
        );
        final outcome = await run() as MarkFailed;
        expect(outcome.code, code);
        expect(outcome.message, isNot('raw server text'));
        expect(outcome.message, isNotEmpty);
        expect(outcome.fix, MarkFix.none);
      });
    }

    test('outside_radius message carries both distances', () {
      final text = attendanceErrorMessage(
        const BackendException(
          'x',
          code: 'outside_radius',
          details: {'distance_m': 41.6, 'radius_m': 30},
        ),
      );
      expect(text, contains('42 m'));
      expect(text, contains('30 m'));
    });

    test('invalid_input keeps the server wording', () {
      expect(
        attendanceErrorMessage(
          const BackendException('Radius must be 10 to 500.', code: 'invalid_input'),
        ),
        'Radius must be 10 to 500.',
      );
    });
  });

  group('helpers', () {
    test('minutesEarly', () {
      expect(minutesEarly(now: '17:30', leave: '19:00', grace: 15), 90);
      expect(minutesEarly(now: '18:45', leave: '19:00', grace: 15), 0);
      expect(minutesEarly(now: '18:44', leave: '19:00', grace: 15), 16);
      expect(minutesEarly(now: 'bad', leave: '19:00', grace: 15), 0);
    });

    test('device id is random, long, and stable once saved', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await DeviceIdStore().get();
      final second = await DeviceIdStore().get();
      expect(first.length, 32);
      expect(second, first);
      SharedPreferences.setMockInitialValues({});
      expect(await DeviceIdStore().get(), isNot(first));
    });

    test('summary with nulls parses as not rated', () {
      final s = MonthSummary.fromJson({
        'working_days': 0,
        'present': 0,
        'percent': null,
        'stars': null,
        'rank': null,
        'ranked_of': null,
      });
      expect(s.isRated, isFalse);
      expect(s.rank, isNull);
      expect(MonthSummary.fromJson(null).workingDays, 0);
    });
  });

  group('midnight rollover', () {
    test('someone viewing the month that just ended follows into the new month', () {
      expect(
        monthAfterDayChange(DateTime(2026, 11), '2026-11-30', '2026-12-01'),
        DateTime(2026, 12),
      );
      expect(
        monthAfterDayChange(DateTime(2026, 12), '2026-12-31', '2027-01-01'),
        DateTime(2027, 1),
      );
    });

    test('a month browsed to on purpose is left alone, and an ordinary day changes nothing', () {
      expect(
        monthAfterDayChange(DateTime(2026, 9), '2026-11-30', '2026-12-01'),
        DateTime(2026, 9),
      );
      expect(
        monthAfterDayChange(DateTime(2026, 11), '2026-11-18', '2026-11-19'),
        DateTime(2026, 11),
      );
    });
  });

  group('adversarial', () {
    test('a throwing location plugin becomes a retryable failure, not a crash',
        () async {
      location.accessError = StateError('plugin exploded');
      final outcome = await run();
      expect(outcome, isA<MarkFailed>());
      expect((outcome as MarkFailed).fix, MarkFix.retry);
      expect(biometric.calls, 0);
      expect(service.markCalls, isEmpty);
      location.accessError = null;
      expect(await run(), isA<MarkSuccess>());
    });

    test('local_auth v3 codes: quiet cancels, enrolment, lockout, the rest', () async {
      Future<BiometricResult> via(LocalAuthExceptionCode c) =>
          LocalAuthGateway(_ThrowingAuth(c)).authenticate('why');
      for (final c in [
        LocalAuthExceptionCode.userCanceled,
        LocalAuthExceptionCode.systemCanceled,
        LocalAuthExceptionCode.timeout,
        LocalAuthExceptionCode.userRequestedFallback,
        LocalAuthExceptionCode.authInProgress,
      ]) {
        expect(await via(c), BiometricResult.cancelled, reason: '$c');
      }
      expect(await via(LocalAuthExceptionCode.noBiometricsEnrolled), BiometricResult.notEnrolled);
      expect(await via(LocalAuthExceptionCode.noCredentialsSet), BiometricResult.notEnrolled);
      expect(await via(LocalAuthExceptionCode.temporaryLockout), BiometricResult.lockedOut);
      expect(await via(LocalAuthExceptionCode.biometricLockout), BiometricResult.lockedOut);
      expect(await via(LocalAuthExceptionCode.noBiometricHardware), BiometricResult.unavailable);
      expect(await via(LocalAuthExceptionCode.uiUnavailable), BiometricResult.unavailable);
      expect(await via(LocalAuthExceptionCode.deviceError), BiometricResult.unavailable);
    });
  });

}

/// Throws the given local_auth failure from authenticate().
class _ThrowingAuth implements LocalAuthentication {
  _ThrowingAuth(this.code);
  final LocalAuthExceptionCode code;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<bool>.error(LocalAuthException(code: code));
}
