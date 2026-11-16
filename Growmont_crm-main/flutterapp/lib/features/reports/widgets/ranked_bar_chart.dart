// lib/features/reports/widgets/ranked_bar_chart.dart
//
// Ranked horizontal bars: one row per category, largest first, all on one
// baseline, in a single hue.
//
// ── Why this and not a donut ──────────────────────────────────────────────
//
// Product mix here runs to seventeen categories with close values. That is
// precisely the case ranked bars answer and a donut cannot: segments laid
// end to end around a ring have no common baseline, so close values cannot
// be compared, and past about six parts adjacent slices blur together.
// Bars share a baseline, so the reader compares lengths directly and the
// ranking is the chart.
//
// ── Why one hue and not one colour per bar ────────────────────────────────
//
// Colouring each bar differently would be a value-ramp on nominal
// categories: it double-encodes bar length as hue, spends the only free
// channel on information the chart already shows, and fails the
// categorical colour checks by design. Products are an identity set with
// no natural order, so every bar takes the same accent and length alone
// carries magnitude. Highlighting the leader was considered and dropped
// for the same reason — the sort order already says which one won.
//
// ── Where the interest comes from instead ─────────────────────────────────
//
// Not decoration: more information, and better use of the row.
//   * a rank numeral, so the ordering is explicit rather than implied;
//   * the deal count under each name — a second measure the flat version
//     threw away;
//   * the amount set INSIDE the bar end where it fits (white on navy500 is
//     6.9:1), which is what buys back the horizontal space the old layout
//     wasted between label and bar. Where it does not fit, the figure sits
//     outside the end instead — measured with a TextPainter, never guessed,
//     so a label is never clipped by its own bar;
//   * bars that grow on entry, lightly staggered, so the eye follows the
//     ranking as it lands;
//   * a row hover state, so a long row stays readable across its width.

import 'package:flutter/material.dart';

import '../../../core/reports/monthly_report.dart';
import '../../../core/theme/app_theme.dart';
import 'report_chart_theme.dart';
import 'report_tables.dart' show rupeesFromPaise;

class RankedBarChart extends StatelessWidget {
  const RankedBarChart({
    super.key,
    required this.rows,
    this.maxRows = 8,
    this.showAmount = true,
    this.countNoun = 'deal',
    this.emptyMessage = 'Nothing to break down for this month',
    this.animate = true,
  });

  final List<CategoryTotal> rows;

  /// Rows past this fold into one "Other" bar, so the tail cannot turn the
  /// card into a wall of hairlines. Null shows everything.
  final int? maxRows;

  /// False for a breakdown with no money on it — interaction priority,
  /// say — where the count is the measure and an amount column would read
  /// as a column of zeroes.
  final bool showAmount;

  /// Singular noun for the secondary count, pluralized with an 's'.
  final String countNoun;

  final String emptyMessage;

