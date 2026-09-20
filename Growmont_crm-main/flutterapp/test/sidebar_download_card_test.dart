import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/mobile_install.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';
import 'package:growmont_crm/shared/widgets/sidebar_app_download_card.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      user: AppUser(
        id: '1',
        email: 'admin@growmont.com',
        name: 'Admin User',
        role: UserRole.admin,
      ),
    );
  }
}

/// Pins this computer's override without touching SharedPreferences.
class _FixedOverride extends SidebarQrOverride {
  _FixedOverride(this._value);

  final bool? _value;

  @override
  bool? build() => _value;
}

Widget _frame(Widget card, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 195,
          height: 600,
          child: Column(children: [card]),
        ),
      ),
    ),
  );
}

Widget _host({
  required bool installed,
  double t = 1.0,
  bool? deviceOverride,
}) {
  return _frame(
    SidebarAppDownloadCard(t: t),
    overrides: [
      mobileAppInstalledProvider.overrideWith((ref) => Stream.value(installed)),
      sidebarQrOverrideProvider.overrideWith(() => _FixedOverride(deviceOverride)),
    ],
  );
}

void main() {
  testWidgets('offers the QR while the account has no mobile install', (
    tester,
  ) async {
    await tester.pumpWidget(_host(installed: false));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Get the mobile app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disappears entirely once the account has signed in on a phone', (
    tester,
  ) async {
    await tester.pumpWidget(_host(installed: true));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Get the mobile app'), findsNothing);
  });

  testWidgets('collapsed rail shows the rule only, never a shrunken QR', (
    tester,
  ) async {
    await tester.pumpWidget(_host(installed: false, t: 0.0));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown answer keeps the card visible rather than hiding it', (
    tester,
  ) async {
    // The real providers, with no Firebase behind them — the state a desktop
    // is in while offline or before Firestore first answers. It must degrade
    // to "not installed" and keep the card, never throw out of build and never
    // suppress the card for everyone.
    await tester.pumpWidget(
      _frame(
        const SidebarAppDownloadCard(t: 1.0),
        overrides: [authProvider.overrideWith(() => _FakeAuthNotifier())],
      ),
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('this computer can force the QR back after a phone sign-in', (
    tester,
  ) async {
    await tester.pumpWidget(_host(installed: true, deviceOverride: true));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('this computer can dismiss the QR before any phone sign-in', (
    tester,
  ) async {
    await tester.pumpWidget(_host(installed: false, deviceOverride: false));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
  });
}
