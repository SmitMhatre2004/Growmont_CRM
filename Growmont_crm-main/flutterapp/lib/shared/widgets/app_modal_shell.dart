import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The standard Growmont dialog: a centered, scrollable card with a title row
/// and a close button.
///
/// Every add/edit modal in the app used to hand-roll this exact shell, which
/// meant the mobile sizing had to be fixed in six places and drifted. Sizing is
/// driven by [AppLayout.modalInset] and [AppLayout.modalPaddingFor] so phones
/// get a tighter inset and body padding than desktop.
///
/// The title is [Expanded] rather than followed by a `Spacer()` so a long title
/// — or a large system font scale — ellipsizes instead of overflowing the row.
class AppModalShell extends StatelessWidget {
  const AppModalShell({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
  });

  /// Shown in the header row. Ellipsizes after two lines.
  final String title;

  /// Body of the modal, rendered below the header inside the scroll view.
  final Widget child;

  /// Defaults to popping the current route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: AppLayout.modalInset(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.modalMaxWidth),
        child: SingleChildScrollView(
          padding: AppLayout.modalPaddingFor(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.sectionTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: onClose ?? () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays two form fields out side by side on wide screens and stacked on phones.
///
/// Two `Expanded` fields inside a modal on a 360pt screen get ~126pt each,
/// which is too narrow for a dropdown or a labelled input.
Widget modalFieldPair(BuildContext context, Widget first, Widget second) {
  if (AppLayout.isMobile(context)) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        first,
        const SizedBox(height: AppSpacing.lg),
        second,
      ],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: second),
    ],
  );
}
