import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/shared/widgets/app_form.dart';
import 'package:growmont_crm/shared/widgets/app_modal_shell.dart';
import 'package:growmont_crm/shared/widgets/password_form_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget body, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: body),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every kind of input renders at the same height', (
    tester,
  ) async {
    final password = TextEditingController();
    addTearDown(password.dispose);

    await pump(
      tester,
      SizedBox(
        width: 400,
        child: AppFormColumn(
          children: [
            const AppFormField(
              label: 'Text',
              child: TextField(key: Key('text')),
            ),
            AppFormField(
              label: 'Dropdown',
              child: AppDropdownField<String>(
                key: const Key('dropdown'),
                value: 'a',
                items: const [DropdownMenuItem(value: 'a', child: Text('A'))],
                onChanged: (_) {},
              ),
            ),
            AppFormField(
              label: 'Date',
              child: AppDateField(
                key: const Key('date'),
                value: DateTime(2026, 9, 30),
                onChanged: (_) {},
              ),
            ),
            AppFormField(
              label: 'Time',
              child: AppTimeField(
                key: const Key('time'),
                value: null,
                onChanged: (_) {},
              ),
            ),
            const AppFormField(
              label: 'Read only',
              child: AppReadOnlyField(key: Key('readonly'), value: 'Rahul'),
            ),
            KeyedSubtree(
              key: const Key('password'),
              child: PasswordFormField(controller: password),
            ),
          ],
        ),
      ),
    );

    double inputHeight(String key) {
      final decorator = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(InputDecorator),
      );
      return tester.getSize(decorator.first).height;
    }

    final expected = inputHeight('text');
    for (final key in ['dropdown', 'date', 'time', 'readonly', 'password']) {
      expect(inputHeight(key), expected, reason: '$key input height');
    }
  });

  testWidgets('labels sit above their input, not inside it', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 400,
        child: AppFormField(
          label: 'Client name',
          child: TextField(key: Key('input')),
        ),
      ),
    );
    final label = tester.getRect(find.text('Client name'));
    final input = tester.getRect(find.byKey(const Key('input')));
    expect(label.bottom, lessThanOrEqualTo(input.top));
  });

  testWidgets('optional fields say so; required ones carry no marker', (
    tester,
  ) async {
    await pump(
      tester,
      const Column(
        children: [
          AppFormField(label: 'Remarks', optional: true, child: TextField()),
          AppFormField(label: 'Amount', child: TextField()),
        ],
      ),
    );
    expect(find.textContaining('Optional'), findsOneWidget);
    expect(find.textContaining('*'), findsNothing);
  });

  testWidgets('toggle section reveals its fields only when switched on', (
    tester,
  ) async {
    var on = false;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppToggleSection(
          title: 'Follow-up',
          value: on,
          onChanged: (v) => setState(() => on = v),
          child: const Text('revealed'),
        ),
      ),
    );
    expect(find.text('revealed'), findsNothing);
    await tester.tap(find.text('Follow-up'));
    await tester.pumpAndSettle();
    expect(find.text('revealed'), findsOneWidget);
  });

  group('AppFormActions', () {
    testWidgets('right-aligned Cancel + primary on desktop', (tester) async {
      await pump(
        tester,
        AppFormActions(submitLabel: 'Save Client', onSubmit: () {}),
      );
      final cancel = tester.getRect(find.text('Cancel'));
      final save = tester.getRect(find.text('Save Client'));
      expect(cancel.right, lessThan(save.left));
      expect(save.right, greaterThan(1100));
    });

    testWidgets('busy disables both buttons and swaps the label', (
      tester,
    ) async {
      await pump(
        tester,
        AppFormActions(submitLabel: 'Save', busy: true, onSubmit: () {}),
      );
      expect(find.text('Saving...'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });
  });

  testWidgets('modal footer stays visible while a long body scrolls', (
    tester,
  ) async {
    await pump(
      tester,
      AppModalShell(
        title: 'Add Sale',
        footer: AppFormActions(submitLabel: 'Save Sale', onSubmit: () {}),
        child: AppFormColumn(
          children: [
            for (var i = 0; i < 30; i++)
              AppFormField(label: 'Field $i', child: const TextField()),
          ],
        ),
      ),
      size: const Size(1200, 600),
    );
    expect(tester.takeException(), isNull);
    final save = tester.getRect(find.text('Save Sale'));
    expect(save.bottom, lessThanOrEqualTo(600));
  });
}
