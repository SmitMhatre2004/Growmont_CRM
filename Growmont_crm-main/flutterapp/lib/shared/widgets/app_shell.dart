import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'app_sidebar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final isSidebarCollapsed = ref.watch(sidebarCollapsedProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 768;

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
                      right: BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                  ),
                  child: AppSidebar(
                    isCompact: isSidebarCollapsed,
                    onNavigate: () {},
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 30, right: 16),
                    child: ClipRect(child: widget.navigationShell),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Image.asset(
            'assets/images/growmont-logo_coloured-large-size.webp',
            fit: BoxFit.contain,
          ),
        ),
      ),
      drawer: Drawer(
        child: AppSidebar(
          isCompact: false,
          onNavigate: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
      ),
      body: widget.navigationShell,
    );
  }
}

