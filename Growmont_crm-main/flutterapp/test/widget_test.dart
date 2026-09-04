import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:growmont_crm/main.dart';

void main() {
  testWidgets('App smoke test — renders without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: GrowmontApp()));
    await tester.pump();

    // Shows loading spinner while auth session restores from secure storage.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
