import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

/// Small seams over the two phone-only plugins, so the mark flow can be
/// tested without them and so nothing in them is ever called on Windows or
/// the web.

/// Whether this build can mark attendance: only Android and iOS have the GPS
/// and biometric hardware the check needs.
bool platformCanMarkAttendance() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

enum LocationAccess { granted, denied, deniedForever, serviceOff }

class GpsFix {
  const GpsFix({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.isMocked,
    required this.positionAgeMs,
  });

  final double lat;
  final double lng;
  final double accuracyM;
  final bool isMocked;

  /// How old the reading was when it was taken, in milliseconds.
  final int positionAgeMs;
}

abstract class LocationGateway {
  /// Checks the location service and permission, asking for permission when
  /// that is still possible.
  Future<LocationAccess> ensureAccess();

  /// The current location service and permission state, WITHOUT asking for
  /// anything. Safe to call on any screen load.
  Future<LocationAccess> checkAccess();

  /// Live readings while someone is listening; cancelling the subscription
  /// stops the GPS. A new reading is sent after [distanceFilterM] metres.
  Stream<GpsFix> watchFix({int distanceFilterM = 5});

  /// A fresh high-accuracy reading. Throws [TimeoutException] if none
  /// arrives within [timeout].
  Future<GpsFix> currentFix({Duration timeout = const Duration(seconds: 20)});

  /// Straight-line distance in metres.
  double distanceM(double lat1, double lng1, double lat2, double lng2);

  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}

class GeolocatorGateway implements LocationGateway {
  @override
  Future<LocationAccess> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        return LocationAccess.denied;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      default:
        return LocationAccess.granted;
    }
  }

  @override
  Future<LocationAccess> checkAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    switch (await Geolocator.checkPermission()) {
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      default:
        return LocationAccess.granted;
    }
  }

  @override
  Stream<GpsFix> watchFix({int distanceFilterM = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: distanceFilterM,
      ),
    ).map(_fixOf);
  }

  static GpsFix _fixOf(Position position) {
    final age = DateTime.now().difference(position.timestamp).inMilliseconds;
    return GpsFix(
      lat: position.latitude,
      lng: position.longitude,
      accuracyM: position.accuracy,
      isMocked: position.isMocked,
      positionAgeMs: age < 0 ? 0 : age,
    );
  }

  @override
  Future<GpsFix> currentFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: timeout,
      ),
    );
    final age = DateTime.now().difference(position.timestamp).inMilliseconds;
    return GpsFix(
      lat: position.latitude,
      lng: position.longitude,
      accuracyM: position.accuracy,
      isMocked: position.isMocked,
      // The server accepts 0..120000; a clock that is a little off must not
      // push a fresh reading out of range.
      positionAgeMs: age < 0 ? 0 : age,
    );
  }

  @override
  double distanceM(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}

enum BiometricResult {
  passed,

  /// The person dismissed the prompt or failed it. Nothing should happen.
  cancelled,
  notEnrolled,
  unavailable,
  lockedOut,
}

abstract class BiometricGateway {
  Future<BiometricResult> authenticate(String reason);
}

class LocalAuthGateway implements BiometricGateway {
  LocalAuthGateway([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricResult.passed : BiometricResult.cancelled;
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.userRequestedFallback:
        // A prompt is already on screen (a double tap): stay quiet.
        case LocalAuthExceptionCode.authInProgress:
          return BiometricResult.cancelled;
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noCredentialsSet:
          return BiometricResult.notEnrolled;
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return BiometricResult.lockedOut;
        default:
          return BiometricResult.unavailable;
      }
    } catch (_) {
      return BiometricResult.unavailable;
    }
  }
}
