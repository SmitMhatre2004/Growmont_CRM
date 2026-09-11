import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../features/auth/auth_provider.dart';
import 'app_bottom_nav.dart';
import 'app_sidebar.dart';

/// Shell branch indices, matching the order declared in `app_router.dart`.
class AppBranch {
  AppBranch._();

  static const int dashboard = 0;
  static const int sales = 1;
  static const int interactions = 2;
  static const int clients = 3;
  static const int employees = 4;
  static const int infoPortal = 5;
  static const int profile = 6;
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      // Tapping the active destination pops back to its root, the standard
      // bottom-nav behaviour.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSidebarCollapsed = ref.watch(sidebarCollapsedProvider);
    final isWide = !AppLayout.isMobile(context);

    if (isWide) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
            ref.read(sidebarCollapsedProvider.notifier).update((v) => !v);
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  width: isSidebarCollapsed ? 80 : 195,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: AppColors.border, width: 1),
                    ),
                  ),
                  child: AppSidebar(
                    isCompact: isSidebarCollapsed,
                    onNavigate: () {},
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xl,
                      right: AppSpacing.lg,
                    ),
                    child: ClipRect(child: widget.navigationShell),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _MobileShell(
      navigationShell: widget.navigationShell,
      onSelectBranch: _goBranch,
    );
  }
}

/// Phone layout: brand app bar with a profile avatar on the right, and a
/// bottom navigation bar in place of the drawer.
class _MobileShell extends ConsumerWidget {
  const _MobileShell({
    required this.navigationShell,
    required this.onSelectBranch,
  });

  final StatefulNavigationShell navigationShell;
  final ValueChanged<int> onSelectBranch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.isAdmin == true;

    final items = <BottomNavItem>[
      const BottomNavItem(
        icon: Icons.dashboard_outlined,
        activeIcon: Icons.dashboard,
        label: 'Dashboard',
        branchIndex: AppBranch.dashboard,
      ),
      const BottomNavItem(
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        label: 'Sales',
        branchIndex: AppBranch.sales,
      ),
      const BottomNavItem(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: 'Chats',
        branchIndex: AppBranch.interactions,
      ),
      const BottomNavItem(
        icon: Icons.handshake_outlined,
        activeIcon: Icons.handshake,
        label: 'Clients',
        branchIndex: AppBranch.clients,
      ),
      // Employees and Info Portal are admin-only and would take the bar past
      // five destinations, so they sit behind "More".
      if (isAdmin)
        const BottomNavItem(
          icon: Icons.grid_view_outlined,
          activeIcon: Icons.grid_view,
          label: 'More',
          branchIndex: BottomNavItem.moreBranch,
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Image.asset(
          'assets/images/growmont-logo_coloured-large-size.webp',
          height: 28,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
        ),
        actions: [
          _ProfileAvatarButton(
            onOpenProfile: () => onSelectBranch(AppBranch.profile),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        items: items,
        currentBranch: navigationShell.currentIndex,
        onSelect: onSelectBranch,
        onMore: () => _showMoreSheet(context, onSelectBranch),
      ),
    );
  }

  void _showMoreSheet(BuildContext context, ValueChanged<int> onSelect) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topLg),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: AppRadius.brXs,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(
                Icons.people_outline,
                color: AppColors.primaryBlue,
              ),
              title: const Text('Employees'),
              onTap: () {
                Navigator.pop(sheetContext);
                onSelect(AppBranch.employees);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primaryBlue,
              ),
              title: const Text('Info Portal'),
              onTap: () {
                Navigator.pop(sheetContext);
                onSelect(AppBranch.infoPortal);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// Circular avatar in the app bar. Tapping opens a menu with Profile and
/// Logout — the pattern the user asked for, matching Google's apps.
class _ProfileAvatarButton extends ConsumerWidget {
  const _ProfileAvatarButton({required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final avatarUrl = AppConfig.mediaUrl(user?.avatar);

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
      onSelected: (value) {
        if (value == 'profile') {
          onOpenProfile();
        } else if (value == 'logout') {
          ref.read(authProvider.notifier).logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                user?.name ?? 'User',
                style: AppTypography.itemTitle,
                overflow: TextOverflow.ellipsis,
              ),
              if ((user?.email ?? '').isNotEmpty)
                Text(
                  user!.email,
                  style: AppTypography.caption,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'profile',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.person_outline),
            title: Text('Profile'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.logout, color: AppColors.danger),
            title: Text('Logout'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.primaryGreenSoft,
          foregroundImage: avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: Text(
            user?.initials ?? 'U',
            style: const TextStyle(
              color: AppColors.primaryGreenDark,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
