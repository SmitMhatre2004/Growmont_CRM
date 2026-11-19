import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// The branches that sit in the phone swipe row, in bottom-nav order, and the
/// root path of each. "More" is a sheet and is not part of the row.
const List<String> kSwipeRootPaths = [
  '/dashboard',
  '/sales',
  '/interactions',
  '/clients',
];

/// How far, as a share of a page's width, the person must keep dragging past
/// the last page (Clients) before the More sheet opens.
const double kMoreSwipeThreshold = 0.20;

/// Lets the phone shell hand the pager a way to open its "More" sheet, so a
/// swipe past Clients can open it without the pager knowing about the shell.
class MoreSheetScope extends InheritedWidget {
  const MoreSheetScope({super.key, required this.open, required super.child});

  /// Opens the More sheet. Does not change the selected tab or the route.
  final VoidCallback open;

  static MoreSheetScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MoreSheetScope>();

  @override
  bool updateShouldNotify(MoreSheetScope old) => open != old.open;
}

/// The `navigatorContainerBuilder` of the app's [StatefulShellRoute].
///
/// On a phone the first four branches live in a [PageView] so they can be
/// swiped like Instagram or WhatsApp; every other branch (Attendance, Reports,
/// Profile...) is shown on its own, outside the swipe row. On a PC or tablet
/// layout it is the plain stack of branches it always was.
Widget buildBranchContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) => BranchContainer(navigationShell: navigationShell, children: children);

class BranchContainer extends StatelessWidget {
  const BranchContainer({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!AppLayout.isMobile(context)) {
      // Unchanged: every branch built once, only the current one shown.
      final current = navigationShell.currentIndex;
      return Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < children.length; i++)
            Offstage(
              offstage: i != current,
              child: TickerMode(enabled: i == current, child: children[i]),
            ),
        ],
      );
    }
    return PhoneBranchPager(navigationShell: navigationShell, children: children);
  }
}

/// Lets a widget that handles its own horizontal drags tell the pager not to
/// treat a drag that starts on it as a page swipe. Most widgets do not need
/// this: a scrollable, slider or chart with its own horizontal drag wins the
/// gesture over the pager automatically.
class PageSwipeGuard extends StatefulWidget {
  const PageSwipeGuard({super.key, required this.child});

  final Widget child;

  @override
  State<PageSwipeGuard> createState() => _PageSwipeGuardState();
}

class _PageSwipeGuardState extends State<PageSwipeGuard> {
  final _down = <int>{};
  ValueNotifier<int>? _lock;

  void _release() {
    final lock = _lock;
    if (lock != null && _down.isNotEmpty) {
      lock.value = (lock.value - _down.length).clamp(0, 1 << 20);
    }
    _down.clear();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _lock = _PageSwipeLockScope.maybeOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (_down.add(e.pointer)) _lock?.value += 1;
      },
      onPointerUp: (e) {
        if (_down.remove(e.pointer)) _lock?.value -= 1;
      },
      onPointerCancel: (e) {
        if (_down.remove(e.pointer)) _lock?.value -= 1;
      },
      child: widget.child,
    );
  }
}

class _PageSwipeLockScope extends InheritedWidget {
  const _PageSwipeLockScope({required this.lock, required super.child});

  final ValueNotifier<int> lock;

  static ValueNotifier<int>? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_PageSwipeLockScope>()
      ?.lock;

  @override
  bool updateShouldNotify(_PageSwipeLockScope old) => lock != old.lock;
}

