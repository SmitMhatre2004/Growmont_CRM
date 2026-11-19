import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/shared/widgets/reorderable_columns.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A table shaped like the Interactions / Sales ones, with fake data: a fixed
/// checkbox, four reorderable columns of different widths, a fixed actions
/// column, all inside one horizontal scroll view.
const _columns = [
  ReorderColumn('a', 4),
  ReorderColumn('b', 3),
  ReorderColumn('c', 2),
  ReorderColumn('d', 3),
];

class _Table extends StatefulWidget {
  const _Table({
    required this.controller,
    this.scroll,
    this.onSort,
    this.onRowTap,
    this.enabled = true,
  });

  final ColumnOrderController controller;
  final ScrollController? scroll;
  final ValueChanged<String>? onSort;
  final ValueChanged<int>? onRowTap;
  final bool enabled;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final order = c.orderFor(reorderable: widget.enabled);
    return SingleChildScrollView(
      controller: widget.scroll,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 850,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 36,
                  height: 48,
                  child: Checkbox(
                    key: Key('hdr-check'),
                    value: false,
                    onChanged: null,
                  ),
                ),
                Expanded(
                  child: ReorderableColumnHeaders(
                    controller: c,
                    enabled: widget.enabled,
                    cellBuilder: (context, id) => InkWell(
                      onTap: () => widget.onSort?.call(id),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: Text(id.toUpperCase(), key: Key('h-$id')),
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 76,
                  child: Text('ACTIONS', key: Key('hdr-actions')),
                ),
              ],
            ),
            for (var r = 0; r < 2; r++)
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 40,
                    child: Checkbox(
                      key: Key('row$r-check'),
                      value: false,
                      onChanged: (_) {},
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => widget.onRowTap?.call(r),
                      child: Row(
                        children: orderedRowCells(order, {
                          for (final col in _columns)
                            col.id: Expanded(
                              flex: c.flexOf(col.id),
                              child: Center(
                                child: Text(
                                  'r$r-${col.id}',
                                  key: Key('r$r-${col.id}'),
                                ),
                              ),
                            ),
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 76, child: Text('edit')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<ColumnOrderController> _controller({
  Map<String, Object> saved = const {},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final c = ColumnOrderController(tableId: 'test', columns: _columns);
  await c.load();
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  Widget table, {
  double width = 500,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 300, child: table),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Long-press [from] and drag it to [to], optionally releasing there.
Future<TestGesture> _pickUp(
  WidgetTester tester,
  Finder from,
  Offset to, {
  bool release = true,
}) async {
  // Measured once: while dragging, the key is on the feedback as well.
  final start = tester.getCenter(from);
  final g = await tester.startGesture(start);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  for (var i = 1; i <= 8; i++) {
    await g.moveTo(Offset.lerp(start, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (release) {
    await g.up();
    await tester.pumpAndSettle();
  }
  return g;
}

double _x(WidgetTester t, String key) => t.getTopLeft(find.byKey(Key(key))).dx;

void main() {
  group('column order bookkeeping', () {
    test(
      'reconcile drops unknown ids, ignores repeats, appends new columns',
      () {
        expect(
          ColumnOrderController.reconcile(
            ['d', 'zzz', 'a', 'd'],
            ['a', 'b', 'c', 'd'],
          ),
          ['d', 'a', 'b', 'c'],
        );
        expect(ColumnOrderController.reconcile(null, ['a', 'b']), ['a', 'b']);
        expect(ColumnOrderController.reconcile([], ['a', 'b']), ['a', 'b']);
        expect(ColumnOrderController.reconcile(['x', 'y'], ['a', 'b']), [
          'a',
          'b',
        ]);
      },
    );

    test(
      'swap exchanges two columns; unknown ids and self-drops do nothing',
      () async {
        final c = await _controller();
        c.swap('a', 'c');
        expect(c.order, ['c', 'b', 'a', 'd']);
        c.swap('b', 'b');
        c.swap('nope', 'a');
        c.swap('a', 'nope');
        expect(c.order, ['c', 'b', 'a', 'd']);
      },
    );

    test('the order is saved and read back', () async {
      final c = await _controller();
      c.swap('a', 'd');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(ColumnOrderController.prefsKey('test')), [
        'd',
        'b',
        'c',
        'a',
      ]);
      final again = ColumnOrderController(tableId: 'test', columns: _columns);
      await again.load();
      expect(again.order, ['d', 'b', 'c', 'a']);
    });

    test(
      'a stale saved order from an older app version is tolerated',
      () async {
        final key = ColumnOrderController.prefsKey('test');
        // 'old' was removed, 'b' and 'd' did not exist yet when this was saved.
        final c = await _controller(
          saved: {
            key: ['c', 'old', 'a'],
          },
        );
        expect(c.order, ['c', 'a', 'b', 'd']);
      },
    );

    test('tables keep separate orders', () async {
      SharedPreferences.setMockInitialValues({});
      final x = ColumnOrderController(tableId: 'x', columns: _columns);
      final y = ColumnOrderController(tableId: 'y', columns: _columns);
      x.swap('a', 'b');
      await Future<void>.delayed(Duration.zero);
      await y.load();
      expect(y.order, ['a', 'b', 'c', 'd']);
    });

    test('a column keeps its own flex', () async {
      final c = await _controller();
      c.swap('a', 'd');
      expect([for (final id in c.order) c.flexOf(id)], [3, 3, 2, 4]);
    });
  });

  group('reordering on the table', () {
    testWidgets('long-press and drop swaps header and every row cell', (
      tester,
    ) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final c = await _controller();
      await _pump(tester, _Table(controller: c));
      expect(_x(tester, 'h-a') < _x(tester, 'h-b'), isTrue);

      await _pickUp(
        tester,
        find.byKey(const Key('h-a')),
        tester.getCenter(find.byKey(const Key('h-b'))),
      );

      expect(c.order, ['b', 'a', 'c', 'd']);
      expect(_x(tester, 'h-b') < _x(tester, 'h-a'), isTrue);
      expect(_x(tester, 'h-a') < _x(tester, 'h-c'), isTrue);
      for (final r in [0, 1]) {
        expect(_x(tester, 'r$r-b') < _x(tester, 'r$r-a'), isTrue);
        expect(_x(tester, 'r$r-a') < _x(tester, 'r$r-c'), isTrue);
        // Header and cells of a column line up.
        expect(
          tester.getCenter(find.byKey(Key('r$r-a'))).dx,
          closeTo(tester.getCenter(find.byKey(const Key('h-a'))).dx, 0.5),
        );
      }
      expect(haptics, contains('HapticFeedbackType.selectionClick'));
    });

    testWidgets('each column keeps its own width after a swap', (tester) async {
      final c = await _controller();
      await _pump(tester, _Table(controller: c));
      Size size(String k) => tester.getSize(find.byKey(Key(k)));
      // Column widths come from the column's own cell (Expanded + Center).
      double cellWidth(String id) => tester
          .getSize(
            find
                .ancestor(
                  of: find.byKey(Key('r0-$id')),
                  matching: find.byType(Center),
                )
                .first,
          )
          .width;
      final before = {for (final col in _columns) col.id: cellWidth(col.id)};
      expect(
        before['a']! > before['b']! && before['b']! > before['c']!,
        isTrue,
      );
      final tableWidth = size('hdr-actions').width;

      await _pickUp(
        tester,
        find.byKey(const Key('h-a')),
        tester.getCenter(find.byKey(const Key('h-b'))),
      );
      expect(c.order, ['b', 'a', 'c', 'd']);

      for (final col in _columns) {
        expect(
          cellWidth(col.id),
          closeTo(before[col.id]!, 0.01),
          reason: col.id,
        );
      }
      expect(size('hdr-actions').width, tableWidth);
    });

    testWidgets(
      'tap still sorts, before and after a reorder; row tap still works',
      (tester) async {
        final sorted = <String>[];
        final taps = <int>[];
        final c = await _controller();
        await _pump(
          tester,
          _Table(controller: c, onSort: sorted.add, onRowTap: taps.add),
        );
        await tester.tap(find.byKey(const Key('h-b')));
        await tester.pump();
        expect(sorted, ['b']);

        await _pickUp(
          tester,
          find.byKey(const Key('h-a')),
          tester.getCenter(find.byKey(const Key('h-b'))),
        );
        expect(c.order, ['b', 'a', 'c', 'd']);
        // A reorder is not a tap.
        expect(sorted, ['b']);

        await tester.tap(find.byKey(const Key('h-a')));
        await tester.pump();
        expect(sorted, ['b', 'a']);

        await tester.tap(find.byKey(const Key('r1-b')));
        await tester.pump();
        expect(taps, [1]);
      },
    );

    testWidgets(
      'a plain horizontal drag scrolls the table and does not reorder',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final c = await _controller();
        await _pump(tester, _Table(controller: c, scroll: scroll));
        await tester.drag(find.byKey(const Key('h-a')), const Offset(-200, 0));
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(100));
        expect(c.order, ['a', 'b', 'c', 'd']);

        // Same from the data rows.
        await tester.drag(find.byKey(const Key('r0-b')), const Offset(150, 0));
        await tester.pumpAndSettle();
        expect(c.order, ['a', 'b', 'c', 'd']);
      },
    );

    testWidgets('the checkbox and actions columns are fixed', (tester) async {
      final c = await _controller();
      await _pump(tester, _Table(controller: c));
      expect(
        find.ancestor(
          of: find.byKey(const Key('hdr-check')),
          matching: find.byType(LongPressDraggable<String>),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('hdr-actions')),
          matching: find.byType(LongPressDraggable<String>),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('hdr-check')),
          matching: find.byType(DragTarget<String>),
        ),
        findsNothing,
      );

      // Long-press the checkbox and drag it over a column: nothing moves.
      await _pickUp(
        tester,
        find.byKey(const Key('hdr-check')),
        tester.getCenter(find.byKey(const Key('h-b'))),
      );
      expect(c.order, ['a', 'b', 'c', 'd']);

      // Drop a column on the checkbox cell: nothing moves.
      await _pickUp(
        tester,
        find.byKey(const Key('h-a')),
        tester.getCenter(find.byKey(const Key('hdr-check'))),
      );
      expect(c.order, ['a', 'b', 'c', 'd']);
      expect(_x(tester, 'hdr-check') < _x(tester, 'h-a'), isTrue);
    });

    testWidgets(
      'dropping a column back on itself or on nothing changes nothing',
      (tester) async {
        final c = await _controller();
        await _pump(tester, _Table(controller: c));
        await _pickUp(
          tester,
          find.byKey(const Key('h-a')),
          tester.getCenter(find.byKey(const Key('h-a'))) + const Offset(5, 0),
        );
        expect(c.order, ['a', 'b', 'c', 'd']);
        await _pickUp(
          tester,
          find.byKey(const Key('h-a')),
          const Offset(200, 250),
        );
        expect(c.order, ['a', 'b', 'c', 'd']);
      },
    );

    testWidgets(
      'the saved order is applied when the table opens, stale ids ignored',
      (tester) async {
        final c = await _controller(
          saved: {
            ColumnOrderController.prefsKey('test'): ['d', 'gone', 'a'],
          },
        );
        await _pump(tester, _Table(controller: c));
        expect(c.order, ['d', 'a', 'b', 'c']);
        expect(_x(tester, 'h-d') < _x(tester, 'h-a'), isTrue);
        expect(_x(tester, 'h-a') < _x(tester, 'h-b'), isTrue);
        expect(_x(tester, 'r0-d') < _x(tester, 'r0-a'), isTrue);
      },
    );

    testWidgets(
      'when disabled (PC / wide) the default order shows and nothing drags',
      (tester) async {
        final c = await _controller(
          saved: {
            ColumnOrderController.prefsKey('test'): ['d', 'c', 'b', 'a'],
          },
        );
        await _pump(tester, _Table(controller: c, enabled: false));
        expect(find.byType(LongPressDraggable<String>), findsNothing);
        expect(_x(tester, 'h-a') < _x(tester, 'h-b'), isTrue);
        expect(_x(tester, 'r0-a') < _x(tester, 'r0-b'), isTrue);
      },
    );

    testWidgets('dragging near the right edge scrolls the table', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final c = await _controller();
      await _pump(tester, _Table(controller: c, scroll: scroll));
      expect(scroll.offset, 0);
      final g = await _pickUp(
        tester,
        find.byKey(const Key('h-a')),
        const Offset(494, 24),
        release: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.offset, greaterThan(50));
      final during = scroll.offset;

      // Back to the middle: it stops.
      await g.moveTo(const Offset(250, 24));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scroll.offset, during);

      // And to the left edge: it scrolls back.
      await g.moveTo(const Offset(4, 24));
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.offset, lessThan(during));
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group('page swipe', () {
    testWidgets(
      'a reorder does not swipe the page, and a table scroll does not either',
      (tester) async {
        final pages = PageController();
        addTearDown(pages.dispose);
        final c = await _controller();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageView(
                controller: pages,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(height: 300, child: _Table(controller: c)),
                  ),
                  const Center(child: Text('next page')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final view = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(view.width, greaterThan(500));

        // Reorder with a long sideways sweep: the page stays put.
        final b = tester.getCenter(find.byKey(const Key('h-b')));
        await _pickUp(
          tester,
          find.byKey(const Key('h-a')),
          Offset(b.dx + 120, b.dy),
        );
        expect(pages.page, 0);
        expect(find.text('next page'), findsNothing);

        // Plain sideways drag on the table scrolls the table, not the pager.
        await tester.drag(find.byKey(const Key('h-a')), const Offset(-300, 0));
        await tester.pumpAndSettle();
        expect(pages.page, 0);
      },
    );
  });
}
