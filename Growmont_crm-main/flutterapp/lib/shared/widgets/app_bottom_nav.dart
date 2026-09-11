import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One destination in the phone bottom bar.
class BottomNavItem {
  const BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.branchIndex,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Index of the matching [StatefulShellBranch], or -1 for the "More" entry,
  /// which opens a sheet instead of switching branches.
  final int branchIndex;

  static const int moreBranch = -1;
}

/// Bottom navigation for phones, replacing the drawer.
///
/// Uses the same dark green as the desktop sidebar ([AppColors.sidebarBg]) so
/// the two navigation surfaces read as the same component, and caps itself at
/// five destinations — anything past that lives behind "More".
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentBranch,
    required this.onSelect,
    required this.onMore,
  });

  final List<BottomNavItem> items;

  /// Currently active shell branch. When it belongs to a destination behind
  /// "More", that entry is shown as selected.
  final int currentBranch;
  final ValueChanged<int> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final selected = items.indexWhere((i) => i.branchIndex == currentBranch);
    final hasMore = items.any(
      (i) => i.branchIndex == BottomNavItem.moreBranch,
    );
    // A branch not in the bar (Employees, Info Portal) is reached through
    // "More", so highlight that; Profile lives in the app bar and highlights
    // nothing.
    final effective = selected >= 0
        ? selected
        : (hasMore && currentBranch >= 0 ? items.length - 1 : -1);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        boxShadow: AppShadows.md,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavCell(
                    item: items[i],
                    isSelected: i == effective,
                    onTap: () {
                      if (items[i].branchIndex == BottomNavItem.moreBranch) {
                        onMore();
                      } else {
                        onSelect(items[i].branchIndex);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.white : Colors.white70;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Icon(
                  isSelected ? item.activeIcon : item.icon,
                  size: AppSizing.iconLg,
                  color: color,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              // Labels are short by construction, but a large system font scale can
              // still push them wide, so they ellipsize rather than overflow.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
