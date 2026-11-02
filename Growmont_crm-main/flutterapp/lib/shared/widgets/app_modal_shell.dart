import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The standard Growmont dialog: a centered card with a fixed header, a
/// scrolling body and an optional fixed footer.
///
/// Every add/edit modal in the app used to hand-roll this exact shell, which
/// meant the mobile sizing had to be fixed in six places and drifted. Sizing is
/// driven by [AppLayout.modalInset] and [AppLayout.modalPaddingFor] so phones
/// get a tighter inset and body padding than desktop. Every form uses the
/// default width so they all open at the same size.
///
/// The title is [Expanded] rather than followed by a `Spacer()` so a long title
/// — or a large system font scale — ellipsizes instead of overflowing the row.
class AppModalShell extends StatelessWidget {
  /// Shown in the header row. Ellipsizes after two lines.
  final String title;

  /// One or two lines under the title explaining what the form does.
  final String? subtitle;

  /// Body of the modal, rendered below the header inside the scroll view.
  final Widget child;

  /// Pinned below the body, outside the scroll view, so the primary action
  /// is always visible - normally an [AppFormActions].
  final Widget? footer;

  final VoidCallback? onClose;

  /// Custom max width constraint, defaults to [AppSizing.modalMaxWidth] (560).
  /// Forms should leave this alone; it exists for read-only detail views.
  final double? maxWidth;

  /// Optional widgets shown before the close button in the header.
  final Widget? headerTrailing;

  const AppModalShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onClose,
    this.maxWidth,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final pad = AppLayout.modalPaddingFor(context).left;
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: AppLayout.modalInset(context),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? AppSizing.modalMaxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                pad - AppSpacing.xs,
                pad - AppSpacing.sm,
                AppSpacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTypography.sectionTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              subtitle!,
                              style: AppTypography.sectionSubtitle,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ?headerTrailing,
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose ?? () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(pad),
                child: child,
              ),
            ),
            if (footer != null) ...[
              const Divider(),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: pad,
                  vertical: AppSpacing.lg,
                ),
                child: footer,
              ),
            ],
          ],
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
