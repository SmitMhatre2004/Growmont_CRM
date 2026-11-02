import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/interactions/widgets/interaction_detail_modal.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/user.dart';

void main() {
  const sampleInteraction = Interaction(
    id: 'test_interaction_1',
    date: '2026-09-29',
    clientName: 'Sunita Sharma',
    clientId: 'client_123',
    clientContact: '+91 98765 43210',
    employee: 'emp_456',
    employeeName: 'Rahul Verma',
    followUpDate: '2026-10-05',
    followUpTime: '14:30:00',
    priority: 'HIGH',
    discussionNotes:
        'Detailed client meeting discussing retirement portfolio expansion.\n'
        'Client expressed strong interest in high-yield debt funds and SIP increment.\n'
        'Action items:\n'
        '1. Send customized portfolio proposal by Friday.\n'
        '2. Schedule follow-up call on October 5 at 2:30 PM.',
  );

  Widget createSubject({
    Interaction interaction = sampleInteraction,
    AppUser? user,
    VoidCallback? onUpdated,
  }) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: InteractionDetailModal(
            interaction: interaction,
            currentUser: user,
            onUpdated: onUpdated,
          ),
        ),
      ),
    );
  }

  testWidgets('InteractionDetailModal renders notes prominently with personal data', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    // Verify title and notes header
    expect(find.text('Client Interaction'), findsOneWidget);
    expect(find.text('DISCUSSION NOTES'), findsOneWidget);

    // Verify notes content is present in full
    expect(find.textContaining('Detailed client meeting discussing retirement'), findsOneWidget);
    expect(find.textContaining('Send customized portfolio proposal by Friday'), findsOneWidget);

    // Verify word count badge
    expect(find.textContaining('words'), findsOneWidget);

    // Verify personal metadata is present
    expect(find.text('Sunita Sharma'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('Rahul Verma'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);

    // Verify action button
    expect(find.text('Edit Interaction'), findsOneWidget);

    // Verify both client & metadata and discussion notes cards have the exact same height
    final clientCard = find.ancestor(
      of: find.text('CLIENT & METADATA'),
      matching: find.byType(Container),
    ).last;
    final notesCard = find.ancestor(
      of: find.text('DISCUSSION NOTES'),
      matching: find.byType(Container),
    ).last;
    expect(tester.getSize(clientCard).height, equals(tester.getSize(notesCard).height));
  });

  testWidgets('Switching to Edit mode shows the standard interaction form', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createSubject());
    await tester.pump();

    // Tap on Edit Interaction button
    await tester.tap(find.text('Edit Interaction'));
    await tester.pumpAndSettle();

    // Same fields as the Add Interaction form, with the notes pre-filled
    expect(find.text('Edit Interaction'), findsOneWidget);
    expect(find.textContaining('Discussion notes'), findsOneWidget);
    expect(find.text('Interaction date'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.textContaining('Detailed client meeting'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel returns back to Read mode
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('DISCUSSION NOTES'), findsOneWidget);
    expect(find.text('Edit Interaction'), findsOneWidget);
  });

  testWidgets('Follow-up is optional: toggle reveals the date and time fields', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const noFollowUp = Interaction(
      id: 'test_interaction_2',
      date: '2026-09-29',
      clientName: 'Sunita Sharma',
      clientContact: '+91 98765 43210',
      employee: 'emp_456',
      followUpDate: '',
      followUpTime: '',
      priority: 'LOW',
    );

    await tester.pumpWidget(createSubject(interaction: noFollowUp));
    await tester.pump();
    await tester.tap(find.text('Edit Interaction'));
    await tester.pumpAndSettle();

    // Off by default when the interaction has no follow-up.
    final toggle = find.byType(Switch);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('Follow-up date'), findsNothing);
    expect(find.text('Follow-up time'), findsNothing);

    await tester.tap(find.text('Follow-up'));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.text('Follow-up date'), findsOneWidget);
    expect(find.text('Follow-up time'), findsOneWidget);
  });

  testWidgets('InteractionDetailModal adapts to mobile viewport without RenderFlex overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createSubject());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Sunita Sharma'), findsOneWidget);
    expect(find.textContaining('Detailed client meeting'), findsOneWidget);
  });
}