  /// Entrance animation. Off in tests, so a pumpAndSettle cannot hang on a
  /// repeating-looking animation and assertions do not race the tween.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          emptyMessage,
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      );
    }

    final visible = _collapse(rows, maxRows);
    int measure(CategoryTotal r) => showAmount ? r.paise : r.count;
    final peak = visible.fold<int>(
      0,
      (best, r) => measure(r) > best ? measure(r) : best,
    );
    final total = visible.fold<int>(0, (sum, r) => sum + measure(r));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _Row(
            rank: i + 1,
            row: visible[i],
            fraction: peak == 0 ? 0 : measure(visible[i]) / peak,
            share: total == 0 ? 0 : measure(visible[i]) / total,
            showAmount: showAmount,
            countNoun: countNoun,
            animate: animate,
          ),
        ],
      ],
    );
  }

  /// Keeps the top rows and sums the tail into one "Other", so the shares
  /// still add to the whole.
  static List<CategoryTotal> _collapse(List<CategoryTotal> rows, int? limit) {
    if (limit == null || rows.length <= limit) return rows;

    final head = rows.take(limit - 1).toList();
    final tail = rows.skip(limit - 1);
    final label = rows.any((r) => r.label == 'Other')
        ? 'Other categories'
        : 'Other';

    return [
      ...head,
      CategoryTotal(
        label: '$label (${tail.length})',
        paise: tail.fold<int>(0, (sum, r) => sum + r.paise),
        count: tail.fold<int>(0, (sum, r) => sum + r.count),
      ),
    ];
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.rank,
    required this.row,
    required this.fraction,
    required this.share,
    required this.showAmount,
    required this.countNoun,
    required this.animate,
  });

  final int rank;
  final CategoryTotal row;
  final double fraction;
  final double share;
  final bool showAmount;
  final String countNoun;
  final bool animate;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.showAmount
        ? rupeesFromPaise(widget.row.paise)
        : '${widget.row.count}';
    final sharePercent = widget.share >= 0.1 || widget.share == 0
        ? '${(widget.share * 100).round()}%'
        : '${(widget.share * 100).toStringAsFixed(1)}%';
    final count = widget.row.count;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Later rows take slightly longer, which reads as a stagger
            // down the ranking without needing a controller.
            final duration =
                AppMotion.slow + Duration(milliseconds: widget.rank * 45);

            // Where the card is narrow — the side rail, a phone — the bar
            // drops under the name instead of fighting it for width. A
            // 150px bar squeezed between a truncated label and two figures
            // is unreadable, and is what made the wide-only layout look
            // cramped in a third-width column.
            if (constraints.maxWidth < 380) {
              return _stacked(value, sharePercent, count, duration);
            }
            return _inline(value, sharePercent, count, duration);
          },
        ),
      ),
    );
  }

  Widget _rank() {
    // Muted and small: it orders the list without competing with figures.
    return Text(
      '${widget.rank}',
      style: AppTypography.caption.copyWith(
        color: AppColors.textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _name({bool expand = false}) {
    final text = Text(
      widget.row.label,
      style: AppTypography.tableCell.copyWith(fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return expand ? Expanded(child: text) : text;
  }

  Widget _countLine(int count) {
    return Text(
      '$count ${widget.countNoun}${count == 1 ? '' : 's'}',
      style: AppTypography.caption.copyWith(
        color: AppColors.textMuted,
        fontSize: 10,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _share(String sharePercent) {
    return Text(
      sharePercent,
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.right,
    );
  }

  /// Wide: rank · name over count · bar · share, all on one line.
  Widget _inline(
    String value,
    String sharePercent,
    int count,
    Duration duration,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 18, child: _rank()),
        SizedBox(
          width: 136,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _name(),
              if (widget.showAmount) ...[
                const SizedBox(height: 1),
                _countLine(count),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Bar(
            fraction: widget.fraction,
            label: value,
            animate: widget.animate,
            duration: duration,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(width: 38, child: _share(sharePercent)),
      ],
    );
  }

  /// Narrow: name and figure on top, the bar full width beneath. The bar
  /// gets the whole column, so lengths stay comparable down the list —
  /// which is the only job the bar has.
  Widget _stacked(
    String value,
    String sharePercent,
    int count,
    Duration duration,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 16, child: _rank()),
            _name(expand: true),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: AppTypography.tableCellNumeric.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: _Bar(
                fraction: widget.fraction,
                // The figure is already on the line above; repeating it on
                // the bar would be a value on every mark.
                label: null,
                animate: widget.animate,
                duration: duration,
                height: 10,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.showAmount) ...[
                    Flexible(child: _countLine(count)),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  _share(sharePercent),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One bar: capped thickness, 4px rounded data-end, square at the
/// baseline, grown from a single left baseline. The track behind it is a
/// recessive wash, not a competing block.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.label,
    required this.animate,
    required this.duration,
    this.height = 22,
  });

  final double fraction;

  /// Null where the figure already sits beside the bar — the stacked
  /// layout prints it on the line above, and repeating it on the mark
  /// would be a value on every data point.
  final String? label;

  final bool animate;
  final Duration duration;
  final double height;

  static const double _labelPadding = 10;

  @override
  Widget build(BuildContext context) {
    final target = fraction.clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final style = AppTypography.tableCellNumeric.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          );

          // Measure, never guess: a label only goes inside the bar when it
          // fits with padding on both sides, otherwise it sits outside the
          // end. Clipping a figure would be worse than moving it.
          var fitsInside = false;
          if (label != null) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              textDirection: TextDirection.ltr,
            )..layout();
            final barWidth = constraints.maxWidth * target;
            fitsInside = barWidth >= painter.width + _labelPadding * 2;
          }

          Widget buildBar(double t) {
            final width = constraints.maxWidth * t;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Container(
                  // A zero row still shows a sliver, so it reads as "none"
                  // rather than as a rendering failure.
                  width: width < 3 ? 3 : width,
                  height: height,
                  decoration: const BoxDecoration(
                    color: ReportChart.accent,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(3),
                      bottomLeft: Radius.circular(3),
                      topRight: ReportChart.barEnd,
                      bottomRight: ReportChart.barEnd,
                    ),
                  ),
                  alignment: Alignment.centerRight,
                  child: fitsInside
                      ? Padding(
                          padding: const EdgeInsets.only(right: _labelPadding),
                          child: Text(label!, style: style),
                        )
                      : null,
                ),
                if (label != null && !fitsInside)
                  Padding(
                    padding: EdgeInsets.only(
                      left: (width < 3 ? 3 : width) + AppSpacing.sm,
                    ),
                    child: Text(
                      label!,
                      style: style.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
              ],
            );
          }

          if (!animate) return buildBar(target);

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: duration,
            curve: AppMotion.curve,
            builder: (context, t, _) => buildBar(t),
          );
        },
      ),
    );
  }
}
