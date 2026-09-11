import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/excel/excel_io.dart';
import '../../core/io/file_saver.dart';
import '../../core/io/record_import.dart';
import '../../core/io/record_json.dart';
import '../../shared/widgets/export_format_picker.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../../shared/widgets/toolbar_action_button.dart';
import '../auth/auth_provider.dart';
import '../interactions/interactions_excel.dart';
import '../interactions/widgets/add_interaction_modal.dart';
import '../sales/sales_excel.dart';
import '../sales/widgets/add_sale_modal.dart';

/// Screen palette. Every value aliases the shared design tokens in
/// [AppColors] so this screen can never drift from the rest of the app.
class _Palette {
  _Palette._();

  static const Color border = AppColors.border;
  static const Color headerBg = AppColors.surfaceHeader;
  static const Color rowHover = AppColors.surfaceHover;

  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color textMuted = AppColors.textMuted;

  static const Color all = AppColors.primaryBlue;
  static const Color high = AppColors.danger;
  static const Color highBg = AppColors.dangerSoft;
  static const Color medium = AppColors.warning;
  static const Color mediumBg = AppColors.warningSoft;
  static const Color low = AppColors.yellow;
  static const Color lowBg = AppColors.yellowSoft;
}

class InfoPortalScreen extends ConsumerStatefulWidget {
  const InfoPortalScreen({super.key});

  @override
  ConsumerState<InfoPortalScreen> createState() => _InfoPortalScreenState();
}

class _InfoPortalScreenState extends ConsumerState<InfoPortalScreen> {
  // Control metrics come from the shared design tokens so every screen's
  // toolbar sits on the same baseline with the same corner treatment.
  static const double _controlHeight = AppSizing.controlMd; // 40
  static const double _radius = AppRadius.md; // 8 - controls are not pills

  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
  bool _loading = true;

  // Active Tab: 'sales' or 'interactions'
  String _activeTab = 'sales';

  // Search
  String _search = '';

  // Filter Controllers
  final _dateFromController = TextEditingController();
  final _dateToController = TextEditingController();
  final _clientController = TextEditingController();
  final _salesRepController = TextEditingController();
  String _productFilter = '';
  String _priorityFilter = '';

  // Sorting
  String _sortColumnInteractions = 'date';
  bool _sortAscendingInteractions = false;

  String _sortColumnSales = 'date';
  bool _sortAscendingSales = false;

