import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/excel/excel_io.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/interaction.dart';
import '../../models/user.dart';
import '../auth/auth_provider.dart';
import 'interactions_excel.dart';
import 'widgets/add_interaction_modal.dart';

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

class InteractionsScreen extends ConsumerStatefulWidget {
  const InteractionsScreen({super.key});

  @override
  ConsumerState<InteractionsScreen> createState() => _InteractionsScreenState();
}

class _InteractionsScreenState extends ConsumerState<InteractionsScreen> {
  // Control metrics come from the shared design tokens so every screen's
  // toolbar sits on the same baseline with the same corner treatment.
  static const double _controlHeight = AppSizing.controlMd; // 40
  static const double _radius = AppRadius.md; // 8 - controls are not pills

  List<Interaction> _interactions = [];
  bool _loading = true;

  // Search
  String _search = '';

  // Quick priority filter
  String _priorityFilter = ''; // empty = all

  // Sorting
  String _sortColumn = 'date';
  bool _sortAscending = false;

  // Selection (for bulk delete)
  final Set<dynamic> _selectedIds = {};

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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).user;
      final selfId = user?.isAdmin == true ? null : user?.id;
      final data = await ref.read(apiServiceProvider).getInteractions(
        employeeId: selfId,
      );
      if (mounted) {
        setState(() {
          _interactions = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Filtering / sorting
  // ---------------------------------------------------------------------

  bool _matchesSearch(Interaction i) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return i.clientName.toLowerCase().contains(q) ||
        i.clientContact.toLowerCase().contains(q) ||
        (i.employeeName?.toLowerCase().contains(q) ?? false) ||
        i.employee.toLowerCase().contains(q) ||
        i.discussionNotes.toLowerCase().contains(q);
  }

  bool get _hasActiveFilters => _priorityFilter.isNotEmpty;

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

  List<Interaction> get _filtered {
    Iterable<Interaction> list = _interactions.where(_matchesSearch);

    if (_priorityFilter.isNotEmpty) {
      list = list.where(
        (i) =>
            i.priority.trim().toUpperCase() ==
            _priorityFilter.trim().toUpperCase(),
      );
    }

    final result = list.toList();
    result.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
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
      return _sortAscending ? cmp : -cmp;
    });
    return result;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = column != 'date'; // date defaults newest-first
      }
    });
  }

  void _selectTab(String? priority) {
    setState(() {
      _priorityFilter = priority ?? '';
    });
  }

  // ---------------------------------------------------------------------
  // CRUD / bulk actions
  // ---------------------------------------------------------------------

  Future<void> _delete(dynamic id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Interaction'),
        content: const Text(
          'Are you sure you want to delete this interaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteInteraction(id);
    _load();
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Interactions'),
        content: Text(
          'Are you sure you want to delete $count selected interaction${count == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _selectedIds.toList()) {
      await ref.read(apiServiceProvider).deleteInteraction(id);
    }
    setState(() => _selectedIds.clear());
    _load();
  }

  Future<void> _export() async {
    try {
      final savedPath = await ExcelIO.exportWorkbook(
        filename: 'interactions_export.xlsx',
        sheetName: 'Interactions',
        headers: interactionsExcelHeaders,
        rows: _interactions.map(interactionExportRow).toList(),
        shareText: 'Interactions Export',
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result?.files.single.path == null) return;
    try {
      final rows = await ExcelIO.readDataRows(result!.files.single.path!);
      final currentUserName =
          ref.read(authProvider).user?.name ?? 'Team Member';
      final api = ref.read(apiServiceProvider);
      var count = 0;
      for (final row in rows) {
        final payload = interactionImportPayload(
          row,
          currentUserName: currentUserName,
        );
        if (payload == null) continue;
        try {
          await api.createInteraction(payload);
          count++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported $count interaction(s)')));
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

  Future<void> _showModal(AppUser? user, {Interaction? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          AddInteractionModal(existing: existing, currentUser: user),
    );
    if (saved == true) _load();
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleRow(),
        _buildTabsRow(user),
        _buildSearchRow(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildTableCard(filtered),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  // -- Title row: "Interactions" ------------------------------------------

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
          'Interactions',
          style: isMobile
              ? AppTypography.pageTitleMobile
              : AppTypography.pageTitle,
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
        icon: Icon(icon, size: AppSizing.iconMd),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _Palette.textPrimary,
          side: const BorderSide(color: _Palette.border),
          backgroundColor: AppColors.surface,
        ),
      ),
    );
  }

  // -- Tabs row: physical sliding priority filter + Export/Import + Add Interaction

  Widget _buildTabsRow(AppUser? user) {
    int activeIndex = 0;
    Color activeColor = _Palette.all;
    if (_priorityFilter == 'HIGH') {
      activeIndex = 1;
      activeColor = _Palette.high;
    } else if (_priorityFilter == 'MEDIUM') {
      activeIndex = 2;
      activeColor = _Palette.medium;
    } else if (_priorityFilter == 'LOW') {
      activeIndex = 3;
      activeColor = _Palette.low;
    }

    const itemWidth = 74.0;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    final segmentWidget = Container(
      height: _controlHeight,
      decoration: BoxDecoration(
        color: _Palette.headerBg,
        border: Border.all(color: _Palette.border),
        borderRadius: BorderRadius.circular(_radius),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: SizedBox(
        width: itemWidth * 4,
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.25),
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
                  label: 'All',
                  isSelected: activeIndex == 0,
                  width: itemWidth,
                  onTap: () => _selectTab(null),
                ),
                _slidingSegmentItem(
                  label: 'High',
                  isSelected: activeIndex == 1,
                  width: itemWidth,
                  onTap: () => _selectTab('HIGH'),
                ),
                _slidingSegmentItem(
                  label: 'Medium',
                  isSelected: activeIndex == 2,
                  width: itemWidth,
                  onTap: () => _selectTab('MEDIUM'),
                ),
                _slidingSegmentItem(
                  label: 'Low',
                  isSelected: activeIndex == 3,
                  width: itemWidth,
                  onTap: () => _selectTab('LOW'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _outlinedIconButton(
          icon: Icons.download_outlined,
          label: 'Export',
          onPressed: _export,
        ),
        const SizedBox(width: AppSpacing.sm),
        _outlinedIconButton(
          icon: Icons.upload_outlined,
          label: 'Import',
          onPressed: _import,
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: _controlHeight,
          child: FilledButton.icon(
            onPressed: () => _showModal(user),
            icon: const Icon(Icons.add, size: AppSizing.iconMd),
            label: const Text('Add Interaction'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
          ),
        ),
      ],
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: segmentWidget,
            ),
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: actionButtons,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(children: [segmentWidget, const Spacer(), actionButtons]),
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

  // -- Search row / Selection action bar -----------------------------------

  Widget _buildSearchRow() {
    final hasSelection = _selectedIds.isNotEmpty;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

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
            hintText: 'Search clients, representatives, notes...',
            hintStyle: const TextStyle(fontSize: 13, color: _Palette.textMuted),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 72,
              maxHeight: 40,
            ),
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: AppSpacing.sm),
                PopupMenuButton<String>(
                  tooltip: 'Filter & sort options',
                  icon: Icon(
                    _hasActiveFilters
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                    size: AppSizing.iconMd,
                    color: _hasActiveFilters
                        ? activeFilterColor
                        : _Palette.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  splashRadius: 18,
                  offset: const Offset(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: const BorderSide(color: _Palette.border),
                  ),
                  color: Colors.white,
                  elevation: 6,
                  onSelected: (val) {
                    if (val == 'CLEAR') {
                      setState(() {
                        _priorityFilter = '';
                        _sortColumn = 'date';
                        _sortAscending = false;
                      });
                    } else if (val.startsWith('PRIORITY:')) {
                      final p = val.replaceFirst('PRIORITY:', '');
                      setState(() {
                        _priorityFilter = (p == 'ALL') ? '' : p;
                      });
                    } else if (val.startsWith('SORT:')) {
                      final s = val.replaceFirst('SORT:', '');
                      setState(() {
                        if (s == 'newest') {
                          _sortColumn = 'date';
                          _sortAscending = false;
                        } else if (s == 'oldest') {
                          _sortColumn = 'date';
                          _sortAscending = true;
                        } else if (s == 'client') {
                          _sortColumn = 'client';
                          _sortAscending = true;
                        } else if (s == 'priority') {
                          _sortColumn = 'priority';
                          _sortAscending = false;
                        }
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text(
                        'FILTER BY PRIORITY',
                        style: AppTypography.tableHeader,
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
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 28,
                      child: Text('SORT BY', style: AppTypography.tableHeader),
                    ),
                    _filterMenuItem(
                      'SORT:newest',
                      'Newest First',
                      _sortColumn == 'date' && !_sortAscending,
                    ),
                    _filterMenuItem(
                      'SORT:oldest',
                      'Oldest First',
                      _sortColumn == 'date' && _sortAscending,
                    ),
                    _filterMenuItem(
                      'SORT:client',
                      'Client Name (A-Z)',
                      _sortColumn == 'client',
                    ),
                    _filterMenuItem(
                      'SORT:priority',
                      'Priority (High to Low)',
                      _sortColumn == 'priority',
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
                              size: AppSizing.iconSm,
                              color: AppColors.danger,
                            ),
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
                  ],
                ),
                Container(
                  width: 1,
                  height: 16,
                  color: _Palette.border,
                  margin: const EdgeInsets.only(
                    left: AppSpacing.xxs,
                    right: AppSpacing.sm,
                  ),
                ),
                const Icon(
                  Icons.search,
                  color: _Palette.textMuted,
                  size: AppSizing.iconMd,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: _Palette.textMuted,
                      size: AppSizing.iconMd,
                    ),
                    onPressed: () => setState(() {
                      _search = '';
                    }),
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
          onChanged: (v) => setState(() {
            _search = v;
          }),
        ),
      ),
    );

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
          '${_selectedIds.length} selected',
          style: AppTypography.tableCellStrong.copyWith(fontSize: 14),
        ),
      ],
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

  // -- Table --------------------------------------------------------------

  Widget _buildTableCard(List<Interaction> items) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
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
          final tableWidth = constraints.maxWidth < 850.0
              ? 850.0
              : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  _buildTableHeader(items),
                  Expanded(
                    child: items.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              color: _Palette.border,
                            ),
                            itemBuilder: (_, i) => _InteractionTableRow(
                              item: items[i],
                              selected: _selectedIds.contains(items[i].id),
                              onSelectChanged: (v) => setState(() {
                                if (v == true) {
                                  _selectedIds.add(items[i].id);
                                } else {
                                  _selectedIds.remove(items[i].id);
                                }
                              }),
                              onEdit: () => _showModal(
                                ref.read(authProvider).user,
                                existing: items[i],
                              ),
                              onDelete: () => _delete(items[i].id),
                            ),
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

  Widget _buildTableHeader(List<Interaction> items) {
    final itemIds = items.map((e) => e.id).toSet();
    final allSelected =
        itemIds.isNotEmpty && itemIds.every(_selectedIds.contains);
    final someSelected = itemIds.any(_selectedIds.contains);

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
                    _selectedIds.addAll(itemIds);
                  } else {
                    _selectedIds.removeAll(itemIds);
                  }
                }),
              ),
            ),
          ),
          _sortableHeader(
            columnKey: 'client',
            title: 'CLIENT & CONTACT',
            flex: 4,
          ),
          _sortableHeader(
            columnKey: 'rep',
            title: 'REPRESENTATIVE',
            flex: 3,
            alignment: Alignment.centerLeft,
          ),
          _sortableHeader(
            columnKey: 'date',
            title: 'DATE',
            flex: 2,
            alignment: Alignment.center,
          ),
          _sortableHeader(
            columnKey: 'follow_up',
            title: 'FOLLOW-UP',
            flex: 3,
            alignment: Alignment.center,
          ),
          _sortableHeader(
            columnKey: 'priority',
            title: 'PRIORITY',
            flex: 2,
            alignment: Alignment.center,
          ),
          _sortableHeader(columnKey: 'notes', title: 'NOTES', flex: 4),
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

  Widget _buildEmptyState() {
    final isFiltered = _search.isNotEmpty || _hasActiveFilters;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.huge,
          horizontal: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
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
            Text(
              isFiltered ? 'No interactions found' : 'No interactions recorded yet',
              style: AppTypography.itemTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isFiltered
                  ? 'Try adjusting your search or filters.'
                  : 'Start logging client conversations by recording your first interaction.',
              style: AppTypography.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: () => _showModal(ref.read(authProvider).user),
              icon: const Icon(Icons.add, size: AppSizing.iconMd),
              label: const Text('Add First Interaction'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Table row
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
