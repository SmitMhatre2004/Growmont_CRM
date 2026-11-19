import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import 'branch_container.dart' show PageSwipeGuard;

/// One reorderable data column: a stable [id] and its flex [flex].
///
/// The flex is the column's width. It is looked up by id, so a column carries
/// its own width to wherever it is moved; widths are never resized or evened
/// out by a reorder.
class ReorderColumn {
  const ReorderColumn(this.id, this.flex);

  final String id;
  final int flex;
}

/// The display order of one table's data columns, remembered on the device.
///
/// Only the DISPLAY order lives here. Sorting, filtering, search, export and
/// import all work on the data and never look at this order.
///
/// Selection and action columns are not part of it: they sit outside the
/// reorderable region, so they cannot be moved or dropped on.
class ColumnOrderController extends ChangeNotifier {
  ColumnOrderController({
    required this.tableId,
    required List<ReorderColumn> columns,
  }) : columns = List.unmodifiable(columns),
       _order = [for (final c in columns) c.id];

  final String tableId;
  final List<ReorderColumn> columns;
  List<String> _order;
  bool _disposed = false;

  /// SharedPreferences key holding this table's order (a string list).
  static String prefsKey(String tableId) => 'table_column_order.$tableId';

  /// Merges a saved order with the current columns after an app update: ids
  /// that no longer exist are dropped (and repeats ignored), columns that are
  /// new are appended at the end in their default order.
  static List<String> reconcile(
    Iterable<String>? saved,
    List<String> defaults,
  ) {
    final known = defaults.toSet();
    final result = <String>[];
    for (final id in saved ?? const <String>[]) {
      if (known.contains(id) && !result.contains(id)) result.add(id);
    }
    for (final id in defaults) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  List<String> get defaultIds => [for (final c in columns) c.id];

  /// The order to show on the phone.
  List<String> get order => List.unmodifiable(_order);

  /// The order to render: the saved order when [reorderable], else the
  /// default (PC / wide layout stays exactly as it always was).
  List<String> orderFor({required bool reorderable}) =>
      reorderable ? order : defaultIds;

  int flexOf(String id) {
    for (final c in columns) {
      if (c.id == id) return c.flex;
    }
    return 1;
  }

  /// Reads the saved order. Safe to call once; storage errors leave the
  /// default order in place.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = reconcile(
        prefs.getStringList(prefsKey(tableId)),
        defaultIds,
      );
      if (_disposed || _sameOrder(merged, _order)) return;
      _order = merged;
      notifyListeners();
    } catch (_) {
      // Keep the default order.
    }
  }

  /// Swaps the positions of two columns and remembers the result. Unknown ids
  /// and dropping a column on itself do nothing.
  void swap(String a, String b) {
    final i = _order.indexOf(a);
    final j = _order.indexOf(b);
    if (i < 0 || j < 0 || i == j) return;
    final next = [..._order];
    next[i] = b;
    next[j] = a;
    _order = next;
    notifyListeners();
    unawaited(_save());
  }

  /// Forgets the saved order and goes back to the default.
  Future<void> reset() async {
    _order = defaultIds;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey(tableId));
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey(tableId), _order);
    } catch (_) {
      // Not remembered this time; the order still applies for the session.
    }
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Puts the cells of one data row in [order]. Every cell must already be an
/// [Expanded] carrying its column's own flex (see [ColumnOrderController.flexOf]),
/// so a cell keeps its width wherever it lands. Ids without a cell are skipped.
List<Widget> orderedRowCells(List<String> order, Map<String, Widget> cells) => [
  for (final id in order)
    if (cells[id] != null) cells[id]!,
];

/// The data-column part of a table header. On the phone each header can be
/// long-pressed and dragged onto another column to swap their places. A
/// plain horizontal drag still scrolls the table; the reorder only starts
/// after the long press, and from then on it owns the gesture, so it never
/// turns into a table scroll or a page swipe. Near the left or right edge of
/// the table, the table scrolls itself.
///
/// Place it as `Expanded(child: ReorderableColumnHeaders(...))` between the
/// fixed checkbox cell and the fixed actions cell of the header row.
class ReorderableColumnHeaders extends StatefulWidget {
  const ReorderableColumnHeaders({
    super.key,
    required this.controller,
    required this.cellBuilder,
    this.enabled = true,
  });

