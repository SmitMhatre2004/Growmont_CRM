import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/cloud_callables.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/attendance/attendance_providers.dart';
import 'package:growmont_crm/features/attendance/dashboard_ring.dart';
import 'package:growmont_crm/features/attendance/device_gateways.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_fakes.dart';

const _inside = GpsFix(lat: 18.5, lng: 73.8, accuracyM: 8, isMocked: false, positionAgeMs: 100);

class _Harness {
  _Harness({
    FakeAttendanceService? service,
    FakeLocation? location,
    this.canMark = true,
  }) : service = service ?? FakeAttendanceService(),
       location = location ?? FakeLocation();

  final FakeAttendanceService service;
  final FakeLocation location;
  final FakeBiometric biometric = FakeBiometric();
  final bool canMark;
  int openedAttendance = 0;
}

Future<void> _pump(
  WidgetTester t,
  _Harness h, {
  bool disableAnimations = false,
  Widget Function(Widget ring)? wrap,
}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(390, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final ring = DashboardRingButton(onOpenAttendance: () => h.openedAttendance++);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        if (h.canMark) ...[
          attendanceServiceProvider.overrideWithValue(h.service),
          locationGatewayProvider.overrideWithValue(h.location),
          biometricGatewayProvider.overrideWithValue(h.biometric),
        ],
        canMarkAttendanceProvider.overrideWithValue(h.canMark),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(actions: [wrap == null ? ring : wrap(ring)]),
          body: const SizedBox(),
        ),
      ),
    ),
  );
  addTearDown(() async => t.pumpWidget(const SizedBox()));
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

RingVisual _visual(WidgetTester t) => t.widget<RingVisual>(find.byType(RingVisual));

