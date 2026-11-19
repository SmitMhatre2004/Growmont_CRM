import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_provider.dart';
import 'approvals_tab.dart';
import 'attendance_providers.dart';
import 'holidays_tab.dart';
import 'settings_tab.dart';
import 'team_tab.dart';
import 'today_tab.dart';

/// /attendance. Everyone gets "Today"; admins get four more tabs on the same
/// screen.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen>
    with TickerProviderStateMixin {
  TabController? _controller;
  int _tabCount = 0;

  TabController _controllerFor(int count) {
    if (_controller == null || _tabCount != count) {
      final previous = _controller?.index ?? 0;
      _controller?.dispose();
      _tabCount = count;
      _controller = TabController(
        length: count,
        vsync: this,
        initialIndex: previous < count ? previous : 0,
      );
    }
    return _controller!;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.isAdmin == true;
    final isMobile = AppLayout.isMobile(context);
    final pad = isMobile ? AppSpacing.lg : AppSpacing.xxl;

    final tabs = <_TabSpec>[
      const _TabSpec('Today', AttendanceTodayTab()),
      if (isAdmin) ...[
        const _TabSpec('Team', AttendanceTeamTab()),
        _TabSpec('Approvals', const AttendanceApprovalsTab(), badge: true),
        const _TabSpec('Holidays', AttendanceHolidaysTab()),
        const _TabSpec('Settings', AttendanceSettingsTab()),
      ],
    ];
    final controller = _controllerFor(tabs.length);
    final pending = isAdmin
        ? ref.watch(attendanceApprovalsProvider).valueOrNull?.total ?? 0
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, isMobile ? 10 : 16, pad, 8),
          child: Text(
            'Attendance',
            style: isMobile
                ? AppTypography.pageTitleMobile
                : AppTypography.pageTitle,
          ),
        ),
        if (tabs.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final t in tabs)
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.label),
                        if (t.badge && pending > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Badge(label: Text('$pending')),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [for (final t in tabs) t.body],
          ),
        ),
      ],
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.body, {this.badge = false});

  final String label;
  final Widget body;
  final bool badge;
}
