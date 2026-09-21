// lib/core/updater/update_prompt.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'update_dialog.dart';
import 'update_notifier.dart';

/// Raises [UpdateDialog] on its own when the launch-time check in main.dart
/// finds a newer release, so the user no longer has to go looking for the
/// Profile -> System card to learn one exists.
///
/// Sits in MaterialApp's `builder`, which is above the router's Navigator,
/// so the dialog is shown through [navigatorKey] rather than this widget's
/// own context.
class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({
    super.key,
    required this.navigatorKey,
    required this.enabled,
    required this.deferWhile,
    required this.child,
  });

  /// The router's navigator. Passed on every build rather than captured
  /// once, because the router is recreated whenever auth state changes.
  final GlobalKey<NavigatorState> navigatorKey;

  /// False while the app has no navigator to show a dialog on yet (auth
  /// still resolving).
  final bool enabled;

  /// The prompt waits while this is true — the splash. A dialog opened
  /// under the splash would sit on the pre-redirect route and be torn down
  /// with it the moment routing settles.
  final ValueListenable<bool> deferWhile;

  final Widget child;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  // Once per launch, not once per check, and static so it survives this
  // state being recreated. The Profile card's Check button drives the same
  // notifier; re-raising the dialog each time it finds the update the user
  // just put off with "Later" would be nagging.
  static bool _prompted = false;

  late final Listenable _triggers =
      Listenable.merge([UpdateNotifier.instance, widget.deferWhile]);

  @override
  void initState() {
    super.initState();
    _triggers.addListener(_maybePrompt);
    _maybePrompt();
  }

  @override
  void didUpdateWidget(covariant UpdatePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybePrompt();
  }

  @override
  void dispose() {
    _triggers.removeListener(_maybePrompt);
    super.dispose();
  }

  void _maybePrompt() {
    if (_prompted || !widget.enabled || widget.deferWhile.value) return;

    final notifier = UpdateNotifier.instance;
    // Idle only: a check still running has no answer yet, and a download
    // already under way means the user found the update themselves.
    if (!notifier.hasUpdate || notifier.state != UpdateState.idle) return;

    _prompted = true;
    // Deferred a frame: this can be reached from a listener firing during
    // build, where pushing a route is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigatorContext = widget.navigatorKey.currentContext;
      if (!mounted || navigatorContext == null) {
        // No navigator yet — let the next trigger try again.
        _prompted = false;
        return;
      }
      UpdateDialog.show(navigatorContext);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
