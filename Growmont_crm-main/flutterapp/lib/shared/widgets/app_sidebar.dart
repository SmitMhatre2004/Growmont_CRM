import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';

/// Global provider for sidebar collapsed state on desktop/wide screens.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

class AppSidebar extends ConsumerWidget {
  const AppSidebar({
    super.key,
    this.isCompact,
    this.onNavigate,
    this.isDarkMode = false,
    this.onToggleTheme,
  });

  /// If not null, overrides [sidebarCollapsedProvider].
  final bool? isCompact;
  final VoidCallback? onNavigate;
  final bool isDarkMode;
  final VoidCallback? onToggleTheme;

  void _toggle(WidgetRef ref) {
    ref.read(sidebarCollapsedProvider.notifier).update((v) => !v);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final user = ref.watch(authProvider).user;
        final location = GoRouterState.of(context).matchedLocation;
        final bool isCollapsed =
            (isCompact ?? ref.watch(sidebarCollapsedProvider));

        // t interpolates continuously: 0.0 when collapsed (width <= 80px) to 1.0 when expanded (width >= 195px).
        // This drives the physical, dynamic movement of icons across the sidebar during width transitions.
        final double t =
            ((constraints.maxWidth - 80) / (195 - 80)).clamp(0.0, 1.0);

        // Exact horizontal centering calculations when collapsed:
        // Use a fixed collapsed target width (80.0px in standard layout, or 79.0px if 1px border is applied by AppShell)
        // so icons glide directly and monotonically to their centered position during collapse/expand,
        // without swinging to the right and then left.
        final bool isAppShellInset = (constraints.maxWidth <= 79.0) ||
            ((constraints.maxWidth - 194.0).abs() < 1.0);
        final double collapsedTargetWidth = isAppShellInset ? 79.0 : 80.0;

        // Nav item: card horizontal margin is 12 (ListView 4 + item 8), border is 1. Icon size is 21.
        // Center X = 13 + navIconLeftCollapsed + 10.5 = collapsedTargetWidth / 2 => (collapsedTargetWidth - 47.0) / 2.
        final double navIconLeftCollapsed = (collapsedTargetWidth - 47.0) / 2;
        // Avatar: card horizontal margin is 10, border is 1. Avatar diameter is 30 (radius 15).
        // Center X = 11 + avatarLeftCollapsed + 15.0 = collapsedTargetWidth / 2 => (collapsedTargetWidth - 52.0) / 2.
        final double avatarLeftCollapsed = (collapsedTargetWidth - 52.0) / 2;
        // Logout: card horizontal margin is 10, border is 1. Icon size is 18.
        // Center X = 11 + logoutLeftCollapsed + 9.0 = collapsedTargetWidth / 2 => (collapsedTargetWidth - 40.0) / 2.
        final double logoutLeftCollapsed = (collapsedTargetWidth - 40.0) / 2;

        final String initials = user?.initials ?? 'U';
        final String userName = user?.name ?? 'User';
        final String userEmail = user?.email ?? '';

        final items = <_MenuItem>[
          _MenuItem(
            'dashboard',
            'Dashboard',
            Icons.dashboard_outlined,
            '/dashboard',
          ),
          _MenuItem('sales', 'Sales', Icons.bar_chart_outlined, '/sales'),
          _MenuItem(
            'interactions',
            'Interactions',
            Icons.chat_bubble_outline,
            '/interactions',
          ),
          if (user?.isAdmin == true)
            _MenuItem(
              'employees',
              'Employees',
              Icons.people_outline,
              '/employees',
            ),
          if (user?.isAdmin == true)
            _MenuItem(
              'info-portal',
              'Info Portal',
              Icons.inventory_2_outlined,
              '/info-portal',
            ),
        ];

        // Growmont Theme Colors - Side Nav Color: #0f4a31
        final Color bgColor = isDarkMode
            ? const Color(0xFF092E1E)
            : const Color(0xFF0F4A31);
        final Color textColor = Colors.white;
        final Color subTextColor = Colors.white70;
        final Color activeColor = Colors.white;
        final Color activeBgColor = Colors.white.withValues(alpha: 0.2);
        final Color activeBorderColor = Colors.white.withValues(alpha: 0.35);
        final Color profileCardBg = Colors.white.withValues(alpha: 0.1);
        final Color dividerColor = Colors.white.withValues(alpha: 0.15);

        // Header section: Entire area for the logo is solid white overall.
        // The logo shrinks and expands smoothly as the sidebar collapses and expands.
        // Clicking the logo / header toggles the sidebar (no specific collapse icon).
        final Widget topSection = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1.0,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Tooltip(
            message: isCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
            waitDuration: const Duration(milliseconds: 200),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggle(ref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1600 / 622,
                    child: Image.asset(
                      'assets/images/growmont-logo_coloured-large-size.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Profile section at bottom: Clicking avatar/info opens profile, separated logout button below
        final bool isProfileActive = location.startsWith('/profile');

        final Widget profileCard = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, color: dividerColor),
              const SizedBox(height: 8),
              if (onToggleTheme != null)
                Tooltip(
                  message: isDarkMode ? 'Light mode' : 'Dark mode',
                  waitDuration: const Duration(milliseconds: 200),
                  child: IconButton(
                    icon: Icon(
                      isDarkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: subTextColor,
                      size: 20,
                    ),
                    onPressed: onToggleTheme,
                  ),
                ),
              // Profile Info Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: isProfileActive
                        ? activeBgColor
                        : (t > 0.5 ? profileCardBg : Colors.transparent),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isProfileActive
                          ? activeBorderColor
                          : (t > 0.5 ? dividerColor : Colors.transparent),
                      width: 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        context.go('/profile');
                        onNavigate?.call();
                      },
                      child: SizedBox(
                        height: 48,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // Avatar that physically glides from center to left
                            Positioned(
                              left: lerpDouble(avatarLeftCollapsed, 10.0, t)!,
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: const Color(0xFF6366F1),
                                    child: Text(
                                      initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4ADE80),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: bgColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // User name and email fading in
                            if (t > 0.1)
                              Positioned(
                                left: 48,
                                right: 28,
                                child: Opacity(
                                  opacity: t,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (userEmail.isNotEmpty)
                                        Text(
                                          userEmail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: subTextColor,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            // Chevron icon on the right
                            if (t > 0.2)
                              Positioned(
                                right: 8,
                                child: Opacity(
                                  opacity: t,
                                  child: const Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Separated Logout Button below Profile Info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/');
                      onNavigate?.call();
                    },
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Logout icon that physically glides from center to left
                          Positioned(
                            left: lerpDouble(logoutLeftCollapsed, 12.0, t)!,
                            child: const Icon(
                              Icons.logout_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                          ),
                          // Logout text label fading in
                          if (t > 0.15)
                            Positioned(
                              left: 38,
                              right: 8,
                              child: Opacity(
                                opacity: t,
                                child: const Text(
                                  'Logout',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return Container(
          color: bgColor,
          child: SafeArea(
            child: ClipRect(
              child: Column(
                children: [
                  topSection,
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      children: items.map((item) {
                        final isActive =
                            location == item.path ||
                            (item.path != '/dashboard' &&
                                location.startsWith(item.path));
                        return _buildNavItem(
                          context: context,
                          item: item,
                          isActive: isActive,
                          t: t,
                          iconLeftCollapsed: navIconLeftCollapsed,
                          activeColor: activeColor,
                          inactiveColor: subTextColor,
                          activeBg: activeBgColor,
                          activeBorderColor: activeBorderColor,
                          textColor: textColor,
                          onTap: () {
                            context.go(item.path);
                            onNavigate?.call();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  profileCard,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required _MenuItem item,
    required bool isActive,
    required double t,
    required double iconLeftCollapsed,
    required Color activeColor,
    required Color inactiveColor,
    required Color activeBg,
    required Color activeBorderColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    final double iconLeft = lerpDouble(iconLeftCollapsed, 14.0, t)!;
    // When an item is selected (isActive), the green vertical indicator emerges and nudges the icon and text to the right
    final double nudge = isActive ? (8.0 * t) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Tooltip(
        message: t < 0.5 ? item.label : '',
        waitDuration: const Duration(milliseconds: 150),
        preferBelow: false,
        margin: const EdgeInsets.only(left: 50),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? activeBorderColor : Colors.transparent,
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Active indicator bar
                    Positioned(
                      left: 6,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 3.5,
                        height: isActive ? 18 : 0,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80), // brandGreen
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Nav Icon that actually, physically moves from center (collapsed) to left (expanded),
                    // and smoothly nudges to the right when active
                    AnimatedPositioned(
                      duration: t < 1.0 ? Duration.zero : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      left: iconLeft + nudge,
                      child: Icon(
                        item.icon,
                        color: isActive ? activeColor : inactiveColor,
                        size: 21,
                      ),
                    ),
                    // Text label fading in as sidebar expands, and smoothly nudging to the right when active
                    if (t > 0.05)
                      AnimatedPositioned(
                        duration: t < 1.0 ? Duration.zero : const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        left: 46.0 + nudge,
                        right: 10,
                        child: Opacity(
                          opacity: t,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.fontFamily,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w500,
                              color: isActive ? activeColor : textColor,
                            ),
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.id, this.label, this.icon, this.path);
  final String id;
  final String label;
  final IconData icon;
  final String path;
}
