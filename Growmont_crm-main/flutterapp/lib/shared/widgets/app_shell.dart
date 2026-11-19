import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../features/attendance/dashboard_ring.dart';
import '../../features/auth/auth_provider.dart';
import 'app_bottom_nav.dart';
import 'app_sidebar.dart';
import 'branch_container.dart' show MoreSheetScope;
import 'dev_test_banner.dart';

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
  static const int reports = 7;
  static const int attendance = 8;
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
            body: Column(
              children: [
                const DevTestBanner(),
                Expanded(
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOutCubic,
                        width: isSidebarCollapsed
                            ? AppSizing.sidebarCollapsedWidth
                            : AppSizing.sidebarWidth,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            right: BorderSide(
                              color: AppColors.border,
                              width: 1,
                            ),
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

/// Height of the Growmont logo in the phone top bar (it was 28).
const double kPhoneLogoHeight = 36;

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
        label: 'Interactions',
        branchIndex: AppBranch.interactions,
      ),
      const BottomNavItem(
        icon: Icons.handshake_outlined,
        activeIcon: Icons.handshake,
        label: 'Clients',
        branchIndex: AppBranch.clients,
      ),
      // Reports is available to everyone; Employees and Info Portal are
      // admin-only. All three would take the bar past five destinations,
      // so they sit behind "More" — which is why it is no longer gated on
      // isAdmin: a non-admin still needs a way through to Reports.
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
        // No white band: the page background shows through from the very top
        // of the screen, status bar included. Nothing tints or shadows it on
        // scroll, and there is no divider line.
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleSpacing: AppSpacing.lg,
        title: Image.asset(
          'assets/images/growmont-logo_coloured-large-size.webp',
          height: kPhoneLogoHeight,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
        ),
        actions: [
          // The attendance ring: Dashboard only (and, inside it, phones with
          // attendance set up only).
          if (navigationShell.currentIndex == AppBranch.dashboard)
            DashboardRingButton(
              onOpenAttendance: () => onSelectBranch(AppBranch.attendance),
            ),
          _ProfileAvatarButton(
            onOpenProfile: () => onSelectBranch(AppBranch.profile),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      // The scope lets a swipe past Clients open the same More sheet the
      // nav bar's More button opens.
      body: MoreSheetScope(
        open: () => _showMoreSheet(context, onSelectBranch, isAdmin),
        child: Column(
          children: [
            const DevTestBanner(),
            Expanded(child: navigationShell),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        items: items,
        currentBranch: navigationShell.currentIndex,
        onSelect: onSelectBranch,
        onMore: () => _showMoreSheet(context, onSelectBranch, isAdmin),
      ),
    );
  }

  void _showMoreSheet(
    BuildContext context,
    ValueChanged<int> onSelect,
    bool isAdmin,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topLg),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.assessment_outlined,
                color: AppColors.primaryBlue,
              ),
              title: const Text('Reports'),
              onTap: () {
                Navigator.pop(sheetContext);
                onSelect(AppBranch.reports);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.fingerprint,
                color: AppColors.primaryBlue,
              ),
              title: const Text('Attendance'),
              onTap: () {
                Navigator.pop(sheetContext);
                onSelect(AppBranch.attendance);
              },
            ),
            if (isAdmin) ...[
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
            ],
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
        // Same height as the attendance pill beside it, ring included. A
        // solid brand gradient with white initials, so it never fades into
        // the page background.
        child: Container(
          width: kAttendancePillHeight,
          height: kAttendancePillHeight,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppPalette.green600, AppPalette.navy700],
            ),
          ),
          child: CircleAvatar(
            radius: kAttendancePillHeight / 2,
            backgroundColor: Colors.transparent,
            foregroundImage: avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: Text(
              user?.initials ?? 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
