import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/excel/excel_io.dart';
import '../../core/io/file_saver.dart';
import '../../core/io/record_import.dart';
import '../../core/io/record_json.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../../shared/widgets/export_format_picker.dart';
import '../../shared/widgets/toolbar_action_button.dart';
import '../auth/auth_provider.dart';
import 'sales_excel.dart';
import 'widgets/add_sale_modal.dart';

// -----------------------------------------------------------------------------
// Design tokens matching Interactions & Info Portal screens
// -----------------------------------------------------------------------------
/// Screen palette. Every value aliases the shared design tokens in
/// [AppColors] so this screen can never drift from the rest of the app.
class _Palette {
  _Palette._();

  static const Color surface = AppColors.surface;
  static const Color border = AppColors.border;
  static const Color headerBg = AppColors.surfaceHeader;
  static const Color hover = AppColors.surfaceHover;
  static const Color selected = AppColors.surfaceSelected;

  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textMuted = AppColors.textMuted;
}

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  // Control metrics come from the shared design tokens so every screen's
  // toolbar sits on the same baseline with the same corner treatment.

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
      final user = ref.read(authProvider).user;
      final selfId = user?.isAdmin == true ? null : user?.id;
      final data = await ref.read(apiServiceProvider).getSales(
        salesRepId: selfId,
      );
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
        _sortAscending = (column == 'amount' || column == 'date')
            ? false
            : true;
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
          cmp = a.clientName.toLowerCase().compareTo(
            b.clientName.toLowerCase(),
          );
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
    final format = await pickExportFormat(context);
    if (format == null) return;

    try {
      final rows = _sales.map(saleExportRow).toList();
      final savedPath = format == ExportFormat.json
          ? await FileSaver.save(
              filename: 'sales_export.json',
              bytes: RecordJson.encode(
                type: 'sales',
                keys: salesJsonKeys,
                rows: rows,
              ),
              extensions: const ['json'],
              shareText: 'Sales Export',
            )
          : await ExcelIO.exportWorkbook(
              filename: 'sales_export.xlsx',
              sheetName: 'Sales',
              headers: salesExcelHeaders,
              rows: rows,
              shareText: 'Sales Export',
            );
      if (savedPath != null) _showSuccess('Saved to $savedPath');
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  Future<void> _importSales() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'json'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    try {
      final rows = RecordJson.isJsonPath(path)
          ? await RecordJson.readRows(path, salesJsonKeys)
          : await ExcelIO.readDataRows(path);

      final currentUserName =
          ref.read(authProvider).user?.name ?? 'Team Member';
      final api = ref.read(firestoreServiceProvider);

      final result = await runRecordImport(
        payloads: rows
            .map((r) => saleImportPayload(r, currentUserName: currentUserName))
            .nonNulls,
        existingIdBySignature: {
          for (final s in _sales) saleSignatureOf(s): s.id,
        },
        signatureFields: salesSignatureFields,
        create: api.createSale,
        update: api.updateSale,
      );

      _showSuccess(result.describe('sale'));
      _loadSales();
    } catch (e) {
      _showError('Import failed: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
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
    return AppToolbarButton(icon: icon, label: label, onPressed: onPressed);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final isWide = !isMobile && MediaQuery.sizeOf(context).width >= 900;
    final user = ref.watch(authProvider).user;
    final filtered = _filtered;

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitleRow(),
            _summaryRow(user),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? AppSpacing.lg : AppSpacing.xxl,
                ),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Filter by product side column
                          SizedBox(width: 250, child: _filterPanel()),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _salesTableOrEmpty(filtered, user),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 40,
                            child: _filterPanel(horizontal: true),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          if (MediaQuery.sizeOf(context).width < 600) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: _buildSelectionBar(),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                          Expanded(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _salesTableOrEmpty(filtered, user),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        );

        const minComfortHeight = 280.0;
        if (constraints.maxHeight.isFinite &&
            constraints.maxHeight < minComfortHeight) {
          return SingleChildScrollView(
            child: SizedBox(
              height: minComfortHeight,
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }

  // -- Title row: "Sales" ---------------------------------------------------

  Widget _buildTitleRow() {
    final isMobile = AppLayout.isMobile(context);
    final isShort = MediaQuery.sizeOf(context).height < 450;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        isShort ? 4 : (isMobile ? 10 : 16),
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        isShort ? 4 : (isMobile ? 8 : 12),
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

  // -- Actions: Export / Import / Add Sale ----------------------------------

  /// On phones the primary (blue) action leads the group, on the extreme
  /// left; desktop keeps Export/Import first with Add trailing.
  Widget _buildActions(AppUser? user, {required bool isMobile}) {
    final addButton = AppToolbarButton(
      icon: Icons.add,
      label: 'Add Sale',
      isPrimary: true,
      onPressed: () => _showSaleModal(context, user),
    );
    final exportButton = _outlinedIconButton(
      icon: Icons.download_outlined,
      label: 'Export',
      onPressed: _exportSales,
    );
    final importButton = _outlinedIconButton(
      icon: Icons.upload_outlined,
      label: 'Import',
      onPressed: _importSales,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isMobile
            ? [
                addButton,
                const SizedBox(width: AppSpacing.sm),
                exportButton,
                const SizedBox(width: AppSpacing.sm),
                importButton,
              ]
            : [
                exportButton,
                const SizedBox(width: AppSpacing.sm),
                importButton,
                const SizedBox(width: AppSpacing.sm),
                addButton,
              ],
      ),
    );
  }

  // -- Selection Action Bar -------------------------------------------------

  Widget _buildSelectionBar() {
    final hasSelection = _selectedIds.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Visibility(
          visible: hasSelection,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Tooltip(
            message: 'Delete selected',
            child: Material(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                onTap: hasSelection ? _bulkDelete : null,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${_selectedIds.length} selected',
          style: AppTypography.tableCellStrong.copyWith(fontSize: 14),
        ),
      ],
    );
  }

  // -- Summary Row & Info Boxes ---------------------------------------------

  Widget _infoBox({
    required String title,
    required String value,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _Palette.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppTypography.metricLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.metricLarge.copyWith(color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(AppUser? user) {
    final count = _filtered.length;
    final total = _filtered.fold<double>(
      0.0,
      (sum, s) => sum + (double.tryParse(s.amount) ?? (s.amountPaise / 100.0)),
    );
    final avgDeal = count > 0 ? total / count : 0.0;
    final uniqueClients = _filtered
        .map((s) => s.clientName.trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;

    final isFiltered = _selectedProduct != 'ALL';
    final currentCatName = _getCategoryName(_selectedProduct);
    final isMobile = AppLayout.isMobile(context);

    final dealsBox = _infoBox(
      title: isFiltered ? currentCatName.toUpperCase() : 'TOTAL DEALS',
      value: '$count',
    );

    final clientsBox = _infoBox(
      title: 'ACTIVE CLIENTS',
      value: '$uniqueClients',
    );

    final amountBox = _infoBox(
      title: 'TOTAL REVENUE',
      value: AppFormatters.formatAmount(total.toStringAsFixed(2)),
    );

    final avgBox = _infoBox(
      title: 'AVG DEAL VALUE',
      value: AppFormatters.formatAmount(avgDeal.toStringAsFixed(2)),
    );

    final actionButtons = _buildActions(user, isMobile: isMobile);
    const gap = 10.0;

    final isCompactWidth = MediaQuery.sizeOf(context).width < 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        0,
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        gap,
      ),
      child: isCompactWidth
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                actionButtons,
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      dealsBox,
                      const SizedBox(width: AppSpacing.md),
                      clientsBox,
                      const SizedBox(width: AppSpacing.md),
                      amountBox,
                      const SizedBox(width: AppSpacing.md),
                      avgBox,
                    ],
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dealsBox,
                        const SizedBox(width: AppSpacing.md),
                        clientsBox,
                        const SizedBox(width: AppSpacing.md),
                        amountBox,
                        const SizedBox(width: AppSpacing.md),
                        avgBox,
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    actionButtons,
                    const SizedBox(height: gap),
                    _buildSelectionBar(),
                  ],
                ),
              ],
            ),
    );
  }

  // -- Filter Panel (Side Column) ------------------------------------------

  Widget _filterPanel({bool horizontal = false}) {
    final allCategory = productCategories.firstWhere((c) => c.$1 == 'ALL');
    final otherCategories = productCategories
        .where((c) => c.$1 != 'ALL')
        .toList();

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
      final catColor = productColor(cat.$1);

      return InkWell(
        onTap: () => setState(() => _selectedProduct = cat.$1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? catColor.withValues(alpha: 0.08)
                : Colors.transparent,
            border: selected
                ? Border(
                    left: BorderSide(color: catColor, width: 3.5),
                  )
                : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
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
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? catColor
                            : _Palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$count sale${count == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? catColor.withValues(alpha: 0.8)
                            : _Palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: catColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (horizontal) {
      final itemsToShow = <(String, String)>[allCategory, ...otherCategories];

      return Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _Palette.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 3,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: itemsToShow.map((cat) {
              final count = cat.$1 == 'ALL'
                  ? _sales.length
                  : _sales.where((s) => s.product == cat.$1).length;
              final selected = _selectedProduct == cat.$1;
              final catColor = productColor(cat.$1);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  onTap: () => setState(() => _selectedProduct = cat.$1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? catColor.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: selected ? catColor : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? catColor : _Palette.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '($count)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? catColor : _Palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.surfaceHeader,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'FILTER BY PRODUCT',
                    style: AppTypography.tableHeader,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.infoSoft,
                    borderRadius: AppRadius.brSm,
                  ),
                  child: Text(
                    '${activeCategories.length + 1} active',
                    style: AppTypography.badge.copyWith(
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ListView(
                children: [
                  ...visibleCategories.map(buildCategoryItem),
                  if (zeroCountCategories.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    InkWell(
                      onTap: () => setState(
                        () =>
                            _expandZeroCountFilters = !_expandZeroCountFilters,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: _Palette.headerBg,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: _Palette.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _expandZeroCountFilters
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: AppSizing.iconSm,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: AppSpacing.xs),
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.sm,
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surfaceHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allSelected ? true : (someSelected ? null : false),
                tristate: true,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
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
            alignment: Alignment.centerLeft,
          ),
          _salesSortHeader(
            columnKey: 'amount',
            title: 'AMOUNT',
            flex: 2,
            alignment: Alignment.center,
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
                fontWeight: FontWeight.w700,
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
        borderRadius: AppRadius.brSm,
        hoverColor: AppColors.surfaceHover,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          alignment: alignment,
          child: Row(
            mainAxisAlignment: mainAxis,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.tableHeader.copyWith(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                isSelected
                    ? (_sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                    : Icons.unfold_more,
                size: AppSizing.iconXs,
                color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xl,
                  horizontal: AppSpacing.xxl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        size: AppSizing.iconEmptyState,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      isFiltered
                          ? 'No sales found in $categoryName'
                          : 'No sales recorded yet',
                      style: AppTypography.sectionTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
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
                    const SizedBox(height: AppSpacing.xxl),
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
                          icon: const Icon(Icons.add, size: AppSizing.iconMd),
                          label: Text(
                            isFiltered ? 'Add $categoryName Sale' : 'Add First Sale',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                          ),
                        ),
                        if (isFiltered)
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _selectedProduct = 'ALL'),
                            icon: const Icon(
                              Icons.filter_alt_off,
                              size: AppSizing.iconMd,
                            ),
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
            ),
          ),
        );
      },
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
    final repName =
        widget.sale.salesRepName ??
        (widget.sale.salesRep.isNotEmpty ? widget.sale.salesRep : '');
    final freqText =
        widget.sale.frequencyDisplay ??
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.selected,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.sale.clientName.isEmpty
                              ? '—'
                              : widget.sale.clientName,
                          style: AppTypography.tableCellStrong,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasCompany || hasScheme) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            [
                              if (hasCompany) widget.sale.company.trim(),
                              if (hasScheme) widget.sale.scheme.trim(),
                            ].join(' • '),
                            style: AppTypography.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Product Category (Dot + Text treatment, aligned left)
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: productColor(widget.sale.product),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.sale.productDisplay ??
                          _getProductName(widget.sale.product),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _Palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Amount (Center-aligned)
            Expanded(
              flex: 2,
              child: Text(
                AppFormatters.formatAmount(widget.sale.amount),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
                  width: 84,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _Palette.headerBg,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: _Palette.border),
                  ),
                  child: Text(
                    freqText,
                    textAlign: TextAlign.center,
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
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: _Palette.headerBg,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: AppSizing.iconXs,
                      color: _Palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      repName.isNotEmpty ? repName : '—',
                      style: TextStyle(
                        fontSize: 12,
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
                  fontSize: 12,
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
                      size: AppSizing.iconMd,
                    ),
                    onPressed: widget.onEdit,
                    tooltip: 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.danger,
                      size: AppSizing.iconMd,
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
