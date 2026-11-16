import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sale.dart';
import '../charts/charts.dart';

/// A sale's value in paise. Money is summed in paise so repeated float
/// addition cannot drift; [Sale.amount] is only a fallback for older rows
/// written before `amount_paise` existed.
int salePaise(Sale s) => s.amountPaise != 0
    ? s.amountPaise
    : ((double.tryParse(s.amount) ?? 0) * 100).round();

/// Compact rupee label in Indian units: Cr, L, K.
String compactRupees(double rupees) {
  if (rupees >= 10000000) return '₹${(rupees / 10000000).toStringAsFixed(1)}Cr';
  if (rupees >= 100000) return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  if (rupees >= 1000) return '₹${(rupees / 1000).toStringAsFixed(0)}K';
  return '₹${rupees.toStringAsFixed(0)}';
}

/// Revenue per month across the trailing [months] months, oldest first.
List<({String label, double rupees})> monthlyRevenue(
  List<Sale> sales, {
  int months = 6,
}) {
  final now = DateTime.now();
  final totals = <String, double>{};
  final buckets = <({String key, String label})>[];

  for (var i = months - 1; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i);
    final key = '${m.year}-${m.month}';
    buckets.add((key: key, label: DateFormat('MMM').format(m)));
    totals[key] = 0;
  }

  for (final s in sales) {
    final d = DateTime.tryParse(s.date);
    if (d == null) continue;
    final key = '${d.year}-${d.month}';
    if (totals.containsKey(key)) {
      totals[key] = totals[key]! + salePaise(s) / 100;
    }
  }

  return [
    for (final b in buckets) (label: b.label, rupees: totals[b.key] ?? 0),
  ];
}

/// Bar chart of booked revenue per month, shared by the dashboard and the
/// employee detail screen.
class MonthlyRevenueChart extends StatelessWidget {
  const MonthlyRevenueChart({
    super.key,
    required this.sales,
    this.months = 6,
    this.height = 190,
    this.barColor,
    this.emptyMessage = 'No sales in this period',
  });

  final List<Sale> sales;
  final int months;
  final double height;

  /// Defaults to the chart kit accent.
  final Color? barColor;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final series = monthlyRevenue(sales, months: months);
    final peak = series.fold<double>(0, (m, e) => e.rupees > m ? e.rupees : m);

    if (peak <= 0) return ChartEmpty(height: height, message: emptyMessage);

    return GrowBarChart(
      height: height,
      color: barColor,
      bars: [
        for (final e in series) ChartBar(label: e.label, value: e.rupees),
      ],
    );
  }
}