  // Selections for bulk delete
  final Set<dynamic> _selectedInteractionIds = {};
  final Set<dynamic> _selectedSaleIds = {};

  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _dateFromController.dispose();
    _dateToController.dispose();
    _clientController.dispose();
    _salesRepController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final results = await Future.wait([
        api.getSales(),
        api.getInteractions(),
      ]);
      if (mounted) {
        setState(() {
          _sales = results[0] as List<Sale>;
          _interactions = results[1] as List<Interaction>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Filtering & Sorting
  // ---------------------------------------------------------------------

  bool get _hasActiveFilters {
    return _dateFromController.text.isNotEmpty ||
        _dateToController.text.isNotEmpty ||
        _clientController.text.isNotEmpty ||
        _salesRepController.text.isNotEmpty ||
        _productFilter.isNotEmpty ||
        _priorityFilter.isNotEmpty;
  }

  int _severity(String p) {
    switch (p.trim().toUpperCase()) {
      case 'HIGH':
        return 3;
      case 'MEDIUM':
        return 2;
      case 'LOW':
        return 1;
      default:
        return 0;
    }
  }

  List<Interaction> get _filteredInteractions {
    final list = _interactions.where((i) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final matches =
            i.clientName.toLowerCase().contains(q) ||
            i.clientContact.toLowerCase().contains(q) ||
            (i.employeeName?.toLowerCase().contains(q) ?? false) ||
            i.employee.toLowerCase().contains(q) ||
            i.discussionNotes.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (_dateFromController.text.isNotEmpty &&
          i.date.compareTo(_dateFromController.text) < 0) {
        return false;
      }
      if (_dateToController.text.isNotEmpty &&
          i.date.compareTo(_dateToController.text) > 0) {
        return false;
      }
      if (_clientController.text.isNotEmpty &&
          !i.clientName.toLowerCase().contains(
            _clientController.text.toLowerCase(),
          )) {
        return false;
      }
      if (_salesRepController.text.isNotEmpty) {
        final rep = (i.employeeName ?? i.employee).toLowerCase();
        if (!rep.contains(_salesRepController.text.toLowerCase())) {
          return false;
        }
      }
      if (_priorityFilter.isNotEmpty &&
          i.priority.trim().toUpperCase() !=
              _priorityFilter.trim().toUpperCase()) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnInteractions) {
        case 'client':
          cmp = a.clientName.toLowerCase().compareTo(
            b.clientName.toLowerCase(),
          );
          break;
        case 'rep':
          final aRep = (a.employeeName ?? a.employee).toLowerCase();
          final bRep = (b.employeeName ?? b.employee).toLowerCase();
          cmp = aRep.compareTo(bRep);
          break;
        case 'follow_up':
          final aKey = '${a.followUpDate} ${a.followUpTime}';
          final bKey = '${b.followUpDate} ${b.followUpTime}';
          cmp = aKey.compareTo(bKey);
          break;
        case 'priority':
          cmp = _severity(a.priority).compareTo(_severity(b.priority));
          break;
        case 'notes':
          cmp = a.discussionNotes.toLowerCase().compareTo(
            b.discussionNotes.toLowerCase(),
          );
          break;
        case 'date':
        default:
          cmp = a.date.compareTo(b.date);
      }
      return _sortAscendingInteractions ? cmp : -cmp;
    });

    return list;
  }

  List<Sale> get _filteredSales {
    final list = _sales.where((s) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final matches =
            s.clientName.toLowerCase().contains(q) ||
            s.product.toLowerCase().contains(q) ||
            (s.productDisplay?.toLowerCase().contains(q) ?? false) ||
            s.company.toLowerCase().contains(q) ||
            s.scheme.toLowerCase().contains(q) ||
            (s.salesRepName?.toLowerCase().contains(q) ?? false) ||
            s.salesRep.toLowerCase().contains(q) ||
            s.remarks.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (_dateFromController.text.isNotEmpty &&
          s.date.compareTo(_dateFromController.text) < 0) {
        return false;
      }
      if (_dateToController.text.isNotEmpty &&
          s.date.compareTo(_dateToController.text) > 0) {
        return false;
      }
      if (_clientController.text.isNotEmpty &&
          !s.clientName.toLowerCase().contains(
            _clientController.text.toLowerCase(),
          )) {
        return false;
      }
      if (_salesRepController.text.isNotEmpty) {
        final rep = (s.salesRepName ?? s.salesRep).toLowerCase();
        if (!rep.contains(_salesRepController.text.toLowerCase())) {
          return false;
        }
      }
      if (_productFilter.isNotEmpty && s.product != _productFilter) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnSales) {
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
      return _sortAscendingSales ? cmp : -cmp;
    });

    return list;
  }

  void _onSortInteractions(String column) {
    setState(() {
      if (_sortColumnInteractions == column) {
        _sortAscendingInteractions = !_sortAscendingInteractions;
      } else {
        _sortColumnInteractions = column;
        _sortAscendingInteractions = column != 'date';
      }
    });
  }

  void _onSortSales(String column) {
    setState(() {
      if (_sortColumnSales == column) {
        _sortAscendingSales = !_sortAscendingSales;
      } else {
        _sortColumnSales = column;
        _sortAscendingSales = (column == 'amount' || column == 'date')
            ? false
            : true;
      }
    });
  }

  // ---------------------------------------------------------------------
  // Actions & CRUD
  // ---------------------------------------------------------------------

