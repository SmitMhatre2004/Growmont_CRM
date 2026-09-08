import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../auth/auth_provider.dart';
import '../interactions/widgets/add_interaction_modal.dart';
import '../sales/widgets/add_sale_modal.dart';

/// Design tokens matching the SaaS dashboard aesthetic from Interactions screen.
class _Palette {
  _Palette._();

  static const Color border = Color(0xFFE7E8EC);
  static const Color headerBg = Color(0xFFFAFAFB);
  static const Color rowHover = Color(0xFFF5F8FF);

  static const Color textPrimary = Color(0xFF13182B);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFFA0A4AE);

  static const Color all = Color.fromARGB(255, 15, 82, 164);
  static const Color high = Color.fromARGB(255, 220, 50, 50);
  static const Color highBg = Color(0xFFFEF2F2);
  static const Color medium = Color.fromARGB(255, 255, 167, 66);
  static const Color mediumBg = Color(0xFFFFF7ED);
  static const Color low = Color.fromRGBO(240, 226, 72, 1);
  static const Color lowBg = Color.fromARGB(255, 255, 252, 216);
}

class InfoPortalScreen extends ConsumerStatefulWidget {
  const InfoPortalScreen({super.key});

  @override
  ConsumerState<InfoPortalScreen> createState() => _InfoPortalScreenState();
}

class _InfoPortalScreenState extends ConsumerState<InfoPortalScreen> {
  static const double _controlHeight = 40.0;
  static const double _radius = 20.0;

  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
  bool _loading = true;

