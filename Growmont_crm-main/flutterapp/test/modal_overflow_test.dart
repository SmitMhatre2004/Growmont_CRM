import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/shared/widgets/app_modal_shell.dart';

/// Phone, small phone, and tablet. The first two sit below
/// [AppLayout.mobileBreakpoint]; the third above it.
const _sizes = <String, Size>{
  'small phone 320x640': Size(320, 640),
  'phone 360x740': Size(360, 740),
  'tablet 768x1024': Size(768, 1024),
};

/// Pumps [child] at [size] with [textScale] and returns any framework
/// exception (a RenderFlex overflow surfaces here).
Future<Object?> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.takeException();
}

/// A stand-in for the real modals' bodies: the widest things they contain are
/// a full-width dropdown holding a long name and a pair of side-by-side
/// fields. Both are what actually overflowed before `isExpanded` and
/// [modalFieldPair] were introduced.
Widget _representativeBody(BuildContext context) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<String>(
        initialValue: 'a',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sales Representative *'),
        items: const [
          DropdownMenuItem(
            value: 'a',
            child: Text(
              'Priyadarshini Venkataraghavan (ADMIN)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        onChanged: (_) {},
      ),
      const SizedBox(height: AppSpacing.lg),
      modalFieldPair(
        context,
        DropdownButtonFormField<String>(
          initialValue: 'gi',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Product *'),
          items: const [
            DropdownMenuItem(
              value: 'gi',
              child: Text(
                'General Insurance',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (_) {},
        ),
        const TextField(decoration: InputDecoration(labelText: 'Company *')),
      ),
    ],
  );
}

void main() {
  group('AppModalShell', () {
    for (final entry in _sizes.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        final error = await _pumpAt(
          tester,
          Builder(
            builder: (context) => AppModalShell(
              title: 'Add New Sale',
              child: _representativeBody(context),
            ),
          ),
          size: entry.value,
        );
        expect(error, isNull, reason: 'overflowed at ${entry.key}');
      });
    }

    testWidgets('long title ellipsizes instead of overflowing', (tester) async {
      final error = await _pumpAt(
        tester,
        const AppModalShell(
          title: 'Edit Interaction For A Client With A Very Long Name Indeed',
          child: SizedBox.shrink(),
        ),
        size: const Size(320, 640),
      );
      expect(error, isNull);
    });

    testWidgets('survives a 1.6x system font scale on a small phone', (
      tester,
    ) async {
      final error = await _pumpAt(
        tester,
        Builder(
          builder: (context) => AppModalShell(
            title: 'Add New Sale',
            child: _representativeBody(context),
          ),
        ),
        size: const Size(320, 640),
        textScale: 1.6,
      );
      expect(error, isNull);
    });
  });

  group('modalFieldPair', () {
    testWidgets('stacks into a Column below the mobile breakpoint', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: modalFieldPair(
              context,
              const Text('first'),
              const Text('second'),
            ),
          ),
        ),
        size: const Size(360, 740),
      );
      // A Row would mean side-by-side; below the breakpoint there must be none
      // wrapping the two fields.
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('first'), matching: find.byType(Row)),
        findsNothing,
      );
    });

    testWidgets('sits side by side at tablet width', (tester) async {
      await _pumpAt(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: modalFieldPair(
              context,
              const Text('first'),
              const Text('second'),
            ),
          ),
        ),
        size: const Size(1024, 768),
      );
      expect(
        find.ancestor(of: find.text('first'), matching: find.byType(Row)),
        findsWidgets,
      );
    });
  });
}