  final ColumnOrderController controller;

  /// The header cell for [id] (title, sort indicator, tap to sort). Not
  /// wrapped in an Expanded; this widget does that.
  final Widget Function(BuildContext context, String id) cellBuilder;

  /// False on PC / wide layouts: the default order, no dragging.
  final bool enabled;

  @override
  State<ReorderableColumnHeaders> createState() =>
      _ReorderableColumnHeadersState();
}

class _ReorderableColumnHeadersState extends State<ReorderableColumnHeaders> {
  static const double _edgeZone = 56;
  static const double _maxStep = 16;

  Timer? _scrollTimer;
  double _step = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onOrderChanged);
  }

  @override
  void didUpdateWidget(ReorderableColumnHeaders old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onOrderChanged);
      widget.controller.addListener(_onOrderChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onOrderChanged);
    _stopAutoScroll();
    super.dispose();
  }

  void _onOrderChanged() {
    if (mounted) setState(() {});
  }

  // -- Auto-scroll near the edges ----------------------------------------

  void _onDragUpdate(DragUpdateDetails details) {
    final scrollable = Scrollable.maybeOf(context, axis: Axis.horizontal);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.hasSize) {
      _stopAutoScroll();
      return;
    }
    final x = box.globalToLocal(details.globalPosition).dx;
    final zone = math.min(_edgeZone, box.size.width / 3);
    double step = 0;
    if (x < zone) {
      step = -_maxStep * ((zone - x) / zone).clamp(0.0, 1.0);
    } else if (x > box.size.width - zone) {
      step = _maxStep * ((x - (box.size.width - zone)) / zone).clamp(0.0, 1.0);
    }
    _step = step;
    if (step == 0) {
      _stopAutoScroll();
    } else {
      _scrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _autoScrollTick(),
      );
    }
  }

  void _autoScrollTick() {
    if (!mounted || _step == 0) return;
    final scrollable = Scrollable.maybeOf(context, axis: Axis.horizontal);
    if (scrollable == null) return;
    final position = scrollable.position;
    final target = (position.pixels + _step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) position.jumpTo(target);
  }

  void _stopAutoScroll() {
    _step = 0;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  // -- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    if (!widget.enabled) {
      return Row(
        children: [
          for (final id in c.defaultIds)
            Expanded(
              key: ValueKey('header-$id'),
              flex: c.flexOf(id),
              child: widget.cellBuilder(context, id),
            ),
        ],
      );
    }
    return PageSwipeGuard(
      child: Row(
        children: [
          for (final id in c.order)
            Expanded(
              key: ValueKey('header-$id'),
              flex: c.flexOf(id),
              child: _buildDraggable(context, id),
            ),
        ],
      ),
    );
  }

  Widget _buildDraggable(BuildContext context, String id) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != id,
      onAcceptWithDetails: (d) => widget.controller.swap(d.data, id),
      builder: (context, candidates, _) {
        final isTarget = candidates.isNotEmpty;
        return LayoutBuilder(
          builder: (context, constraints) {
            final cell = AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: isTarget
                    ? AppColors.primaryBlue.withValues(alpha: 0.12)
                    : Colors.transparent,
                border: Border.all(
                  color: isTarget ? AppColors.primaryBlue : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: widget.cellBuilder(context, id),
            );
            return LongPressDraggable<String>(
              data: id,
              // HapticFeedback.selectionClick() on pick-up.
              hapticFeedbackOnStart: true,
              onDragUpdate: _onDragUpdate,
              onDragEnd: (_) => _stopAutoScroll(),
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.primaryBlue, width: 2),
                    boxShadow: AppShadows.md,
                  ),
                  child: widget.cellBuilder(context, id),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: cell),
              child: cell,
            );
          },
        );
      },
    );
  }
}