  // Active Tab: 'interactions' or 'sales'
  String _activeTab = 'interactions';

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
                  backgroundColor: Colors.red.shade600,
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
    try {
      final isInteractions = _activeTab == 'interactions';
      final base64Data = isInteractions
          ? await ref.read(firestoreServiceProvider).exportInteractionsExcel()
          : await ref.read(firestoreServiceProvider).exportSalesExcel();

      final bytes = base64Decode(base64Data);
      final dir = await getTemporaryDirectory();
      final fileName = isInteractions
          ? 'interactions_export.xlsx'
          : 'sales_export.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles([
        XFile(file.path),
      ], text: isInteractions ? 'Interactions Export' : 'Sales Export');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result?.files.single.path == null) return;
    try {
      final bytes = await File(result!.files.single.path!).readAsBytes();
      final base64 = base64Encode(bytes);
      if (_activeTab == 'interactions') {
        await ref.read(firestoreServiceProvider).importInteractions(base64);
      } else {
        await ref.read(firestoreServiceProvider).importSales(base64);
      }
      _load();
    } catch (_) {}
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
      children: [
        const SizedBox(height: 4),
        _buildTitleRow(),
        _buildTabsRow(user),
        _buildSearchRow(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildTableCard(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // -- Title Row --------------------------------------------------------

  Widget _buildTitleRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        isMobile ? 10 : 16,
        isMobile ? 16 : 24,
        isMobile ? 8 : 12,
      ),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Info Portal',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _Palette.textPrimary,
          ),
        ),
      ),
    );
  }

  // -- Tabs & Actions Row ------------------------------------------------

  Widget _buildTabsRow(AppUser? user) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isInteractions = _activeTab == 'interactions';
    final activeIndex = isInteractions ? 0 : 1;
    const itemWidth = 148.0;

    final slidingSegment = Container(
      height: _controlHeight,
      decoration: BoxDecoration(
        color: _Palette.headerBg,
        border: Border.all(color: _Palette.border),
        borderRadius: BorderRadius.circular(_radius),
      ),
      padding: const EdgeInsets.all(3),
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
                  borderRadius: BorderRadius.circular(_radius - 3),
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
                  label: 'Interactions (${_interactions.length})',
                  isSelected: isInteractions,
                  width: itemWidth,
                  onTap: () => setState(() => _activeTab = 'interactions'),
                ),
                _slidingSegmentItem(
                  label: 'Sales (${_sales.length})',
                  isSelected: !isInteractions,
                  width: itemWidth,
                  onTap: () => setState(() => _activeTab = 'sales'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final actionButtons = <Widget>[
      _outlinedIconButton(
        icon: Icons.download_outlined,
        label: 'Export',
        onPressed: _export,
      ),
      const SizedBox(width: 8),
      _outlinedIconButton(
        icon: Icons.upload_outlined,
        label: 'Import',
        onPressed: _import,
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: _controlHeight,
        child: FilledButton.icon(
          onPressed: () => _showAddModal(user),
          icon: const Icon(Icons.add, size: 18),
          label: Text(isInteractions ? 'Add Interaction' : 'Add Sale'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryGreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ),
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
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: actionButtons,
              ),
            ),
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
      height: _controlHeight - 6,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius - 3),
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

  // -- Search Row & Selection Action Bar ---------------------------------

  Widget _buildSearchRow() {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isInteractions = _activeTab == 'interactions';
    final selectedIds = isInteractions
        ? _selectedInteractionIds
        : _selectedSaleIds;
    final hasSelection = selectedIds.isNotEmpty;

    final selectionBar = hasSelection
        ? Material(
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
                      color: _Palette.all,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${selectedIds.length} selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _Palette.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => setState(() => selectedIds.clear()),
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
          )
        : null;

    Color activeFilterColor = _Palette.all;
    if (_priorityFilter == 'HIGH') {
      activeFilterColor = _Palette.high;
    } else if (_priorityFilter == 'MEDIUM') {
      activeFilterColor = _Palette.medium;
    } else if (_priorityFilter == 'LOW') {
      activeFilterColor = _Palette.low;
    }

    final isSearchFocused = _searchFocusNode.hasFocus;

    final searchBar = Material(
      color: Colors.white,
      elevation: isSearchFocused ? 2.0 : 1.5,
      shadowColor: isSearchFocused
          ? AppColors.primaryGreen.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.08),
      shape: StadiumBorder(
        side: BorderSide(
          color: isSearchFocused ? AppColors.primaryGreen : _Palette.border,
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
            hintStyle:
                const TextStyle(fontSize: 13.5, color: _Palette.textMuted),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 72,
              maxHeight: 40,
            ),
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  tooltip: 'Filter & sort options',
                  icon: Icon(
                    _hasActiveFilters
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                    size: 19,
                    color: _hasActiveFilters
                        ? activeFilterColor
                        : _Palette.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                  offset: const Offset(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: _Palette.border),
                  ),
                  color: Colors.white,
                  elevation: 6,
                  onSelected: (val) {
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
                  },
                  itemBuilder: (context) => [
                    if (isInteractions) ...[
                      const PopupMenuItem<String>(
                        enabled: false,
                        height: 28,
                        child: Text(
                          'FILTER BY PRIORITY',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _Palette.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
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
                        child: Text(
                          'FILTER BY PRODUCT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _Palette.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      _filterMenuItem(
                        'PRODUCT:ALL',
                        'All Products',
                        _productFilter.isEmpty,
                      ),
                      ...productCategories
                          .where((c) => c.$1 != 'ALL')
                          .map(
                            (c) => _filterMenuItem(
                              'PRODUCT:${c.$1}',
                              c.$2,
                              _productFilter == c.$1,
                            ),
                          ),
                      const PopupMenuDivider(height: 12),
                    ],
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text(
                        'SORT BY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _Palette.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _filterMenuItem(
                      'SORT:newest',
                      'Newest First',
                      isInteractions
                          ? (_sortColumnInteractions == 'date' &&
                                !_sortAscendingInteractions)
                          : (_sortColumnSales == 'date' && !_sortAscendingSales),
                    ),
                    _filterMenuItem(
                      'SORT:oldest',
                      'Oldest First',
                      isInteractions
                          ? (_sortColumnInteractions == 'date' &&
                                _sortAscendingInteractions)
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
                            Icon(
                              Icons.clear_all,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Reset All Filters',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  width: 1,
                  height: 16,
                  color: _Palette.border,
                  margin: const EdgeInsets.only(left: 2, right: 8),
                ),
                const Icon(
                  Icons.search,
                  color: _Palette.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 4),
              ],
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: _Palette.textMuted,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _search = ''),
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          style: const TextStyle(fontSize: 13.5),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          children: [
            searchBar,
            if (selectionBar != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: selectionBar),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          Expanded(flex: 1, child: searchBar),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: selectionBar != null
                ? Align(alignment: Alignment.centerRight, child: selectionBar)
                : const SizedBox.shrink(),
          ),
        ],
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
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primaryBlue : _Palette.textPrimary,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check,
              size: 16,
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
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(color: AppColors.primaryBlue),
      child: Row(
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

  // -- Sales Table Header ------------------------------------------------

  Widget _buildSalesTableHeader(List<Sale> items) {
    final itemIds = items.map((e) => e.id).toSet();
    final allSelected =
        itemIds.isNotEmpty && itemIds.every(_selectedSaleIds.contains);
    final someSelected = itemIds.any(_selectedSaleIds.contains);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: const BoxDecoration(color: AppColors.primaryBlue),
      child: Row(
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
            alignment: Alignment.center,
            currentSort: _sortColumnSales,
            sortAscending: _sortAscendingSales,
            onSort: _onSortSales,
          ),
          _sortableHeader(
            columnKey: 'amount',
            title: 'AMOUNT',
            flex: 2,
            alignment: Alignment.centerRight,
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
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
                    ? (sortAscending
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

  Widget _buildEmptyState(String message, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: _Palette.headerBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              size: 36,
              color: _Palette.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: _Palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: _Palette.textMuted, fontSize: 12.5),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
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
                          widget.item.clientName.isEmpty
                              ? '—'
                              : widget.item.clientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _Palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.item.clientContact.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.item.clientContact,
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

            // Representative
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
                AppFormatters.formatDate(widget.item.date),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
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
                              size: 13,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                AppFormatters.formatDate(
                                  widget.item.followUpDate,
                                ),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _Palette.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (widget.item.followUpTime.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time_outlined,
                                size: 13,
                                color: _Palette.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  AppFormatters.formatTime(
                                    widget.item.followUpTime,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: _Palette.textMuted,
                                  ),
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
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _Palette.textMuted,
                      ),
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
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _Palette.textMuted,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