  Future<bool> _confirmDelete({
    required String title,
    required String content,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteInteraction(dynamic id) async {
    final ok = await _confirmDelete(
      title: 'Delete Interaction',
      content: 'Are you sure you want to delete this interaction?',
    );
    if (!ok) return;
    await ref.read(apiServiceProvider).deleteInteraction(id);
    _load();
  }

  Future<void> _deleteSale(dynamic id) async {
    final ok = await _confirmDelete(
      title: 'Delete Sale',
      content: 'Are you sure you want to delete this sale record?',
    );
    if (!ok) return;
    await ref.read(apiServiceProvider).deleteSale(id);
    _load();
  }

  Future<void> _bulkDelete() async {
    final isInteractions = _activeTab == 'interactions';
    final selectedIds = isInteractions
        ? _selectedInteractionIds
        : _selectedSaleIds;
    if (selectedIds.isEmpty) return;

    final count = selectedIds.length;
    final entityName = isInteractions
        ? (count == 1 ? 'interaction' : 'interactions')
        : (count == 1 ? 'sale' : 'sales');

    final ok = await _confirmDelete(
      title: 'Delete $entityName',
      content: 'Are you sure you want to delete $count selected $entityName?',
    );
    if (!ok) return;

    final api = ref.read(apiServiceProvider);
    for (final id in selectedIds.toList()) {
      if (isInteractions) {
        await api.deleteInteraction(id);
      } else {
        await api.deleteSale(id);
      }
    }
    setState(() => selectedIds.clear());
    _load();
  }

  Future<void> _export() async {
    final format = await pickExportFormat(context);
    if (format == null) return;

    try {
      final isInteractions = _activeTab == 'interactions';
      final rows = isInteractions
          ? _interactions.map(interactionExportRow).toList()
          : _sales.map(saleExportRow).toList();
      final stem = isInteractions ? 'interactions_export' : 'sales_export';
      final label = isInteractions ? 'Interactions Export' : 'Sales Export';

      final savedPath = format == ExportFormat.json
          ? await FileSaver.save(
              filename: '$stem.json',
              bytes: RecordJson.encode(
                type: isInteractions ? 'interactions' : 'sales',
                keys: isInteractions ? interactionsJsonKeys : salesJsonKeys,
                rows: rows,
              ),
              extensions: const ['json'],
              shareText: label,
            )
          : await ExcelIO.exportWorkbook(
              filename: '$stem.xlsx',
              sheetName: isInteractions ? 'Interactions' : 'Sales',
              headers: isInteractions
                  ? interactionsExcelHeaders
                  : salesExcelHeaders,
              rows: rows,
              shareText: label,
            );
      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $savedPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'json'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final currentUserName =
          ref.read(authProvider).user?.name ?? 'Team Member';
      final api = ref.read(apiServiceProvider);
      final isInteractions = _activeTab == 'interactions';

      final rows = RecordJson.isJsonPath(path)
          ? await RecordJson.readRows(
              path,
              isInteractions ? interactionsJsonKeys : salesJsonKeys,
            )
          : await ExcelIO.readDataRows(path);

      final outcome = isInteractions
          ? await runRecordImport(
              payloads: rows
                  .map(
                    (r) => interactionImportPayload(
                      r,
                      currentUserName: currentUserName,
                    ),
                  )
                  .nonNulls,
              existingIdBySignature: {
                for (final i in _interactions) interactionSignatureOf(i): i.id,
              },
              signatureFields: interactionsSignatureFields,
              create: api.createInteraction,
              update: api.updateInteraction,
            )
          : await runRecordImport(
              payloads: rows
                  .map(
                    (r) => saleImportPayload(
                      r,
                      currentUserName: currentUserName,
                    ),
                  )
                  .nonNulls,
              existingIdBySignature: {
                for (final s in _sales) saleSignatureOf(s): s.id,
              },
              signatureFields: salesSignatureFields,
              create: api.createSale,
              update: api.updateSale,
            );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome.describe(isInteractions ? 'interaction' : 'sale'),
            ),
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _showAddModal(AppUser? user) async {
    if (_activeTab == 'interactions') {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AddInteractionModal(currentUser: user),
      );
      if (saved == true) _load();
    } else {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AddSaleModal(currentUser: user),
      );
      if (saved == true) _load();
    }
  }

  Future<void> _editInteraction(Interaction interaction) async {
    final user = ref.read(authProvider).user;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          AddInteractionModal(existing: interaction, currentUser: user),
    );
    if (saved == true) _load();
  }