void main() {
  group('ring colour rule (same test as the server)', () {
    RingTone tone(GpsFix? fix, double? d) =>
        ringToneFor(fix: fix, distanceM: d, radiusM: 30, maxAccuracyM: 25);

    test('green: inside the radius, accurate and not mocked', () {
      expect(tone(_inside, 5), RingTone.green);
      expect(tone(_inside, 30), RingTone.green); // exactly on the radius
    });

    test('yellow in every other case', () {
      expect(tone(_inside, 31), RingTone.yellow); // outside
      expect(
        tone(const GpsFix(lat: 0, lng: 0, accuracyM: 26, isMocked: false, positionAgeMs: 0), 5),
        RingTone.yellow,
      ); // poor accuracy
      expect(
        tone(const GpsFix(lat: 0, lng: 0, accuracyM: 5, isMocked: true, positionAgeMs: 0), 5),
        RingTone.yellow,
      ); // mocked
      expect(tone(null, null), RingTone.yellow); // unknown
    });
  });

  group('the pill', () {
    test('the outline is a full-radius pill that fills its box', () {
      const r = Rect.fromLTWH(2, 2, 60, 40);
      final b = pillOutline(r).getBounds();
      expect(b.left, closeTo(r.left, 0.01));
      expect(b.right, closeTo(r.right, 0.01));
      expect(b.top, closeTo(r.top, 0.01));
      expect(b.bottom, closeTo(r.bottom, 0.01));
      // Perimeter of a stadium: two straights plus one full circle.
      final len = pillOutline(r).computeMetrics().first.length;
      expect(len, closeTo(2 * (60 - 40) + 2 * 3.141592653589793 * 20, 1.5));
    });

    testWidgets('is a 64 x 44 pill, not a circle, with the fingerprint centred', (t) async {
      final h = _Harness();
      await _pump(t, h);
      expect(t.getSize(find.byType(RingVisual)), const Size(kAttendancePillWidth, kAttendancePillHeight));
      expect(kAttendancePillWidth, greaterThan(kAttendancePillHeight));
      final icon = find.descendant(of: find.byType(RingVisual), matching: find.byIcon(Icons.fingerprint));
      expect(t.getCenter(icon), t.getCenter(find.byType(RingVisual)));
    });

    testWidgets('keeps its tone and spins in range or out; static when reduced motion', (t) async {
      final h = _Harness();
      await _pump(t, h);
      h.location
        ..distance = 5
        ..emit(_inside);
      await _settle(t);
      expect(_visual(t).tone, RingTone.green);
      expect(t.hasRunningAnimations, isTrue);
      h.location
        ..distance = 500
        ..emit(_inside);
      await _settle(t);
      expect(_visual(t).tone, RingTone.yellow);
      await t.pumpWidget(const SizedBox());

      await _pump(t, _Harness(), disableAnimations: true);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('the ring paints along the pill outline in the tone colour', (t) async {
      final h = _Harness();
      await _pump(t, h);
      h.location
        ..distance = 5
        ..emit(_inside);
      await _settle(t);
      final painter = t
          .widgetList<CustomPaint>(find.descendant(of: find.byType(RingVisual), matching: find.byType(CustomPaint)))
          .map((c) => c.painter)
          .whereType<RingPainter>()
          .single;
      expect(painter.color, kRingGreen);
      h.location
        ..distance = 500
        ..emit(_inside);
      await _settle(t);
      final yellow = t
          .widgetList<CustomPaint>(find.descendant(of: find.byType(RingVisual), matching: find.byType(CustomPaint)))
          .map((c) => c.painter)
          .whereType<RingPainter>()
          .single;
      expect(yellow.color, kRingYellow);
    });
  });

  group('on the Dashboard', () {
    testWidgets('loading the Dashboard never asks for permission and starts yellow', (t) async {
      final h = _Harness()..location.access = LocationAccess.denied;
      await _pump(t, h);
      expect(h.location.accessCalls, 0); // ensureAccess is the call that prompts
      expect(h.location.fixCalls, 0);
      expect(h.location.watchStarts, 0); // nothing granted, nothing watched
      expect(_visual(t).tone, RingTone.yellow);
      expect(_visual(t).size, inInclusiveRange(44, 48));
    });

    testWidgets('no permission, GPS off or unknown location: yellow', (t) async {
      for (final access in [LocationAccess.serviceOff, LocationAccess.deniedForever]) {
        final h = _Harness()..location.access = access;
        await _pump(t, h);
        expect(_visual(t).tone, RingTone.yellow, reason: '$access');
        await t.pumpWidget(const SizedBox());
      }
      final h = _Harness();
      await _pump(t, h); // granted, but no reading yet
      expect(_visual(t).tone, RingTone.yellow);
    });

    testWidgets('green inside the radius, yellow outside, poor accuracy or mocked', (t) async {
      final h = _Harness();
      await _pump(t, h);
      expect(h.location.watching, isTrue);

      h.location
        ..distance = 5
        ..emit(_inside);
      await _settle(t);
      expect(_visual(t).tone, RingTone.green);

      h.location
        ..distance = 500
        ..emit(_inside);
      await _settle(t);
      expect(_visual(t).tone, RingTone.yellow);

      h.location
        ..distance = 5
        ..emit(const GpsFix(lat: 18.5, lng: 73.8, accuracyM: 60, isMocked: false, positionAgeMs: 0));
      await _settle(t);
      expect(_visual(t).tone, RingTone.yellow);

      h.location.emit(const GpsFix(lat: 18.5, lng: 73.8, accuracyM: 5, isMocked: true, positionAgeMs: 0));
      await _settle(t);
      expect(_visual(t).tone, RingTone.yellow);
    });

    testWidgets('the stream is cancelled on pause, restarted on resume, and on leaving the Dashboard', (t) async {
      final h = _Harness();
      await _pump(t, h);
      expect(h.location.watchStarts, 1);
      expect(h.location.watchCancels, 0);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _settle(t);
      expect(h.location.watchCancels, 1);
      expect(h.location.watching, isFalse);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(h.location.watchStarts, 2);
      expect(h.location.watching, isTrue);

      // The Dashboard goes away (another tab, a pushed page).
      await t.pumpWidget(const SizedBox());
      expect(h.location.watchCancels, 2);
      expect(h.location.watching, isFalse);
    });

    testWidgets('a hidden Dashboard watches nothing even if resumed later', (t) async {
      final h = _Harness();
      await _pump(t, h);
      await t.pumpWidget(const SizedBox());
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(t);
      expect(h.location.watching, isFalse);
    });

    testWidgets('no check-in: tap marks present through the whole flow', (t) async {
      final h = _Harness();
      await _pump(t, h);
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(h.service.markCalls.map((m) => m.action), ['in']);
      expect(h.biometric.calls, 1);
      expect(h.location.accessCalls, 1); // the prompt happens on tap only
      expect(find.textContaining('Marked present at 10:05'), findsOneWidget);
    });

    testWidgets('checked in: tap marks check-out', (t) async {
      final service = FakeAttendanceService()
        ..today = todayJson(time: '18:55', record: recJson(inT: '10:02'));
      final h = _Harness(service: service);
      await _pump(t, h);
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(h.service.markCalls.map((m) => m.action), ['out']);
    });

    testWidgets('after check-out: solid green ring with a check, tap opens Attendance', (t) async {
      final service = FakeAttendanceService()
        ..today = todayJson(record: recJson(inT: '10:02', outT: '19:01'));
      final h = _Harness(service: service);
      await _pump(t, h);
      final v = _visual(t);
      expect(v.complete, isTrue);
      expect(v.tone, RingTone.green);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // Static: nothing keeps animating.
      expect(t.hasRunningAnimations, isFalse);

      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(h.openedAttendance, 1);
      expect(h.service.markCalls, isEmpty);
    });

    testWidgets('out of range: the existing "You are X m away" message, no biometric', (t) async {
      final h = _Harness(location: FakeLocation()..distance = 250);
      await _pump(t, h);
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(find.textContaining('You are 250 m away'), findsOneWidget);
      expect(h.biometric.calls, 0);
      expect(h.service.markCalls, isEmpty);
    });

    testWidgets('a late result opens the same note prompt as the Today tab', (t) async {
      final service = FakeAttendanceService()
        ..onMark = (_) => recJson(inT: '10:40', late: 40, lateStatus: 'needs_note');
      final h = _Harness(service: service);
      await _pump(t, h);
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(find.text('Why were you late?'), findsOneWidget);
    });

    testWidgets('shift over with no check-in: yellow, and a tap explains', (t) async {
      final service = FakeAttendanceService()..today = todayJson(time: '19:30');
      final h = _Harness(service: service);
      await _pump(t, h);
      h.location
        ..distance = 5
        ..emit(_inside);
      await _settle(t);
      expect(_visual(t).tone, RingTone.yellow);
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(find.textContaining('shift is over'), findsOneWidget);
      expect(h.service.markCalls, isEmpty);
      expect(h.biometric.calls, 0);
    });

    testWidgets('a mark in flight shows a busy state and ignores a second tap', (t) async {
      final service = FakeAttendanceService()..markGate = Completer();
      final h = _Harness(service: service);
      await _pump(t, h);
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await t.pump(const Duration(milliseconds: 100));
      expect(_visual(t).busy, isTrue);
      expect(t.getSemantics(find.byKey(const ValueKey('dashboard-ring'))).flagsCollection.isEnabled.name, isNot('isTrue'));
      await t.tap(find.byKey(const ValueKey('dashboard-ring')), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 100));
      service.markGate!.complete();
      await _settle(t);
      expect(service.markCalls, hasLength(1));
    });

    testWidgets('reduced motion gives a static ring; otherwise it turns', (t) async {
      final h = _Harness();
      await _pump(t, h, disableAnimations: true);
      expect(t.hasRunningAnimations, isFalse);
      await t.pumpWidget(const SizedBox());

      final h2 = _Harness();
      await _pump(t, h2);
      expect(t.hasRunningAnimations, isTrue);
    });

    testWidgets('it has an accessible label that names the action and the situation', (t) async {
      final h = _Harness();
      await _pump(t, h);
      expect(find.bySemanticsLabel(RegExp('Mark present.*not in range')), findsOneWidget);
    });

    testWidgets('any failure fetching attendance hides the button and touches nothing else', (t) async {
      final service = FakeAttendanceService()..todayError = const BackendException('Could not reach the server.');
      final h = _Harness(service: service);
      await _pump(t, h);
      expect(find.byType(RingVisual), findsNothing);
      expect(t.takeException(), isNull);
      expect(h.location.watching, isFalse);
    });

    testWidgets('not configured: hidden', (t) async {
      final service = FakeAttendanceService()..today = todayJson(configured: false);
      final h = _Harness(service: service);
      await _pump(t, h);
      expect(find.byType(RingVisual), findsNothing);
    });

    testWidgets('PC or web: hidden, and attendance is never fetched', (t) async {
      final h = _Harness(canMark: false);
      await _pump(t, h);
      expect(find.byType(RingVisual), findsNothing);
      expect(t.takeException(), isNull);
      expect(h.service.todayCalls, 0);
    });

    testWidgets('a mark refreshes the shared providers the Attendance screen reads', (t) async {
      final h = _Harness();
      await _pump(t, h);
      final before = h.service.todayCalls;
      await t.tap(find.byKey(const ValueKey('dashboard-ring')));
      await _settle(t);
      expect(h.service.todayCalls, greaterThan(before));
      // The ring itself now shows the new state (checked in -> check-out next).
      expect(find.bySemanticsLabel(RegExp('Mark check-out')), findsOneWidget);
    });
  });
}
