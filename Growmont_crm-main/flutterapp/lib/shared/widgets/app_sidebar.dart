import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/auth_provider.dart';

class AppSidebar extends ConsumerWidget {
  const AppSidebar({
    super.key,
    required this.isCompact,
    required this.onNavigate,
  });

  final bool isCompact;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final location = GoRouterState.of(context).matchedLocation;

    final items = <_MenuItem>[
      _MenuItem('dashboard', 'Dashboard', Icons.dashboard_outlined, '/dashboard'),
      _MenuItem('sales', 'Sales', Icons.bar_chart_outlined, '/sales'),
      _MenuItem('interactions', 'Interactions', Icons.chat_bubble_outline, '/interactions'),
      if (user?.isAdmin == true)
        _MenuItem('employees', 'Employees', Icons.people_outline, '/employees'),
      if (user?.isAdmin == true)
        _MenuItem('info-portal', 'Info Portal', Icons.inventory_2_outlined, '/info-portal'),
    ];

    final sidebar = Container(
      width: isCompact ? null : 256,
      color: Colors.white,
      child: Column(
        children: [
          if (!isCompact)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Image.asset(
                'assets/logo.svg',
                height: 40,
                errorBuilder: (_, __, ___) => const Text(
                  'Growmont',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: items.map((item) {
                final isActive = location == item.path ||
                    (item.path != '/dashboard' && location.startsWith(item.path));
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: isActive ? AppColors.primaryBlue : AppColors.sidebarText,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isActive ? AppColors.primaryBlue : AppColors.sidebarText,
                    ),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  tileColor: isActive ? AppColors.primaryBlue.withValues(alpha: 0.11) : null,
                  onTap: () {
                    context.go(item.path);
                    onNavigate();
                  },
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/');
              onNavigate();
            },
          ),
        ],
      ),
    );

    if (isCompact) {
      return SafeArea(child: sidebar);
    }

    return sidebar;
  }
}

class _MenuItem {
  const _MenuItem(this.id, this.label, this.icon, this.path);
  final String id;
  final String label;
  final IconData icon;
  final String path;
}
