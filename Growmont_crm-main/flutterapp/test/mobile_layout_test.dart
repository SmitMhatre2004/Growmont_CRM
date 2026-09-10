import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/shared/widgets/app_bottom_nav.dart';
import 'package:growmont_crm/shared/widgets/toolbar_action_button.dart';

/// Widths of real phones, smallest first. 320 is the narrowest Android
/// viewport still in common use.
const _phoneWidths = <double>[320, 360, 412];

Future<Object?> _pump(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  );
  await tester.pump();
  return tester.takeException();
}

List<BottomNavItem> _items({required bool isAdmin}) => [
  const BottomNavItem(
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard,
    label: 'Dashboard',
    branchIndex: 0,
  ),
  const BottomNavItem(
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart,
    label: 'Sales',
    branchIndex: 1,
  ),
  const BottomNavItem(
    icon: Icons.chat_bubble_outline,
    activeIcon: Icons.chat_bubble,
    label: 'Chats',
    branchIndex: 2,
  ),
  const BottomNavItem(
    icon: Icons.handshake_outlined,
    activeIcon: Icons.handshake,
    label: 'Clients',
    branchIndex: 3,
  ),
  if (isAdmin)
    const BottomNavItem(
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view,
      label: 'More',
      branchIndex: BottomNavItem.moreBranch,
    ),
];

void main() {
  group('AppBottomNav', () {
    for (final isAdmin in [true, false]) {
      final role = isAdmin ? 'admin (5 items)' : 'employee (4 items)';
      for (final width in _phoneWidths) {
        testWidgets('$role renders without overflow at ${width.toInt()}px', (
          tester,
        ) async {
          final error = await _pump(
            tester,
            Scaffold(
              bottomNavigationBar: AppBottomNav(
                items: _items(isAdmin: isAdmin),
                currentBranch: 0,
                onSelect: (_) {},
                onMore: () {},
              ),
            ),
            size: Size(width, 720),
          );
          expect(error, isNull, reason: 'overflowed at ${width}px, $role');
        });
      }
    }

    testWidgets('survives a 1.6x font scale on the narrowest phone', (
      tester,
    ) async {
      final error = await _pump(
        tester,
        Scaffold(
          bottomNavigationBar: AppBottomNav(
            items: _items(isAdmin: true),
            currentBranch: 0,
            onSelect: (_) {},
            onMore: () {},
          ),
        ),
        size: const Size(320, 720),
        textScale: 1.6,
      );
      expect(error, isNull);
    });

    testWidgets('reports the tapped branch index', (tester) async {
      int? tapped;
      await _pump(
        tester,
        Scaffold(
          bottomNavigationBar: AppBottomNav(
            items: _items(isAdmin: true),
            currentBranch: 0,
            onSelect: (i) => tapped = i,
            onMore: () {},
          ),
        ),
        size: const Size(360, 720),
      );
      await tester.tap(find.text('Clients'));
      expect(tapped, 3);
    });

    testWidgets('"More" opens the sheet instead of switching branch', (
      tester,
    ) async {
      var moreOpened = false;
      int? branchSwitched;
      await _pump(
        tester,
        Scaffold(
          bottomNavigationBar: AppBottomNav(
            items: _items(isAdmin: true),
            currentBranch: 0,
            onSelect: (i) => branchSwitched = i,
            onMore: () => moreOpened = true,
          ),
        ),
        size: const Size(360, 720),
      );
      await tester.tap(find.text('More'));
      expect(moreOpened, isTrue);
      expect(branchSwitched, isNull);
    });

    testWidgets('a branch behind "More" highlights the More entry', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          bottomNavigationBar: AppBottomNav(
            items: _items(isAdmin: true),
            currentBranch: 4, // Employees — not a visible destination
            onSelect: (_) {},
            onMore: () {},
          ),
        ),
        size: const Size(360, 720),
      );
      // The selected cell swaps to its filled icon.
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.byIcon(Icons.dashboard), findsNothing);
    });
  });

  group('Toolbar actions', () {
    /// The real toolbar: two secondary actions plus the primary add button.
    Widget toolbar() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppToolbarButton(
          icon: Icons.download_outlined,
          label: 'Export',
          onPressed: () {},
        ),
        const SizedBox(width: AppSpacing.sm),
        AppToolbarButton(
          icon: Icons.upload_outlined,
          label: 'Import',
          onPressed: () {},
        ),
        const SizedBox(width: AppSpacing.sm),
        AppToolbarButton(
          icon: Icons.add,
          label: 'Add',
          isPrimary: true,
          onPressed: () {},
        ),
      ],
    );

    for (final width in _phoneWidths) {
      testWidgets('fit inside a ${width.toInt()}px screen gutter', (
        tester,
      ) async {
        // 16pt page gutter each side, matching AppLayout.pagePadding on mobile.
        final available = width - AppSpacing.lg * 2;
        final error = await _pump(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: available, child: toolbar()),
            ),
          ),
          size: Size(width, 720),
        );
        expect(error, isNull, reason: 'toolbar overflowed at ${width}px');

        final rowWidth = tester.getSize(find.byType(Row).first).width;
        expect(
          rowWidth,
          lessThanOrEqualTo(available),
          reason: 'toolbar is ${rowWidth}pt wide but only ${available}pt fit',
        );
      });
    }

    testWidgets('secondary actions drop their labels on phones', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(body: toolbar()),
        size: const Size(360, 720),
      );
      // Labels survive only as tooltips, so no visible Export/Import text.
      expect(find.text('Export'), findsNothing);
      expect(find.text('Import'), findsNothing);
      // The primary action keeps its label.
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('secondary actions keep their labels on desktop', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(body: toolbar()),
        size: const Size(1280, 800),
      );
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
    });
  });
}
