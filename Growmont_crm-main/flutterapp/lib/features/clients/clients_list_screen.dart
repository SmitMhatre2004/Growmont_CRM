import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/client.dart';
import '../../shared/widgets/error_state.dart';
import '../auth/auth_provider.dart';
import 'widgets/add_client_modal.dart';

class ClientsListScreen extends ConsumerStatefulWidget {
  const ClientsListScreen({super.key});

  @override
  ConsumerState<ClientsListScreen> createState() => _ClientsListScreenState();
}

class _ClientsListScreenState extends ConsumerState<ClientsListScreen> {
  List<Client> _clients = [];
  String _search = '';
  bool _loading = true;
  String? _error;

  final _searchFocusNode = FocusNode();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      if (_clients.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final user = ref.read(authProvider).user;
      final isAdmin = user?.isAdmin == true;
      final data = await ref
          .read(apiServiceProvider)
          .getClients(employeeId: isAdmin ? null : user?.id);
      if (mounted) {
        setState(() {
          _clients = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        if (_clients.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Refresh failed: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  List<Client> get _filtered {
    final q = _search.toLowerCase();
    if (q.isEmpty) return _clients;
    return _clients.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.contactNumber.toLowerCase().contains(q) ||
          (c.employeeName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _delete(Client client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Client'),
        content: Text('Delete ${client.name}? This cannot be undone.'),
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
    try {
      await ref.read(apiServiceProvider).deleteClient(client.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _showModal({Client? client}) async {
    final user = ref.read(authProvider).user;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AddClientModal(existing: client, currentUser: user),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    final isMobile = AppLayout.isMobile(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitleRow(isAdmin),
            _buildSearchRow(isMobile),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? AppSpacing.lg : AppSpacing.xxl,
                ),
                child: _body(isAdmin, isMobile),
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

  Widget _buildTitleRow(bool isAdmin) {
    final isMobile = AppLayout.isMobile(context);
    final isShort = MediaQuery.sizeOf(context).height < 450;
    final title = Text(
      isAdmin ? 'Clients' : 'My Clients',
      style: isShort
          ? AppTypography.pageTitleMobile.copyWith(fontSize: 18)
          : (isMobile
              ? AppTypography.pageTitleMobile
              : AppTypography.pageTitle),
      overflow: TextOverflow.ellipsis,
    );
    final addButton = SizedBox(
      height: 40.0,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.primaryBlue),
        onPressed: () => _showModal(),
        icon: const Icon(Icons.add, size: AppSizing.iconMd),
        label: const Text('Add Client'),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsInline = constraints.maxWidth >= 380;
        if (!fitsInline) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? AppSpacing.lg : AppSpacing.xxl,
              isShort ? 4 : (isMobile ? 10 : 16),
              isMobile ? AppSpacing.lg : AppSpacing.xxl,
              isShort ? 4 : (isMobile ? 8 : 12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: AppSpacing.md),
                Align(alignment: Alignment.centerLeft, child: addButton),
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? AppSpacing.lg : AppSpacing.xxl,
            isShort ? 4 : 16,
            isMobile ? AppSpacing.lg : AppSpacing.xxl,
            isShort ? 4 : 12,
          ),
          child: Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: AppSpacing.sm),
              addButton,
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchRow(bool isMobile) {
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
          color: isSearchFocused ? AppColors.primaryBlue : AppColors.border,
          width: isSearchFocused ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 40.0,
        child: TextField(
          focusNode: _searchFocusNode,
          controller: _searchController,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search by name, contact or employee...',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.textMuted,
              size: AppSizing.iconMd,
            ),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: AppColors.textMuted,
                      size: AppSizing.iconMd,
                    ),
                    onPressed: () => setState(() {
                      _search = '';
                      _searchController.clear();
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
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
    );

    final countBadge = Text(
      '${_filtered.length} ${_filtered.length == 1 ? 'client' : 'clients'}',
      style: AppTypography.tableCellStrong.copyWith(fontSize: 14),
    );

    final isCompact = MediaQuery.sizeOf(context).width < 500;

    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: searchBar,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24,
        0,
        isMobile ? 16 : 24,
        isMobile ? 8 : 16,
      ),
      child: Row(
        children: [
          Expanded(flex: 1, child: searchBar),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 1,
            child: Align(alignment: Alignment.centerRight, child: countBadge),
          ),
        ],
      ),
    );
  }

  Widget _body(bool isAdmin, bool isMobile) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final card = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: _filtered.isEmpty
          ? (_error != null
                ? ErrorState(
                    message: _error!,
                    title: 'Could not load clients',
                    icon: Icons.handshake_outlined,
                    onRetry: _load,
                  )
                : _buildEmptyState(isAdmin))
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              itemCount: _filtered.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final client = _filtered[i];
                return _ClientRow(
                  client: client,
                  isMobile: isMobile,
                  showOwner: isAdmin,
                  // Non-admins only ever see their own clients (server-side
                  // filtered), so any row they can see, they can edit.
                  canEdit: true,
                  canDelete: isAdmin,
                  onOpen: () => context.push('/clients/${client.id}'),
                  onEdit: () => _showModal(client: client),
                  onDelete: () => _delete(client),
                );
              },
            ),
    );

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryGreen,
      child: card,
    );
  }

  Widget _buildEmptyState(bool isAdmin) {
    final isFiltered = _search.isNotEmpty;

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
                        Icons.handshake_outlined,
                        size: AppSizing.iconEmptyState,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      isFiltered
                          ? 'No clients found'
                          : (isAdmin
                                ? 'No clients found'
                                : 'No clients assigned to you yet'),
                      style: AppTypography.sectionTitle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        isFiltered
                            ? 'Try adjusting your search.'
                            : 'Start building your book of business by adding your first client.',
                        style: AppTypography.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (!isFiltered) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      FilledButton.icon(
                        onPressed: () => _showModal(),
                        icon: const Icon(Icons.add, size: AppSizing.iconMd),
                        label: const Text('Add First Client'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    required this.client,
    required this.isMobile,
    required this.showOwner,
    required this.canEdit,
    required this.canDelete,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Client client;
  final bool isMobile;
  final bool showOwner;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 18,
          vertical: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: isMobile ? 20 : 22,
              backgroundColor: AppColors.surfaceSelected,
              child: Text(
                client.name.isNotEmpty ? client.name[0].toUpperCase() : 'C',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppAccents.blueStrong,
                ),
              ),
            ),
            SizedBox(width: isMobile ? 11 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.name,
                    style: AppTypography.itemTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_outlined,
                        size: AppSizing.iconXs,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        client.contactNumber.isNotEmpty
                            ? client.contactNumber
                            : 'No contact',
                        style: AppTypography.itemSubtitle,
                      ),
                    ],
                  ),
                  if (showOwner && (client.employeeName?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppAccents.greenTint,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(color: AppAccents.greenBorder),
                      ),
                      child: Text(
                        client.employeeName!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppAccents.greenTeal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canEdit || canDelete)
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: AppSizing.iconMd,
                  color: AppColors.textMuted,
                ),
                padding: EdgeInsets.zero,
                tooltip: 'Manage client',
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  if (canEdit)
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: AppSizing.iconSm,
                            color: AppColors.info,
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Text('Edit', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: AppSizing.iconSm,
                            color: AppColors.danger,
                          ),
                          SizedBox(width: AppSpacing.sm),
                          Text(
                            'Delete',
                            style: TextStyle(fontSize: 13, color: AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                ],
              )
            else
              const Icon(
                Icons.chevron_right,
                size: AppSizing.iconMd,
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
