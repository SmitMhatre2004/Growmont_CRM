import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:growmont_crm/main.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';

class _MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(isLoading: true);
  }
}

void main() {
  testWidgets('App smoke test — renders without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _MockAuthNotifier()),
        ],
        child: const GrowmontApp(),
      ),
    );
    await tester.pump();

    // Shows loading spinner while auth session restores.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
