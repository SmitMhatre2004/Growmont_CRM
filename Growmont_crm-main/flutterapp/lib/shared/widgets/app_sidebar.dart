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
    final user = ref.watch(authProvider).user;
    final location = GoRouterState.of(context).matchedLocation;
    final bool effectiveCompact =
        isCompact ?? ref.watch(sidebarCollapsedProvider);

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
        _MenuItem('employees', 'Employees', Icons.people_outline, '/employees'),
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
    final Color brandGreen = const Color(0xFF4ADE80);
    final Color textColor = Colors.white;
    final Color subTextColor = Colors.white70;
    final Color activeColor = Colors.white;
    final Color activeBgColor = Colors.white.withValues(alpha: 0.2);
    final Color activeBorderColor = Colors.white.withValues(alpha: 0.35);
    final Color profileCardBg = Colors.white.withValues(alpha: 0.1);
    final Color dividerColor = Colors.white.withValues(alpha: 0.15);

    // Header section: Clicking Growmont logo toggles collapse/expand
    final Widget topSection = effectiveCompact
        ? Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor)),
            ),
            child: Tooltip(
              message: 'Expand sidebar',
              waitDuration: const Duration(milliseconds: 200),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _toggle(ref),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: brandGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.trending_up_rounded,
                      color: brandGreen,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          )
        : Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: dividerColor)),
            ),
            child: Tooltip(
              message: 'Collapse sidebar',
              waitDuration: const Duration(milliseconds: 200),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _toggle(ref),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: brandGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.trending_up_rounded,
                          color: brandGreen,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Growmont',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: brandGreen,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

    // Profile section at bottom: Clicking avatar/info opens profile, explicit logout icon button
    final bool isProfileActive = location.startsWith('/profile');

    final Widget profileCard = effectiveCompact
        ? Padding(
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
                Tooltip(
                  message: 'Profile ($userName)',
                  waitDuration: const Duration(milliseconds: 150),
                  preferBelow: false,
                  margin: const EdgeInsets.only(left: 50),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: isProfileActive ? activeBgColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isProfileActive
                            ? activeBorderColor
                            : Colors.transparent,
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
                          height: 44,
                          child: Center(
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
                                    color: const Color(
                                      0xFF4ADE80,
                                    ), // Online green dot
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
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
                Tooltip(
                  message: 'Logout',
                  waitDuration: const Duration(milliseconds: 200),
                  child: IconButton(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/');
                      onNavigate?.call();
                    },
                  ),
                ),
              ],
            ),
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: isProfileActive ? activeBgColor : profileCardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isProfileActive
                    ? activeBorderColor
                    : dividerColor,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        context.go('/profile');
                        onNavigate?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF6366F1),
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
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
                                      color: const Color(
                                        0xFF4ADE80,
                                      ), // Online green dot
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: profileCardBg,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Logout',
                  waitDuration: const Duration(milliseconds: 200),
                  child: IconButton(
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) context.go('/');
                      onNavigate?.call();
                    },
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
                  padding: effectiveCompact
                      ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
                      : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  children: items.map((item) {
                    final isActive =
                        location == item.path ||
                        (item.path != '/dashboard' &&
                            location.startsWith(item.path));
                    return _buildNavItem(
                      context: context,
                      item: item,
                      isActive: isActive,
                      isCompact: effectiveCompact,
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
  }

  Widget _buildNavItem({
    required BuildContext context,
    required _MenuItem item,
    required bool isActive,
    required bool isCompact,
    required Color activeColor,
    required Color inactiveColor,
    required Color activeBg,
    required Color activeBorderColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Tooltip(
          message: item.label,
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
                  child: Center(
                    child: Icon(
                      item.icon,
                      color: isActive ? activeColor : inactiveColor,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 3.5,
                    height: isActive ? 18 : 0,
                    margin: EdgeInsets.only(right: isActive ? 8 : 0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4ADE80), // brandGreen
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Icon(
                    item.icon,
                    color: isActive ? activeColor : inactiveColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily:
                            Theme.of(context).textTheme.bodyMedium?.fontFamily,
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
                ],
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
