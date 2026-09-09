import 'package:flutter/material.dart';

/// -----------------------------------------------------------------------------
/// GROWMONT DESIGN TOKENS
/// -----------------------------------------------------------------------------
/// Single source of truth for spacing, radius, sizing and elevation.
///
/// Rules of the system:
///  * Spacing follows a strict 4pt grid. Never use a raw number in a widget.
///  * Radius is deliberately restrained: controls 8, cards 10, modals 12.
///    Nothing is a pill except avatars. This keeps the product feeling like
///    software, not a toy.
///  * Every interactive control snaps to one of three heights so buttons,
///    inputs and dropdowns always line up on the same baseline.
/// -----------------------------------------------------------------------------

/// 4pt spacing scale. Use these instead of literal paddings/gaps.
class AppSpacing {
  AppSpacing._();

  /// 2 - hairline separation inside a badge
  static const double xxs = 2;

  /// 4 - icon-to-label, tight inline gaps
  static const double xs = 4;

  /// 8 - default gap between related elements
  static const double sm = 8;

  /// 12 - gap between rows, compact card padding
  static const double md = 12;

  /// 16 - default card padding, standard block gap
  static const double lg = 16;

  /// 20 - generous card padding
  static const double xl = 20;

  /// 24 - page gutter (desktop), section separation
  static const double xxl = 24;

  /// 32 - major section separation
  static const double xxxl = 32;

  /// 48 - empty-state / hero breathing room
  static const double huge = 48;
}

/// Corner radii. Intentionally shallow and few.
class AppRadius {
  AppRadius._();

  /// 4 - swatches, progress bars, the smallest tags
  static const double xs = 4;

  /// 6 - badges, status pills, chips
  static const double sm = 6;

  /// 8 - buttons, inputs, dropdowns, every interactive control
  static const double md = 8;

  /// 10 - cards, panels, table containers
  static const double lg = 10;

  /// 12 - modals, dialogs, bottom sheets
  static const double xl = 12;

  /// Circular - avatars only.
  static const double full = 999;

  // Prebuilt BorderRadius values so call sites stay short.
  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));

  /// Rounds only the top corners - for modal/sheet headers and table headers.
  static const BorderRadius topLg = BorderRadius.only(
    topLeft: Radius.circular(lg),
    topRight: Radius.circular(lg),
  );
  static const BorderRadius bottomLg = BorderRadius.only(
    bottomLeft: Radius.circular(lg),
    bottomRight: Radius.circular(lg),
  );
}

/// Fixed heights for interactive controls. Buttons, inputs and dropdowns must
/// pick one of these so a toolbar row is always visually flush.
class AppSizing {
  AppSizing._();

  /// 32 - dense controls: table row actions, dialog footers, filter chips
  static const double controlSm = 32;

  /// 40 - THE default: toolbar buttons, search fields, dropdowns
  static const double controlMd = 40;

  /// 48 - full-width primary actions (login, mobile CTAs)
  static const double controlLg = 48;

  /// Minimum tap target on touch devices.
  static const double minTapTarget = 44;

  // Icon sizes
  /// 14 - inline with caption text
  static const double iconXs = 14;

  /// 16 - inside compact buttons and list rows
  static const double iconSm = 16;

  /// 18 - default button / toolbar icon
  static const double iconMd = 18;

  /// 20 - navigation and app bar
  static const double iconLg = 20;

  /// 24 - feature/section icons
  static const double iconXl = 24;

  /// 32 - decorative glyph inside a card or avatar placeholder
  static const double iconDisplay = 32;

  /// 48 - empty-state illustration glyph
  static const double iconEmptyState = 48;

  /// 96 - hero/brand artwork glyph (login split panel)
  static const double iconHero = 96;

  // Avatars
  static const double avatarSm = 32;
  static const double avatarMd = 40;
  static const double avatarLg = 56;
  static const double avatarXl = 96;

  // Layout
  static const double sidebarWidth = 260;
  static const double sidebarCollapsedWidth = 72;
  static const double modalMaxWidth = 560;
  static const double contentMaxWidth = 1400;
  static const double borderWidth = 1;
  static const double borderWidthFocus = 2;
}

/// Page gutters that adapt to breakpoint. Use [AppLayout.pagePadding].
class AppLayout {
  AppLayout._();

  /// Below this width the UI switches to its compact/mobile arrangement.
  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1100;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= mobileBreakpoint && w < tabletBreakpoint;
  }

  /// Horizontal gutter for a screen's scrollable body.
  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.symmetric(
    horizontal: isMobile(context) ? AppSpacing.lg : AppSpacing.xxl,
    vertical: isMobile(context) ? AppSpacing.lg : AppSpacing.xl,
  );

  /// Padding inside a standard card.
  static const EdgeInsets cardPadding = EdgeInsets.all(AppSpacing.lg);

  /// Padding inside a dense card (tables, list panels).
  static const EdgeInsets cardPaddingCompact = EdgeInsets.all(AppSpacing.md);

  /// Padding for a table/list row.
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );

  /// Padding for a table header cell.
  static const EdgeInsets tableHeaderPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );

  /// Padding for badges/status pills.
  static const EdgeInsets badgePadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.sm,
    vertical: AppSpacing.xxs,
  );

  /// Padding inside a modal body.
  static const EdgeInsets modalPadding = EdgeInsets.all(AppSpacing.xxl);
}

/// The single shadow vocabulary. Cards are flat + bordered by default; shadows
/// are reserved for things that genuinely float.
class AppShadows {
  AppShadows._();

  /// Resting card lift - barely there, use with a border.
  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Raised panel / hovered card.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// Dropdown, popover, menu.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x141E293B), blurRadius: 16, offset: Offset(0, 6)),
  ];

  /// Modal / dialog.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1F0F172A), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

/// Motion. Consistent, quick, never showy.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
}
