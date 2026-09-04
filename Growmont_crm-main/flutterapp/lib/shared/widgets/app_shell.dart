import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_provider.dart';
import 'app_sidebar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            AppSidebar(isCompact: false, onNavigate: () {}),
            Expanded(
              child: Column(
                children: [
                  _DesktopNavbar(userName: user?.name ?? 'User', initials: user?.initials ?? 'U'),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Image.asset('assets/logo.svg', height: 32, errorBuilder: (_, __, ___) {
          return const Text('Growmont', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D8A4E)));
        }),
        actions: [
          IconButton(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF6366F1),
              child: Text(
                user?.initials ?? 'U',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      drawer: Drawer(
        child: AppSidebar(
          isCompact: true,
          onNavigate: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
      ),
      body: widget.child,
    );
  }
}

class _DesktopNavbar extends StatelessWidget {
  const _DesktopNavbar({required this.userName, required this.initials});

  final String userName;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          InkWell(
            onTap: () => context.push('/profile'),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF6366F1),
                    child: Text(initials, style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  Text(userName, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
