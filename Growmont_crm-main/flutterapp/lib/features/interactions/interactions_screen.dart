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
import '../../models/user.dart';
import '../auth/auth_provider.dart';
import 'widgets/add_interaction_modal.dart';

/// Local design tokens for this screen only — a clean, neutral
/// "SaaS dashboard" look (thin borders, soft pill badges, plain
/// header row) inspired by the reference screenshot. Doesn't touch
/// the shared AppTheme so nothing else in the app is affected.
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

class InteractionsScreen extends ConsumerStatefulWidget {
  const InteractionsScreen({super.key});

  @override
  ConsumerState<InteractionsScreen> createState() => _InteractionsScreenState();
}

class _InteractionsScreenState extends ConsumerState<InteractionsScreen> {
  static const double _controlHeight = 40.0;
  static const double _radius = 20.0;

  List<Interaction> _interactions = [];
  bool _loading = true;

  // Search
  String _search = '';

  // Quick priority tabs
  final Set<String> _priorityFilter = {}; // empty = all

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
      final data = await ref.read(apiServiceProvider).getInteractions();
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
        (i) => _priorityFilter.contains(i.priority.trim().toUpperCase()),
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
      _priorityFilter.clear();
      if (priority != null) _priorityFilter.add(priority);
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
      final base64Data = await ref
          .read(firestoreServiceProvider)
          .exportInteractionsExcel();
      final bytes = base64Decode(base64Data);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/interactions_export.xlsx');
      await file.writeAsBytes(bytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(file.path)], text: 'Interactions Export');
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
      await ref.read(firestoreServiceProvider).importInteractions(base64);
      _load();
    } catch (_) {}
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
      children: [
        const SizedBox(height: 4),
        _buildTitleRow(),
        _buildTabsRow(user),
        _buildSearchRow(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildTableCard(filtered),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // -- Title row: "Interactions" ------------------------------------------

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
          'Interactions',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _Palette.textPrimary,
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

  // -- Tabs row: physical sliding priority filter + Export/Import + Add Interaction

  Widget _buildTabsRow(AppUser? user) {
    int activeIndex = 0;
    Color activeColor = _Palette.all;
    if (_priorityFilter.length == 1) {
      if (_priorityFilter.contains('HIGH')) {
        activeIndex = 1;
        activeColor = _Palette.high;
      } else if (_priorityFilter.contains('MEDIUM')) {
        activeIndex = 2;
        activeColor = _Palette.medium;
      } else if (_priorityFilter.contains('LOW')) {
        activeIndex = 3;
        activeColor = _Palette.low;
      }
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
      padding: const EdgeInsets.all(3),
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
                  borderRadius: BorderRadius.circular(_radius - 3),
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
            onPressed: () => _showModal(user),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Interaction'),
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
            const SizedBox(height: 10),
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

  // -- Search row / Selection action bar -----------------------------------

  Widget _buildSearchRow() {
    final hasSelection = _selectedIds.isNotEmpty;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    Color activeFilterColor = _Palette.all;
    if (_priorityFilter.contains('HIGH')) {
      activeFilterColor = _Palette.high;
    } else if (_priorityFilter.contains('MEDIUM')) {
      activeFilterColor = _Palette.medium;
    } else if (_priorityFilter.contains('LOW')) {
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
            hintText: 'Search clients, representatives, notes...',
            hintStyle: const TextStyle(
              fontSize: 13.5,
              color: _Palette.textMuted,
            ),
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
                    _priorityFilter.isNotEmpty
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                    size: 19,
                    color: _priorityFilter.isNotEmpty
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
                        _priorityFilter.clear();
                        _sortColumn = 'date';
                        _sortAscending = false;
                      });
                    } else if (val.startsWith('PRIORITY:')) {
                      final p = val.replaceFirst('PRIORITY:', '');
                      _selectTab(p == 'ALL' ? null : p);
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
                      _priorityFilter.contains('HIGH'),
                      activeColor: _Palette.high,
                    ),
                    _filterMenuItem(
                      'PRIORITY:MEDIUM',
                      'Medium Priority',
                      _priorityFilter.contains('MEDIUM'),
                      activeColor: _Palette.medium,
                    ),
                    _filterMenuItem(
                      'PRIORITY:LOW',
                      'Low Priority',
                      _priorityFilter.contains('LOW'),
                      activeColor: _Palette.low,
                    ),
                    const PopupMenuDivider(height: 12),
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
                    if (_priorityFilter.isNotEmpty ||
                        _sortColumn != 'date') ...[
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
                              'Reset Filters',
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          style: const TextStyle(fontSize: 13.5),
          onChanged: (v) => setState(() {
            _search = v;
          }),
        ),
      ),
    );

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
        )
        : null;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Column(
          children: [
            searchBar,
            if (selectionBar != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: selectionBar,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: searchBar,
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: selectionBar != null
                ? Align(
                    alignment: Alignment.centerRight,
                    child: selectionBar,
                  )
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
    final color = activeColor ?? AppColors.primaryBlue;
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: isSelected ? color : _Palette.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? _Palette.textPrimary
                    : _Palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Table --------------------------------------------------------------

  Widget _buildTableCard(List<Interaction> items) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
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
          const Text(
            'No interactions found',
            style: TextStyle(
              color: _Palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try adjusting your search or filters.',
            style: TextStyle(color: _Palette.textMuted, fontSize: 12.5),
          ),
        ],
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