  Future<void> _editSale(Sale sale) async {
    final user = ref.read(authProvider).user;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddSaleModal(existing: sale, currentUser: user),
    );
    if (saved == true) _load();
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(),
        _buildTabsRow(user),
        _buildSearchRow(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildTableCard(),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // -- Title Row --------------------------------------------------------

  Widget _buildTitleRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        isMobile ? 10 : 16,
        isMobile ? AppSpacing.lg : AppSpacing.xxl,
        isMobile ? 8 : 12,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Info Portal',
          style: isMobile
              ? AppTypography.pageTitleMobile
              : AppTypography.pageTitle,
        ),
      ),
    );
  }

  // -- Tabs & Actions Row ------------------------------------------------

  Widget _buildTabsRow(AppUser? user) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isSales = _activeTab == 'sales';
    final activeIndex = isSales ? 0 : 1;
    const itemWidth = 148.0;

    final slidingSegment = Container(
      height: _controlHeight,
      decoration: BoxDecoration(
        color: _Palette.headerBg,
        border: Border.all(color: _Palette.border),
        borderRadius: BorderRadius.circular(_radius),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: SizedBox(
        width: itemWidth * 2,
        child: Stack(
          children: [
            // The physical moving indicator pill
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              left: activeIndex * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: _Palette.all,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: [
                    BoxShadow(
                      color: _Palette.all.withValues(alpha: 0.25),
                      blurRadius: 5,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
            // Clickable segment labels
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _slidingSegmentItem(
                  label: 'Sales (${_sales.length})',
                  isSelected: isSales,
                  width: itemWidth,
                  onTap: () => setState(() => _activeTab = 'sales'),
                ),
                _slidingSegmentItem(
                  label: 'Interactions (${_interactions.length})',
                  isSelected: !isSales,
                  width: itemWidth,
                  onTap: () => setState(() => _activeTab = 'interactions'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final addButton = AppToolbarButton(
      icon: Icons.add,
      // Shorter on phones so the group never needs to scroll.
      label: isMobile ? 'Add' : (isSales ? 'Add Sale' : 'Add Interaction'),
      isPrimary: true,
      onPressed: () => _showAddModal(user),
    );
    final exportButton = _outlinedIconButton(
      icon: Icons.download_outlined,
      label: 'Export',
      onPressed: _export,
    );
    final importButton = _outlinedIconButton(
      icon: Icons.upload_outlined,
      label: 'Import',
      onPressed: _import,
    );

    // On phones the primary (blue) action leads the group, on the extreme
    // left; desktop keeps Export/Import first with Add trailing.
    final actionButtons = isMobile
        ? <Widget>[
            addButton,
            const SizedBox(width: AppSpacing.sm),
            exportButton,
            const SizedBox(width: AppSpacing.sm),
            importButton,
          ]
        : <Widget>[
            exportButton,
            const SizedBox(width: AppSpacing.sm),
            importButton,
            const SizedBox(width: AppSpacing.sm),
            addButton,
          ];

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: slidingSegment,
            ),
            const SizedBox(height: AppSpacing.md),
            // Compact actions fit on one line — no scrolling, no clipping.
            Row(mainAxisSize: MainAxisSize.min, children: actionButtons),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(children: [slidingSegment, const Spacer(), ...actionButtons]),
    );
  }

  Widget _slidingSegmentItem({
    required String label,
    required bool isSelected,
    required double width,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      height: AppSizing.controlSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? Colors.white : _Palette.textSecondary,
            ),
            child: Text(label, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  Widget _outlinedIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return AppToolbarButton(icon: icon, label: label, onPressed: onPressed);
  }

  // -- Search Row & Selection Action Bar ---------------------------------

  Widget _buildSearchRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isInteractions = _activeTab == 'interactions';
    final selectedIds = isInteractions
        ? _selectedInteractionIds
        : _selectedSaleIds;
    final hasSelection = selectedIds.isNotEmpty;

    final selectionBar = Row(
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
          '${selectedIds.length} selected',
          style: AppTypography.tableCellStrong.copyWith(fontSize: 14),
        ),
      ],
    );

    Color activeFilterColor = _Palette.all;
    if (_priorityFilter == 'HIGH') {
      activeFilterColor = _Palette.high;
    } else if (_priorityFilter == 'MEDIUM') {
      activeFilterColor = _Palette.medium;
    } else if (_priorityFilter == 'LOW') {
      activeFilterColor = _Palette.low;
    }

    final searchBar = _buildSearchBar(
      isMobile: isMobile,
      isInteractions: isInteractions,
      activeFilterColor: activeFilterColor,
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          children: [
            searchBar,
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerRight, child: selectionBar),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          Expanded(flex: 1, child: searchBar),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerRight,
              child: selectionBar,
            ),
          ),
        ],
      ),
    );
  }

  void _onFilterMenuSelected(String val, {required bool isInteractions}) {
    if (val == 'CLEAR') {
      setState(() {
        _dateFromController.clear();
        _dateToController.clear();
        _clientController.clear();
        _salesRepController.clear();
        _productFilter = '';
        _priorityFilter = '';
        if (isInteractions) {
          _sortColumnInteractions = 'date';
          _sortAscendingInteractions = false;
        } else {
          _sortColumnSales = 'date';
          _sortAscendingSales = false;
        }
      });
    } else if (val.startsWith('PRIORITY:')) {
      final p = val.replaceFirst('PRIORITY:', '');
      setState(() {
        _priorityFilter = (p == 'ALL') ? '' : p;
      });
    } else if (val.startsWith('PRODUCT:')) {
      final prod = val.replaceFirst('PRODUCT:', '');
      setState(() {
        _productFilter = (prod == 'ALL') ? '' : prod;
      });
    } else if (val.startsWith('SORT:')) {
      final s = val.replaceFirst('SORT:', '');
      setState(() {
        if (isInteractions) {
          if (s == 'newest') {
            _sortColumnInteractions = 'date';
            _sortAscendingInteractions = false;
          } else if (s == 'oldest') {
            _sortColumnInteractions = 'date';
            _sortAscendingInteractions = true;
          } else if (s == 'client') {
            _sortColumnInteractions = 'client';
            _sortAscendingInteractions = true;
          } else if (s == 'priority') {
            _sortColumnInteractions = 'priority';
            _sortAscendingInteractions = false;
          }
        } else {
          if (s == 'newest') {
            _sortColumnSales = 'date';
            _sortAscendingSales = false;
          } else if (s == 'oldest') {
            _sortColumnSales = 'date';
            _sortAscendingSales = true;
          } else if (s == 'client') {
            _sortColumnSales = 'client';
            _sortAscendingSales = true;
          } else if (s == 'amount') {
            _sortColumnSales = 'amount';
            _sortAscendingSales = false;
          }
        }
      });
    }
  }

  List<PopupMenuEntry<String>> _filterMenuItems({required bool isInteractions}) {
    return [
      if (isInteractions) ...[
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('FILTER BY PRIORITY', style: AppTypography.tableHeader),
        ),
        _filterMenuItem(
          'PRIORITY:ALL',
          'All Priorities',
          _priorityFilter.isEmpty,
          activeColor: _Palette.all,
        ),
        _filterMenuItem(
          'PRIORITY:HIGH',
          'High Priority',
          _priorityFilter == 'HIGH',
          activeColor: _Palette.high,
        ),
        _filterMenuItem(
          'PRIORITY:MEDIUM',
          'Medium Priority',
          _priorityFilter == 'MEDIUM',
          activeColor: _Palette.medium,
        ),
        _filterMenuItem(
          'PRIORITY:LOW',
          'Low Priority',
          _priorityFilter == 'LOW',
          activeColor: _Palette.low,
        ),
        const PopupMenuDivider(height: 12),
      ] else ...[
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text('FILTER BY PRODUCT', style: AppTypography.tableHeader),
        ),
        _filterMenuItem(
          'PRODUCT:ALL',
          'All Products',
          _productFilter.isEmpty,
          activeColor: AppColors.primaryBlue,
        ),
        ...productCategories
            .where((c) => c.$1 != 'ALL')
            .map(
              (c) => _filterMenuItem(
                'PRODUCT:${c.$1}',
                c.$2,
                _productFilter == c.$1,
                activeColor: productColor(c.$1),
              ),
            ),
        const PopupMenuDivider(height: 12),
      ],
      const PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text('SORT BY', style: AppTypography.tableHeader),
      ),
      _filterMenuItem(
        'SORT:newest',
        'Newest First',
        isInteractions
            ? (_sortColumnInteractions == 'date' && !_sortAscendingInteractions)
            : (_sortColumnSales == 'date' && !_sortAscendingSales),
      ),
      _filterMenuItem(
        'SORT:oldest',
        'Oldest First',
        isInteractions
            ? (_sortColumnInteractions == 'date' && _sortAscendingInteractions)
            : (_sortColumnSales == 'date' && _sortAscendingSales),
      ),
      _filterMenuItem(
        'SORT:client',
        'Client Name (A-Z)',
        isInteractions
            ? (_sortColumnInteractions == 'client')
            : (_sortColumnSales == 'client'),
      ),
      if (isInteractions)
        _filterMenuItem(
          'SORT:priority',
          'Priority (High to Low)',
          _sortColumnInteractions == 'priority',
        )
      else
        _filterMenuItem(
          'SORT:amount',
          'Highest Amount',
          _sortColumnSales == 'amount' && !_sortAscendingSales,
        ),
      if (_hasActiveFilters) ...[
        const PopupMenuDivider(height: 12),
        const PopupMenuItem<String>(
          value: 'CLEAR',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.clear_all, size: AppSizing.iconSm, color: AppColors.danger),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Reset All Filters',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  /// Builds the search bar. [isMobile] only changes how the leading
  /// filter-icon cluster is sized: on phones the popup menu's default
  /// 48x48 tap target is taller than this field's 40px height, which was
  /// throwing the icon row off-centre relative to the hint text. Giving it
  /// an explicit compact size there fixes that without touching desktop,
  /// where the field is wide enough that the default sizing never showed it.
  Widget _buildSearchBar({
    required bool isMobile,
    required bool isInteractions,
    required Color activeFilterColor,
  }) {
    final isSearchFocused = _searchFocusNode.hasFocus;

    final filterIcon = Icon(
      _hasActiveFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
      size: AppSizing.iconMd,
      color: _hasActiveFilters ? activeFilterColor : _Palette.textMuted,
    );

    final filterPopup = PopupMenuButton<String>(
      tooltip: 'Filter & sort options',
      padding: EdgeInsets.zero,
      splashRadius: 18,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: _Palette.border),
      ),
      color: Colors.white,
      elevation: 6,
      onSelected: (val) =>
          _onFilterMenuSelected(val, isInteractions: isInteractions),
      itemBuilder: (context) =>
          _filterMenuItems(isInteractions: isInteractions),
      icon: isMobile ? null : filterIcon,
      child: isMobile
          ? SizedBox(width: 28, height: 28, child: Center(child: filterIcon))
          : null,
    );

    final prefixChildren = [
      const SizedBox(width: AppSpacing.sm),
      filterPopup,
      Container(
        width: 1,
        height: 16,
        color: _Palette.border,
        margin: const EdgeInsets.only(
          left: AppSpacing.xxs,
          right: AppSpacing.sm,
        ),
      ),
      const Icon(Icons.search, color: _Palette.textMuted, size: AppSizing.iconMd),
      const SizedBox(width: AppSpacing.xs),
    ];

    return Material(
      color: Colors.white,
      elevation: isSearchFocused ? 2.0 : 1.5,
      shadowColor: isSearchFocused
          ? AppColors.primaryBlue.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(
          color: isSearchFocused ? AppColors.primaryBlue : _Palette.border,
          width: isSearchFocused ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _controlHeight,
        child: TextField(
          focusNode: _searchFocusNode,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: isInteractions
                ? 'Search clients, representatives, notes...'
                : 'Search clients, products, representatives, schemes...',
            hintStyle: const TextStyle(fontSize: 13, color: _Palette.textMuted),
            prefixIconConstraints: BoxConstraints(
              minWidth: 72,
              minHeight: isMobile ? _controlHeight : 0,
              maxHeight: _controlHeight,
            ),
            prefixIcon: isMobile
                ? SizedBox(
                    height: _controlHeight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: prefixChildren,
                    ),
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: prefixChildren),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: _Palette.textMuted,
                      size: AppSizing.iconMd,
                    ),
                    onPressed: () => setState(() => _search = ''),
                    padding: isMobile ? EdgeInsets.zero : null,
                    constraints: isMobile
                        ? const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                            maxWidth: 32,
                            maxHeight: 32,
                          )
                        : null,
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
    );
  }

  PopupMenuItem<String> _filterMenuItem(
    String value,
    String label,
    bool isSelected, {
    Color? activeColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      child: Row(
        children: [
          if (activeColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: activeColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppColors.primaryBlue
                    : _Palette.textPrimary,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check,
              size: AppSizing.iconSm,
              color: AppColors.primaryBlue,
            ),
        ],
      ),
    );
  }

  // -- Table Card --------------------------------------------------------

  Widget _buildTableCard() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isInteractions = _activeTab == 'interactions';
    final interactionItems = _filteredInteractions;
    final saleItems = _filteredSales;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? AppSpacing.lg : AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  isInteractions
                      ? _buildInteractionsTableHeader(interactionItems)
                      : _buildSalesTableHeader(saleItems),
                  Expanded(
                    child: isInteractions
                        ? (interactionItems.isEmpty
                              ? _buildEmptyState(
                                  'No interactions found',
                                  'Try adjusting your search or filters.',
                                )
                              : ListView.separated(
                                  itemCount: interactionItems.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(
                                        height: 1,
                                        color: _Palette.border,
                                      ),
                                  itemBuilder: (_, i) => _InteractionTableRow(
                                    item: interactionItems[i],
                                    selected: _selectedInteractionIds.contains(
                                      interactionItems[i].id,
                                    ),
                                    onSelectChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedInteractionIds.add(
                                          interactionItems[i].id,
                                        );
                                      } else {
                                        _selectedInteractionIds.remove(
                                          interactionItems[i].id,
                                        );
                                      }
                                    }),
                                    onEdit: () =>
                                        _editInteraction(interactionItems[i]),
                                    onDelete: () => _deleteInteraction(
                                      interactionItems[i].id,
                                    ),
                                  ),
                                ))
                        : (saleItems.isEmpty
                              ? _buildEmptyState(
                                  'No sales found',
                                  'Try adjusting your search or filters.',
                                )
                              : ListView.separated(
                                  itemCount: saleItems.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(
                                        height: 1,
                                        color: _Palette.border,
                                      ),
                                  itemBuilder: (_, i) => _SalesTableRow(
                                    sale: saleItems[i],
                                    selected: _selectedSaleIds.contains(
                                      saleItems[i].id,
                                    ),
                                    onSelectChanged: (v) => setState(() {
                                      if (v == true) {
                                        _selectedSaleIds.add(saleItems[i].id);
                                      } else {
                                        _selectedSaleIds.remove(
                                          saleItems[i].id,
                                        );
                                      }
                                    }),
                                    onEdit: () => _editSale(saleItems[i]),
                                    onDelete: () =>
                                        _deleteSale(saleItems[i].id),
                                  ),
                                )),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -- Interactions Table Header -----------------------------------------

  Widget _buildInteractionsTableHeader(List<Interaction> items) {
    final itemIds = items.map((e) => e.id).toSet();
    final allSelected =
        itemIds.isNotEmpty && itemIds.every(_selectedInteractionIds.contains);
    final someSelected = itemIds.any(_selectedInteractionIds.contains);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
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
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedInteractionIds.addAll(itemIds);
                  } else {
                    _selectedInteractionIds.removeAll(itemIds);
                  }
                }),
              ),
            ),
          ),
          _sortableHeader(
            columnKey: 'client',
            title: 'CLIENT & CONTACT',
            flex: 4,
            currentSort: _sortColumnInteractions,
            sortAscending: _sortAscendingInteractions,
            onSort: _onSortInteractions,
          ),
          _sortableHeader(
            columnKey: 'rep',
            title: 'REPRESENTATIVE',
            flex: 3,
            alignment: Alignment.centerLeft,
            currentSort: _sortColumnInteractions,
            sortAscending: _sortAscendingInteractions,
            onSort: _onSortInteractions,
          ),
          _sortableHeader(
            columnKey: 'date',
            title: 'DATE',
            flex: 2,
            alignment: Alignment.center,
            currentSort: _sortColumnInteractions,
            sortAscending: _sortAscendingInteractions,
            onSort: _onSortInteractions,
          ),
          _sortableHeader(
            columnKey: 'follow_up',
            title: 'FOLLOW-UP',
            flex: 3,
            alignment: Alignment.center,
            currentSort: _sortColumnInteractions,
            sortAscending: _sortAscendingInteractions,
            onSort: _onSortInteractions,
          ),
          _sortableHeader(
            columnKey: 'priority',
            title: 'PRIORITY',
            flex: 2,
            alignment: Alignment.center,
            currentSort: _sortColumnInteractions,
            sortAscending: _sortAscendingInteractions,
            onSort: _onSortInteractions,
          ),
          _sortableHeader(
            columnKey: 'notes',
            title: 'NOTES',
            flex: 4,
            currentSort: _sortColumnInteractions,
            sortAscending: _sortAscendingInteractions,
            onSort: _onSortInteractions,
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

  // -- Sales Table Header ------------------------------------------------

  Widget _buildSalesTableHeader(List<Sale> items) {
    final itemIds = items.map((e) => e.id).toSet();
    final allSelected =
        itemIds.isNotEmpty && itemIds.every(_selectedSaleIds.contains);
    final someSelected = itemIds.any(_selectedSaleIds.contains);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
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
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedSaleIds.addAll(itemIds);
                  } else {
                    _selectedSaleIds.removeAll(itemIds);
                  }
                }),
              ),
            ),
          ),
          _sortableHeader(
            columnKey: 'client',
            title: 'CLIENT & DETAILS',
            flex: 4,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
          ),
          _sortableHeader(
            columnKey: 'product',
            title: 'PRODUCT',
            flex: 3,
            alignment: Alignment.centerLeft,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
          ),
          _sortableHeader(
            columnKey: 'amount',
            title: 'AMOUNT',
            flex: 2,
            alignment: Alignment.center,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
          ),
          _sortableHeader(
            columnKey: 'frequency',
            title: 'FREQUENCY',
            flex: 2,
            alignment: Alignment.center,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
          ),
          _sortableHeader(
            columnKey: 'rep',
            title: 'SALES REP',
            flex: 3,
            alignment: Alignment.centerLeft,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
          ),
          _sortableHeader(
            columnKey: 'date',
            title: 'DATE',
            flex: 2,
            alignment: Alignment.center,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
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

  Widget _sortableHeader({
    required String columnKey,
    required String title,
    required int flex,
    required String currentSort,
    required bool sortAscending,
    required ValueChanged<String> onSort,
    Alignment alignment = Alignment.centerLeft,
  }) {
    final isSelected = currentSort == columnKey;
    final mainAxis = alignment == Alignment.center
        ? MainAxisAlignment.center
        : (alignment == Alignment.centerRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start);

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(columnKey),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        hoverColor: AppColors.surfaceHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.xs,
          ),
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
                    ? (sortAscending
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

  Widget _buildEmptyState(String message, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: const BoxDecoration(
              color: _Palette.headerBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: AppSizing.iconDisplay,
              color: _Palette.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(message, style: AppTypography.itemTitle),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: AppTypography.caption),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Interactions Table Row
// ---------------------------------------------------------------------

class _InteractionTableRow extends StatefulWidget {
  const _InteractionTableRow({
    required this.item,
    required this.selected,
    required this.onSelectChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final Interaction item;
  final bool selected;
  final ValueChanged<bool?> onSelectChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_InteractionTableRow> createState() => _InteractionTableRowState();
}

class _InteractionTableRowState extends State<_InteractionTableRow> {
  bool _isHovered = false;

  Widget _buildPriorityPill(String priority) {
    Color bg;
    Color fg;
    String label;
    switch (priority.trim().toUpperCase()) {
      case 'HIGH':
        bg = _Palette.highBg;
        fg = _Palette.high;
        label = 'HIGH';
        break;
      case 'MEDIUM':
        bg = _Palette.mediumBg;
        fg = _Palette.medium;
        label = 'MEDIUM';
        break;
      default:
        bg = _Palette.lowBg;
        fg = _Palette.low;
        label = 'LOW';
    }

    return Container(
      width: 72,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repName =
        widget.item.employeeName ??
        (widget.item.employee.isNotEmpty ? widget.item.employee : '');
    final hasFollowUp = widget.item.followUpDate.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        color: widget.selected
            ? _Palette.rowHover
            : (_isHovered ? _Palette.rowHover : Colors.white),
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

            // Client & Contact
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
                      widget.item.clientName.isEmpty
                          ? '?'
                          : widget.item.clientName[0].toUpperCase(),
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
                          widget.item.clientName.isEmpty
                              ? '—'
                              : widget.item.clientName,
                          style: AppTypography.tableCellStrong,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.item.clientContact.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            widget.item.clientContact,
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

            // Representative
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
                AppFormatters.formatDate(widget.item.date),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: _Palette.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Follow-up
            Expanded(
              flex: 3,
              child: hasFollowUp
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_month_outlined,
                              size: AppSizing.iconXs,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                AppFormatters.formatDate(
                                  widget.item.followUpDate,
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _Palette.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (widget.item.followUpTime.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time_outlined,
                                size: AppSizing.iconXs,
                                color: _Palette.textMuted,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  AppFormatters.formatTime(
                                    widget.item.followUpTime,
                                  ),
                                  style: AppTypography.caption,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    )
                  : const Text(
                      '—',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
            ),

            // Priority
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.center,
                child: _buildPriorityPill(widget.item.priority),
              ),
            ),

            // Notes
            Expanded(
              flex: 4,
              child: widget.item.discussionNotes.isNotEmpty
                  ? Tooltip(
                      message: widget.item.discussionNotes,
                      child: Text(
                        widget.item.discussionNotes,
                        textAlign: TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _Palette.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    )
                  : const Text(
                      '—',
                      textAlign: TextAlign.left,
                      style: AppTypography.caption,
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

// ---------------------------------------------------------------------
// Sales Table Row
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
            ? _Palette.rowHover
            : (_isHovered ? _Palette.rowHover : Colors.white),
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
                overflow: TextOverflow.ellipsis,
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
