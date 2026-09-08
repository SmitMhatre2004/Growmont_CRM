import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../auth/auth_provider.dart';
import 'widgets/add_sale_modal.dart';

// -----------------------------------------------------------------------------
// Design tokens matching Interactions & Info Portal screens
// -----------------------------------------------------------------------------
class _Palette {
  static const Color surface = Colors.white;
  static const Color headerBg = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color hover = Color(0xFFF1F5F9);
  static const Color selected = Color(0xFFEFF6FF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
}

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  static const double _controlHeight = 40.0;
  static const double _radius = 20.0;

  List<Sale> _sales = [];
  String _selectedProduct = 'ALL';
  bool _loading = true;
  bool _expandZeroCountFilters = false;

  // Selection (for bulk delete)
  final Set<dynamic> _selectedIds = {};

  // Sorting state
  String _sortColumn = 'date';
  bool _sortAscending = false; // default newest date first

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(apiServiceProvider).getSales();
      if (mounted) {
        setState(() {
          _sales = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('Failed to load sales');
      }
    }
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = (column == 'amount' || column == 'date') ? false : true;
      }
    });
  }

  List<Sale> get _filtered {
    Iterable<Sale> list = _sales;

    // Product filter
    if (_selectedProduct != 'ALL') {
      list = list.where((s) => s.product == _selectedProduct);
    }

    final sorted = list.toList();
    sorted.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'client':
          cmp = a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase());
          break;
        case 'product':
          cmp = a.product.toLowerCase().compareTo(b.product.toLowerCase());
          break;
        case 'amount':
          final aVal = double.tryParse(a.amount) ?? (a.amountPaise / 100.0);
          final bVal = double.tryParse(b.amount) ?? (b.amountPaise / 100.0);
          cmp = aVal.compareTo(bVal);
          break;
        case 'frequency':
          cmp = a.frequency.toLowerCase().compareTo(b.frequency.toLowerCase());
          break;
        case 'rep':
          final aRep = (a.salesRepName ?? a.salesRep).toLowerCase();
          final bRep = (b.salesRepName ?? b.salesRep).toLowerCase();
          cmp = aRep.compareTo(bRep);
          break;
        case 'date':
        default:
          cmp = a.date.compareTo(b.date);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return sorted;
  }

  Future<void> _deleteSale(dynamic id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sale'),
        content: const Text('Are you sure you want to delete this sale?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(apiServiceProvider).deleteSale(id);
      _showSuccess('Sale deleted');
      _loadSales();
    } catch (_) {
      _showError('Failed to delete sale');
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count Sale${count > 1 ? 's' : ''}'),
        content: Text(
          'Are you sure you want to delete $count selected sale${count > 1 ? 's' : ''}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final api = ref.read(apiServiceProvider);
    for (final id in _selectedIds.toList()) {
      try {
        await api.deleteSale(id);
      } catch (_) {}
    }
    setState(() => _selectedIds.clear());
    _showSuccess('$count sale${count > 1 ? 's' : ''} deleted');
    _loadSales();
  }

  Future<void> _exportSales() async {
    try {
      final base64Data =
          await ref.read(firestoreServiceProvider).exportSalesExcel();
      final bytes = base64Decode(base64Data);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sales_export.xlsx');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: 'Sales Export');
    } catch (_) {
      _showError('Export failed');
    }
  }

  Future<void> _importSales() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final base64 = base64Encode(bytes);
      await ref.read(firestoreServiceProvider).importSales(base64);
      _showSuccess('Import successful');
      _loadSales();
    } catch (_) {
      _showError('Import failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _getCategoryName(String code) {
    for (final cat in productCategories) {
      if (cat.$1 == code) return cat.$2;
    }
    return code;
  }

  Widget _outlinedIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: _controlHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _Palette.textPrimary,
          side: const BorderSide(color: _Palette.border),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final user = ref.watch(authProvider).user;
    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(),
        _buildActionsRow(user),
        _summaryRow(),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Filter by product side column
                      SizedBox(width: 250, child: _filterPanel()),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _salesTableOrEmpty(filtered, user),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        height: 120,
                        child: _filterPanel(horizontal: true),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _salesTableOrEmpty(filtered, user),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // -- Title row: "Sales" ---------------------------------------------------

  Widget _buildTitleRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 10 : 16,
        isMobile ? 16 : 24,
        isMobile ? 8 : 12,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Sales',
          style: isMobile
              ? AppTypography.pageTitleMobile
              : AppTypography.pageTitle,
        ),
      ),
    );
  }

  // -- Actions Row: Export / Import / Add Sale ------------------------------

  Widget _buildActionsRow(AppUser? user) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _outlinedIconButton(
          icon: Icons.download_outlined,
          label: 'Export',
          onPressed: _exportSales,
        ),
        const SizedBox(width: 8),
        _outlinedIconButton(
          icon: Icons.upload_outlined,
          label: 'Import',
          onPressed: _importSales,
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: _controlHeight,
          child: FilledButton.icon(
            onPressed: () => _showSaleModal(context, user),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Sale'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_radius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        0,
        isMobile ? 16 : 24,
        isMobile ? 10 : 16,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: actionButtons,
        ),
      ),
    );
  }

  // -- Selection Action Bar -------------------------------------------------

  Widget _buildSelectionBar() {
    return Material(
      color: const Color(0xFFEFF6FF),
      elevation: 1.5,
      shadowColor: const Color(0xFF93C5FD).withValues(alpha: 0.25),
      shape: const StadiumBorder(
        side: BorderSide(
          color: Color(0xFF93C5FD),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: _controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_selectedIds.length} selected',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: _Palette.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              style: TextButton.styleFrom(
                foregroundColor: _Palette.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _bulkDelete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Summary Row ----------------------------------------------------------

  Widget _summaryRow() {
    final count = _filtered.length;
    final total = _filtered.fold<double>(
      0.0,
      (sum, s) =>
          sum + (double.tryParse(s.amount) ?? (s.amountPaise / 100.0)),
    );
    final isFiltered = _selectedProduct != 'ALL';
    final currentCatName = _getCategoryName(_selectedProduct);
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    final summaryContent = Container(
      height: _controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: _Palette.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 16,
              color: AppColors.primaryBlue,
            ),
            const SizedBox(width: 6),
            Text(
              isFiltered ? '$currentCatName: $count' : 'Total Deals: $count',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _Palette.textPrimary,
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 18, color: _Palette.border),
            const SizedBox(width: 16),
            const Icon(
              Icons.currency_rupee,
              size: 16,
              color: AppColors.primaryGreen,
            ),
            const SizedBox(width: 4),
            Text(
              AppFormatters.formatAmount(total.toStringAsFixed(2)),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: _Palette.textPrimary,
              ),
            ),
            if (isFiltered) ...[
              const SizedBox(width: 14),
              InkWell(
                onTap: () => setState(() => _selectedProduct = 'ALL'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _Palette.headerBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _Palette.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, size: 12, color: _Palette.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _Palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        0,
        isMobile ? 16 : 24,
        isMobile ? 10 : 16,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summaryContent,
                if (_selectedIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildSelectionBar(),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: summaryContent),
                if (_selectedIds.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  _buildSelectionBar(),
                ],
              ],
            ),
    );
  }

  // -- Filter Panel (Side Column) ------------------------------------------

  Widget _filterPanel({bool horizontal = false}) {
    final allCategory = productCategories.firstWhere((c) => c.$1 == 'ALL');
    final otherCategories =
        productCategories.where((c) => c.$1 != 'ALL').toList();

    final activeCategories = otherCategories.where((cat) {
      return _sales.any((s) => s.product == cat.$1);
    }).toList();

    final zeroCountCategories = otherCategories.where((cat) {
      return !_sales.any((s) => s.product == cat.$1);
    }).toList();

    Widget buildCategoryItem((String, String) cat) {
      final count = cat.$1 == 'ALL'
          ? _sales.length
          : _sales.where((s) => s.product == cat.$1).length;
      final selected = _selectedProduct == cat.$1;

      return InkWell(
        onTap: () => setState(() => _selectedProduct = cat.$1),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : Colors.transparent,
            border: selected
                ? const Border(
                    left: BorderSide(
                      color: AppColors.primaryBlue,
                      width: 3.5,
                    ),
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                        color: selected
                            ? AppColors.primaryBlue
                            : _Palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count sale${count == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? AppColors.primaryBlue.withValues(alpha: 0.8)
                            : _Palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (horizontal) {
      final itemsToShow = <(String, String)>[
        allCategory,
        ...activeCategories,
      ];
      if (_expandZeroCountFilters) {
        itemsToShow.addAll(zeroCountCategories);
      } else if (_selectedProduct != 'ALL' &&
          zeroCountCategories.any((c) => c.$1 == _selectedProduct)) {
        final selectedCat = zeroCountCategories.firstWhere(
          (c) => c.$1 == _selectedProduct,
        );
        itemsToShow.add(selectedCat);
      }

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.primaryBlue,
              ),
              child: Row(
                children: [
                  const Text(
                    'FILTER BY PRODUCT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (zeroCountCategories.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() =>
                          _expandZeroCountFilters = !_expandZeroCountFilters),
                      child: Text(
                        _expandZeroCountFilters
                            ? 'Show less'
                            : '+ ${zeroCountCategories.length} more',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: itemsToShow
                        .map(
                          (c) => SizedBox(
                            width: 160,
                            child: buildCategoryItem(c),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Vertical Sidebar (Desktop)
    final visibleCategories = <(String, String)>[
      allCategory,
      ...activeCategories,
    ];

    if (_expandZeroCountFilters) {
      visibleCategories.addAll(zeroCountCategories);
    } else if (_selectedProduct != 'ALL' &&
        zeroCountCategories.any((c) => c.$1 == _selectedProduct)) {
      final selectedCat = zeroCountCategories.firstWhere(
        (c) => c.$1 == _selectedProduct,
      );
      visibleCategories.add(selectedCat);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Palette.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: AppColors.primaryBlue,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'FILTER BY PRODUCT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${activeCategories.length + 1} active',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ListView(
                children: [
                  ...visibleCategories.map(buildCategoryItem),
                  if (zeroCountCategories.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => setState(() =>
                          _expandZeroCountFilters = !_expandZeroCountFilters),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _Palette.headerBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _Palette.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _expandZeroCountFilters
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 16,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _expandZeroCountFilters
                                  ? 'Hide inactive categories'
                                  : 'Show ${zeroCountCategories.length} more (0 sales)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Sales Table --------------------------------------------------------

  Widget _salesTableOrEmpty(List<Sale> items, [AppUser? user]) {
    if (items.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _emptyState(),
      );
    }

    final itemIds = items.map((e) => e.id).toSet();
    final allSelected =
        itemIds.isNotEmpty && itemIds.every(_selectedIds.contains);
    final someSelected = itemIds.any(_selectedIds.contains);

    return Container(
      decoration: BoxDecoration(
        color: _Palette.surface,
        border: Border.all(color: _Palette.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minTableWidth = 850.0;
          final tableWidth = constraints.maxWidth < minTableWidth
              ? minTableWidth
              : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  _tableHeader(
                    allSelected: allSelected,
                    someSelected: someSelected,
                    onSelectAll: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.addAll(itemIds);
                        } else {
                          _selectedIds.removeAll(itemIds);
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, index) =>
                          const Divider(height: 1, color: _Palette.border),
                      itemBuilder: (context, index) {
                        final sale = items[index];
                        return _SalesTableRow(
                          sale: sale,
                          selected: _selectedIds.contains(sale.id),
                          onSelectChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(sale.id);
                              } else {
                                _selectedIds.remove(sale.id);
                              }
                            });
                          },
                          onEdit: () => _showSaleModal(
                            context,
                            user ?? ref.read(authProvider).user,
                            sale: sale,
                          ),
                          onDelete: () => _deleteSale(sale.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tableHeader({
    required bool allSelected,
    required bool someSelected,
    required ValueChanged<bool?> onSelectAll,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.primaryBlue,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allSelected ? true : (someSelected ? null : false),
                tristate: true,
                shape: const CircleBorder(),
                side: const BorderSide(color: Colors.white, width: 1.5),
                activeColor: Colors.white,
                checkColor: AppColors.primaryBlue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                onChanged: onSelectAll,
              ),
            ),
          ),
          _salesSortHeader(
            columnKey: 'client',
            title: 'CLIENT & DETAILS',
            flex: 4,
          ),
          _salesSortHeader(
            columnKey: 'product',
            title: 'PRODUCT',
            flex: 3,
            alignment: Alignment.center,
          ),
          _salesSortHeader(
            columnKey: 'amount',
            title: 'AMOUNT',
            flex: 2,
            alignment: Alignment.centerRight,
          ),
          _salesSortHeader(
            columnKey: 'frequency',
            title: 'FREQUENCY',
            flex: 2,
            alignment: Alignment.center,
          ),
          _salesSortHeader(
            columnKey: 'rep',
            title: 'SALES REP',
            flex: 3,
            alignment: Alignment.centerLeft,
          ),
          _salesSortHeader(
            columnKey: 'date',
            title: 'DATE',
            flex: 2,
            alignment: Alignment.center,
          ),
          const SizedBox(
            width: 76,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesSortHeader({
    required String columnKey,
    required String title,
    required int flex,
    Alignment alignment = Alignment.centerLeft,
  }) {
    final isSelected = _sortColumn == columnKey;
    final mainAxis = alignment == Alignment.center
        ? MainAxisAlignment.center
        : (alignment == Alignment.centerRight
            ? MainAxisAlignment.end
            : MainAxisAlignment.start);

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _onSort(columnKey),
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: alignment,
          child: Row(
            mainAxisAlignment: mainAxis,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.5,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isSelected
                    ? (_sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward)
                    : Icons.unfold_more,
                size: 13,
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final isFiltered = _selectedProduct != 'ALL';
    final categoryName = _getCategoryName(_selectedProduct);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isFiltered
                  ? 'No sales found in $categoryName'
                  : 'No sales recorded yet',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _Palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                isFiltered
                    ? 'There are currently no transactions logged under $categoryName. You can record a new transaction for this category or explore other categories.'
                    : 'Start building your sales pipeline by recording your first transaction.',
                style: const TextStyle(
                  fontSize: 13,
                  color: _Palette.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _showSaleModal(
                    context,
                    ref.read(authProvider).user,
                    defaultProduct: isFiltered ? _selectedProduct : null,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    isFiltered ? 'Add $categoryName Sale' : 'Add First Sale',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                  ),
                ),
                if (isFiltered)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _selectedProduct = 'ALL'),
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('View All Categories'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _Palette.textPrimary,
                      side: const BorderSide(color: _Palette.border),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSaleModal(
    BuildContext context,
    AppUser? user, {
    Sale? sale,
    String? defaultProduct,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddSaleModal(
        existing: sale,
        currentUser: user,
        defaultProduct: defaultProduct,
      ),
    );
    if (saved == true) _loadSales();
  }
}

// ---------------------------------------------------------------------
// Sales Table Row (Matches Info Portal & Interactions SaaS pattern)
// ---------------------------------------------------------------------

class _SalesTableRow extends StatefulWidget {
  const _SalesTableRow({
    required this.sale,
    required this.selected,
    required this.onSelectChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final Sale sale;
  final bool selected;
  final ValueChanged<bool?> onSelectChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SalesTableRow> createState() => _SalesTableRowState();
}

class _SalesTableRowState extends State<_SalesTableRow> {
  bool _isHovered = false;

  String _getFrequencyLabel(String code) {
    for (final choice in frequencyChoices) {
      if (choice.$1.toUpperCase() == code.toUpperCase()) {
        return choice.$2;
      }
    }
    return code.isEmpty ? '—' : code;
  }

  String _getProductName(String code) {
    for (final c in productCategories) {
      if (c.$1 == code) return c.$2;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final repName = widget.sale.salesRepName ??
        (widget.sale.salesRep.isNotEmpty ? widget.sale.salesRep : '');
    final freqText = widget.sale.frequencyDisplay ??
        _getFrequencyLabel(widget.sale.frequency);
    final hasCompany = widget.sale.company.trim().isNotEmpty;
    final hasScheme = widget.sale.scheme.trim().isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        color: widget.selected
            ? _Palette.selected
            : (_isHovered ? _Palette.hover : Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.selected,
                  shape: const CircleBorder(),
                  side: const BorderSide(color: Color(0xFFC4C8D2), width: 1.5),
                  activeColor: AppColors.primaryBlue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  onChanged: widget.onSelectChanged,
                ),
              ),
            ),

            // Client & Details
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryBlue.withValues(
                      alpha: 0.1,
                    ),
                    child: Text(
                      widget.sale.clientName.isEmpty
                          ? '?'
                          : widget.sale.clientName[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.sale.clientName.isEmpty
                              ? '—'
                              : widget.sale.clientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _Palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasCompany || hasScheme) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (hasCompany) widget.sale.company.trim(),
                              if (hasScheme) widget.sale.scheme.trim(),
                            ].join(' • '),
                            style: const TextStyle(
                              color: _Palette.textMuted,
                              fontSize: 11.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Product Badge
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    widget.sale.productDisplay ??
                        _getProductName(widget.sale.product),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Amount (Right-aligned)
            Expanded(
              flex: 2,
              child: Text(
                AppFormatters.formatAmount(widget.sale.amount),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _Palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Frequency
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _Palette.headerBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _Palette.border),
                  ),
                  child: Text(
                    freqText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _Palette.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Sales Rep
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _Palette.headerBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 14,
                      color: _Palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      repName.isNotEmpty ? repName : '—',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: repName.isNotEmpty
                            ? _Palette.textPrimary
                            : _Palette.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Date
            Expanded(
              flex: 2,
              child: Text(
                AppFormatters.formatDate(widget.sale.date),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _Palette.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Actions
            SizedBox(
              width: 76,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.primaryBlue,
                      size: 18,
                    ),
                    onPressed: widget.onEdit,
                    tooltip: 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    onPressed: widget.onDelete,
                    tooltip: 'Delete',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
