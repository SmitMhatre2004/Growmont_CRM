import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/legal/legal_screen.dart';

/// Fixed pumps rather than [WidgetTester.pumpAndSettle]: a tab whose document
/// is still loading shows a [CircularProgressIndicator], which never goes idle.
Future<void> _pumpDocs(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openLegal(
  WidgetTester tester, {
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: const LegalScreen()),
  );
  await _pumpDocs(tester);
}

/// The viewer renders the bundled .md files directly, so these assert against
/// the real documents rather than a fixture - a doc that stops loading, or a
/// heading that stops parsing, fails here.
void main() {
  testWidgets('every bundled document loads and renders its title', (
    tester,
  ) async {
    await _openLegal(tester);

    const titles = [
      'Privacy Policy',
      'Terms of Service',
      'End User Licence Agreement',
    ];

    for (var i = 0; i < kLegalDocuments.length; i++) {
      await tester.tap(find.text(kLegalDocuments[i].label));
      await _pumpDocs(tester);
      expect(
        find.text(titles[i]),
        findsOneWidget,
        reason: '${kLegalDocuments[i].asset} did not render its title',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('markdown is parsed rather than shown raw', (tester) async {
    await _openLegal(tester);

    final leaked = find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      return s.contains('##') || s.contains('**') || s.trim() == '---';
    });
    expect(leaked, findsNothing, reason: 'raw markdown reached the screen');
  });

  group('parseLegalMarkdown', () {
    test('maps each syntax to its block kind', () {
      final blocks = parseLegalMarkdown('''
# Title

## Section

---

A plain paragraph.

- first bullet
- second bullet
''');

      expect(
        blocks.map((b) => b.kind).toList(),
        [
          LegalBlockKind.h1,
          LegalBlockKind.h2,
          LegalBlockKind.rule,
          LegalBlockKind.paragraph,
          LegalBlockKind.bullet,
          LegalBlockKind.bullet,
        ],
      );
      expect(blocks.first.text, 'Title');
      expect(blocks[1].text, 'Section');
      expect(blocks.last.text, 'second bullet');
    });

    test('joins hard-wrapped lines back into one paragraph', () {
      final blocks = parseLegalMarkdown(
        'A sentence that was wrapped\nacross three source\nlines.',
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, LegalBlockKind.paragraph);
      expect(
        blocks.single.text,
        'A sentence that was wrapped across three source lines.',
      );
    });

    test('folds an indented continuation into the bullet above it', () {
      final blocks = parseLegalMarkdown(
        '- Client records, such as names and\n  addresses entered by staff\n',
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, LegalBlockKind.bullet);
      expect(
        blocks.single.text,
        'Client records, such as names and addresses entered by staff',
      );
    });

    test('keeps bold markers for the renderer to style, not to print', () {
      final blocks = parseLegalMarkdown('**Your account.** The work email.');

      expect(blocks.single.text, startsWith('**Your account.**'));

      // The widget layer strips the markers into a styled span.
      final text = (blocks.single.toWidget() as Padding).child! as Text;
      final children = (text.textSpan! as TextSpan).children!;
      expect((children.first as TextSpan).text, 'Your account.');
      expect(
        (children.first as TextSpan).style?.fontWeight,
        FontWeight.w600,
      );
      expect(text.textSpan!.toPlainText(), isNot(contains('**')));
    });
  });
}