/// Phone: the swipe row in a PageView, the other branches behind it.
class PhoneBranchPager extends StatefulWidget {
  const PhoneBranchPager({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  State<PhoneBranchPager> createState() => _PhoneBranchPagerState();
}

class _PhoneBranchPagerState extends State<PhoneBranchPager>
    with SingleTickerProviderStateMixin {
  /// The pager's sideways nudge in px while the person drags past Clients.
  /// Springs back to 0 when the finger lifts.
  late final AnimationController _nudge = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// Forward overscroll accumulated by the current drag past the last page.
  double _pull = 0;

  /// True once this drag has opened More, so one gesture opens it once.
  bool _opened = false;

  late int _page = _rowIndexOf(widget.navigationShell.currentIndex) ?? 0;
  late final PageController _controller = PageController(initialPage: _page);
  final ValueNotifier<int> _lock = ValueNotifier<int>(0);

  /// True while we move the PageView ourselves (a nav-bar tap), so the page
  /// callbacks it fires on the way are not mistaken for a swipe.
  bool _programmatic = false;

  static int? _rowIndexOf(int branch) =>
      branch >= 0 && branch < kSwipeRootPaths.length ? branch : null;

  @override
  void dispose() {
    _nudge.dispose();
    _controller.dispose();
    _lock.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PhoneBranchPager old) {
    super.didUpdateWidget(old);
    final target = _rowIndexOf(widget.navigationShell.currentIndex);
    if (target == null || target == _page) return;
    // The router moved to another page of the row (nav-bar tap, deep link,
    // back button): follow it.
    final wasHidden = _rowIndexOf(old.navigationShell.currentIndex) == null;
    final far = (target - _page).abs() > 1;
    _page = target;
    if (!_controller.hasClients) return;
    if (wasHidden || far) {
      _programmatic = false;
      _controller.jumpToPage(target);
    } else {
      _programmatic = true;
      _controller
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _programmatic = false);
    }
  }

  /// A pushed page (client detail) belongs to its own branch: no swiping.
  bool _atRoot() {
    final current = widget.navigationShell.currentIndex;
    final root = _rowIndexOf(current);
    if (root == null) return false;
    final path = widget.navigationShell.shellRouteContext.routerState.uri.path;
    final normalised = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return normalised == kSwipeRootPaths[root];
  }

  bool get _onLastPage =>
      widget.navigationShell.currentIndex == kSwipeRootPaths.length - 1 &&
      _atRoot();

  /// Watches the pager for a drag past Clients. Only the pager's own
  /// horizontal scroll counts (an inner list or chart is deeper than 0), and
  /// only a finger drag, never the tail of a fling.
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
    if (n is ScrollStartNotification) {
      _pull = 0;
      _opened = false;
      _nudge.stop();
    } else if (n is OverscrollNotification) {
      if (n.dragDetails == null || n.overscroll <= 0 || !_onLastPage) {
        return false;
      }
      _pull += n.overscroll;
      _nudge.value = _rubberBand(_pull);
      final width = n.metrics.viewportDimension;
      if (!_opened && width > 0 && _pull >= width * kMoreSwipeThreshold) {
        _opened = true;
        HapticFeedback.mediumImpact();
        MoreSheetScope.maybeOf(context)?.open();
      }
    } else if (n is ScrollUpdateNotification) {
      // Dragging back the other way lowers the pull again.
      final delta = n.scrollDelta ?? 0;
      if (_pull > 0 && delta < 0) {
        _pull = math.max(0, _pull + delta);
        _nudge.value = _rubberBand(_pull);
      }
    } else if (n is ScrollEndNotification) {
      _pull = 0;
      if (_nudge.value != 0) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _nudge.value = 0;
        } else {
          _nudge.animateTo(
            0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
    return false;
  }

  /// A drag past the end moves the page by a diminishing amount.
  static double _rubberBand(double pull) => 56 * (1 - math.exp(-pull / 160));

  void _onPageChanged(int page) {
    if (_programmatic) return;
    _page = page;
    if (page != widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    final current = shell.currentIndex;
    final inRow = _rowIndexOf(current) != null;
    final canSwipe = _atRoot();
    final rowCount = kSwipeRootPaths.length.clamp(0, widget.children.length);

    final pager = _PageSwipeLockScope(
      lock: _lock,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AnimatedBuilder(
          animation: _nudge,
          builder: (context, child) => Transform.translate(
            offset: Offset(-_nudge.value, 0),
            child: child,
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: _lock,
            builder: (context, locks, _) => PageView(
              key: const ValueKey('branch-pager'),
              controller: _controller,
              onPageChanged: _onPageChanged,
              physics: canSwipe && locks == 0
                  ? const PageScrollPhysics(parent: ClampingScrollPhysics())
                  : const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < rowCount; i++)
                  _KeepAlive(
                    child: _PageTickerMode(
                      controller: _controller,
                      index: i,
                      initialPage: _page,
                      enabled: inRow,
                      child: widget.children[i],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: !inRow, child: pager),
        for (var i = rowCount; i < widget.children.length; i++)
          Offstage(
            offstage: i != current,
            child: TickerMode(enabled: i == current, child: widget.children[i]),
          ),
      ],
    );
  }
}

/// Ticks (animations, tickers) only while any part of page [index] is on
/// screen. Kept-alive pages that are swiped out of view stay mounted, but a
/// spinning ring or running chart animation on one of them would otherwise
/// keep scheduling frames nobody sees. During a swipe both pages involved
/// tick, so nothing visible pauses.
class _PageTickerMode extends StatelessWidget {
  const _PageTickerMode({
    required this.controller,
    required this.index,
    required this.initialPage,
    required this.enabled,
    required this.child,
  });

  final PageController controller;
  final int index;
  final int initialPage;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        var page = initialPage.toDouble();
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? page;
        }
        return TickerMode(
          enabled: enabled && (page - index).abs() < 1,
          child: child!,
        );
      },
    );
  }
}

/// Keeps a page's navigator, and with it its state and scroll position, alive
/// while it is swiped out of view.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
