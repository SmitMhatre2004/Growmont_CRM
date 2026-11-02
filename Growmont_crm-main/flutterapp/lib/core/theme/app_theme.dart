import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// -----------------------------------------------------------------------------
/// COLOR
/// -----------------------------------------------------------------------------
/// Two brand colours with fixed jobs, quiet slate neutrals, and status colour
/// that only ever means something.
///
///   * Navy acts.   Buttons, links, focus, selection. Never a money figure.
///   * Green grows. Navigation, logo, money, growth, "won". Never a primary
///     button.
///   * Slate carries the interface. Colour appears only when it tells the user
///     something: an action, a state, or money.
///
/// One light theme, one set of tokens, used by every screen on desktop and
/// phone. Red is reserved for overdue, errors and delete - never emphasis.
/// Text tops out at [AppColors.textPrimary]; there is no pure black.

/// The two brand ramps, 50 -> 900.
///
/// Screens use the semantic names in [AppColors], [AppStatus] and [AppChart].
/// Reach into a ramp step directly only when defining a new token here.
class AppPalette {
  AppPalette._();

  // --------------------------------------------------------- GROWMONT NAVY --
  // Identity - action. 700 is the brand navy: 11.9:1 on white.
  /// Selected row, info tint.
  static const navy50 = Color(0xFFEFF4FB);

  /// Hover on a selected row.
  static const navy100 = Color(0xFFDCE6F5);

  /// Border on a navy-tinted surface.
  static const navy200 = Color(0xFFB8CCEB);
  static const navy300 = Color(0xFF86A7DA);

  /// Focus ring, chart series 3.
  static const navy400 = Color(0xFF4F7DC3);
  static const navy500 = Color(0xFF2458A8);
  static const navy600 = Color(0xFF0F4491);

  /// THE brand navy. Primary button, links, focus border, chart series 1.
  static const navy700 = Color(0xFF00337C);

  /// Primary button hover.
  static const navy800 = Color(0xFF002866);

  /// Primary button pressed.
  static const navy900 = Color(0xFF001C4A);

  // -------------------------------------------------------- GROWMONT GREEN --
  // Identity - growth. 500 is the brand green.
  /// Positive tint, the "won" pill.
  static const green50 = Color(0xFFECFDF3);
  static const green100 = Color(0xFFD3F3DF);

  /// Border on a green-tinted surface.
  static const green200 = Color(0xFFA8E3BE);

  /// Active item on navigation, chart series 4.
  static const green300 = Color(0xFF72CB93);
  static const green400 = Color(0xFF45AD6D);

  /// THE brand green. Logo, charts, icons, chart series 2.
  static const green500 = Color(0xFF2D8A4E);

  /// Money as text - 6.2:1 on white.
  static const green600 = Color(0xFF246E3F);
  static const green700 = Color(0xFF185A38);

  /// Sidebar and bottom bar.
  static const green800 = Color(0xFF0F4A31);

  /// Sidebar gradient end.
  static const green900 = Color(0xFF092E1E);

  // ----------------------------------------------------------------- SLATE --
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  // ---------------------------------------------------------------- PURPLE --
  // The one hue outside the brand ramps: interactions only.
  static const purple = Color(0xFF9333EA);
  static const purpleText = Color(0xFF7E22CE);
  static const purpleTint = Color(0xFFFAF5FF);
}

class AppColors {
  AppColors._();

  // ----------------------------------------------------------------- BRAND --
  /// Navy 700. Primary buttons, links, focus, selection.
  static const primaryBlue = AppPalette.navy700;

  /// Navy 800 / 900 - primary button hover and pressed.
  static const primaryBlueHover = AppPalette.navy800;
  static const primaryBluePressed = AppPalette.navy900;

  /// Green 500. Logo, charts, icons.
  static const primaryGreen = AppPalette.green500;

  /// Green 600. Money as text, and the only green that carries a label.
  static const primaryGreenDark = AppPalette.green600;

  /// Green 50. Positive tint, the "won" pill.
  static const primaryGreenSoft = AppPalette.green50;

  /// Green 200. Border on a green-tinted surface.
  static const primaryGreenBorder = AppPalette.green200;

  /// Green 600. Money, totals, positive deltas. Never navy.
  static const money = AppPalette.green600;

  // ---------------------------------------------------------------- CHROME --
  static const background = AppPalette.slate100;

  /// Green 800 -> 900. Sidebar and bottom bar.
  static const sidebarBg = AppPalette.green800;
  static const sidebarBgDeep = AppPalette.green900;
  static const sidebarText = Color(0xFFFFFFFF);

  /// Green 300. The active destination in the sidebar and bottom bar.
  static const navActive = AppPalette.green300;

  // -------------------------------------------------------------- SURFACES --
  /// Cards, modals, app bar.
  static const surface = Color(0xFFFFFFFF);

  /// Table heads, modal footers.
  static const surfaceHeader = AppPalette.slate50;

  /// Row hover - the canvas colour, one step down from the surface.
  static const surfaceHover = AppPalette.slate100;

  /// Navy 50. Selected row (paired with a 3px navy rail) and info tint.
  static const surfaceSelected = AppPalette.navy50;

  /// Navy 100. Hover on an already-selected row.
  static const surfaceSelectedHover = AppPalette.navy100;
  static const surfaceSunken = AppPalette.slate50;

  // ------------------------------------------------------------------ TEXT --
  /// Titles and values. 17.9:1. The darkest text in the product.
  static const textPrimary = AppPalette.slate900;

  /// Body and subtitles. 7.6:1.
  static const textSecondary = AppPalette.slate600;

  /// Timestamps and helper text. 4.8:1. The lightest readable text.
  static const textCaption = AppPalette.slate500;

  /// Placeholder and disabled only - 2.6:1. If someone must read it, it is
  /// [textCaption] or darker.
  static const textMuted = AppPalette.slate400;
  static const textOnDark = Color(0xFFFFFFFF);

  /// Inline links and text actions.
  static const link = AppPalette.navy700;

  // ----------------------------------------------------------------- LINES --
  /// Card edges, inputs, dividers.
  static const border = AppPalette.slate200;

  /// Drag handles, disabled fill.
  static const borderStrong = AppPalette.slate300;
  static const divider = AppPalette.slate100;

  /// Navy 400 - the focus ring. The focus *border* is navy 700.
  static const focusRing = AppPalette.navy400;

  // ---------------------------------------------------------------- STATUS --
  // Flat aliases onto [AppStatus], for the many call sites that need only one
  // of the three tones. Status colour never decorates: each means one thing.
  /// Overdue, failed, destructive.
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEF2F2);

  /// Needs attention today; nothing is broken yet.
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFFF7ED);

  /// Sale closed, payment received, active client.
  static const success = AppPalette.green600;
  static const successSoft = AppPalette.green50;

  /// New lead, neutral notice, sync in progress.
  static const info = AppPalette.navy700;
  static const infoSoft = AppPalette.navy50;

  /// Priority: low. Yellow is a dot, never text - the word is [yellowText].
  static const yellow = Color(0xFFEAB308);
  static const yellowText = Color(0xFF854D0E);
  static const yellowSoft = Color(0xFFFEF9C3);

  /// Interactions only: calls, chats, meetings.
  static const chat = AppPalette.purple;
  static const chatText = AppPalette.purpleText;
  static const chatSoft = AppPalette.purpleTint;

  /// Archived, transferred, dismissed.
  static const neutral = AppPalette.slate500;
  static const neutralSoft = AppPalette.slate100;
}

/// A status is always three colours: a dot, the tint behind it, and the text on
/// top. Colour never works alone - a badge is always a dot plus a word.
@immutable
class StatusTone {
  const StatusTone({required this.dot, required this.tint, required this.text});

  /// The dot. The most saturated of the three.
  final Color dot;

  /// The pill background.
  final Color tint;

  /// The label, and the border when one is drawn.
  final Color text;
}

/// The seven states the product can be in. Nothing else earns colour.
class AppStatus {
  AppStatus._();

  /// Sale closed, payment received, active client.
  static const won = StatusTone(
    dot: AppPalette.green500,
    tint: AppPalette.green50,
    text: AppPalette.green600,
  );

  /// Needs attention today; nothing is broken yet.
  static const followUp = StatusTone(
    dot: Color(0xFFF59E0B),
    tint: Color(0xFFFFF7ED),
    text: Color(0xFFB45309),
  );

  /// Overdue, failed, destructive. Never decoration.
  static const overdue = StatusTone(
    dot: Color(0xFFEF4444),
    tint: Color(0xFFFEF2F2),
    text: Color(0xFFDC2626),
  );

  /// New lead, neutral notice, sync in progress.
  static const fresh = StatusTone(
    dot: AppPalette.navy500,
    tint: AppPalette.navy50,
    text: AppPalette.navy700,
  );

  /// Priority: low. The yellow is the dot; the word is brown.
  static const lowPriority = StatusTone(
    dot: Color(0xFFEAB308),
    tint: Color(0xFFFEF9C3),
    text: Color(0xFF854D0E),
  );

  /// Interactions only: calls, chats, meetings.
  static const chat = StatusTone(
    dot: AppPalette.purple,
    tint: AppPalette.purpleTint,
    text: AppPalette.purpleText,
  );

  /// Archived, transferred, dismissed.
  static const inactive = StatusTone(
    dot: AppPalette.slate500,
    tint: AppPalette.slate100,
    text: AppPalette.slate600,
  );
}

/// Chart series and avatar monograms.
class AppChart {
  AppChart._();

  /// Series order is fixed, so a measure keeps its colour across every chart.
  static const List<Color> series = [
    AppPalette.navy700,
    AppPalette.green500,
    AppPalette.navy400,
    AppPalette.green300,
    AppPalette.purple,
  ];

  /// Everything past the fifth series collapses into one grey.
  static const other = AppPalette.slate300;

  /// The colour for series [index], falling back to [other] past the fifth.
  static Color seriesAt(int index) =>
      index < series.length ? series[index] : other;

  /// Monogram ramps: a 100-shade fill under 700-shade initials.
  static const List<(Color fill, Color ink)> monograms = [
    (AppPalette.navy100, AppPalette.navy700),
    (AppPalette.green100, AppPalette.green700),
    (Color(0xFFEDE9FE), Color(0xFF6D28D9)),
    (Color(0xFFFEF3C7), Color(0xFF92400E)),
    (Color(0xFFE0F2FE), Color(0xFF075985)),
  ];

  /// A stable monogram pair for [name] - picked from the name, so a person
  /// keeps their colour everywhere they appear.
  static (Color fill, Color ink) monogramFor(String name) {
    final key = name.trim().toUpperCase();
    if (key.isEmpty) return monograms.first;
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return monograms[hash % monograms.length];
  }
}

/// -----------------------------------------------------------------------------
/// TYPOGRAPHY
/// -----------------------------------------------------------------------------
/// Pairing:
///   * Plus Jakarta Sans - display face. Geometric, a little characterful.
///     Used ONLY for page titles, section headings, card titles and KPI numbers.
///   * Inter - text face. Purpose-built for UI at small sizes with a tall
///     x-height. Used for everything else: body, labels, tables, buttons.
///
/// Scale (no half-points, ever):
///   11 - 12 - 13 - 14 - 15 - 16 - 18 - 22 - 24 - 28 - 32
///
/// Weight carries hierarchy, not size alone:
///   400 body - 500 emphasis - 600 titles/labels - 700 headings
///
/// Numerals in tables, money and metrics use tabular figures so columns of
/// digits align on the decimal.
class AppTypography {
  AppTypography._();

  static const String display = 'PlusJakartaSans';
  static const String text = 'Inter';

  /// Fixed-width digits. Attach to anything numeric that stacks in a column.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ---------------------------------------------------------------- DISPLAY --
  /// 32/38 700 - page title, desktop
  static const TextStyle pageTitle = TextStyle(
    fontFamily: display,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 38 / 32,
  );

  /// 24/30 700 - page title, phone. The scale steps down exactly once.
  static const TextStyle pageTitleMobile = TextStyle(
    fontFamily: display,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 30 / 24,
  );

  /// 22/29 700 - major heading inside a page
  static const TextStyle headingLarge = TextStyle(
    fontFamily: display,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 29 / 22,
  );

  /// 20/26 700 - major heading, phone
  static const TextStyle headingLargeMobile = TextStyle(
    fontFamily: display,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 26 / 20,
  );

  /// 18/23 700 - section heading (Clients, Sales, Reminders). Same on phone.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: display,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 23 / 18,
  );

  /// 16/22 600 - card & modal title
  static const TextStyle cardTitle = TextStyle(
    fontFamily: display,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 22 / 16,
  );

  // ------------------------------------------------------------------- TEXT --
  /// 14/400 - page subtitle / section description
  static const TextStyle pageSubtitle = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  /// 13/400 - section subtitle
  static const TextStyle sectionSubtitle = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  /// 15/20 600 - list item title, client name, row subject
  static const TextStyle itemTitle = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 20 / 15,
  );

  /// 13/19 400 - list item subtitle, contact info, secondary attributes
  static const TextStyle itemSubtitle = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 19 / 13,
  );

  /// 14/20 500 - primary body copy
  static const TextStyle bodyPrimary = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 20 / 14,
  );

  /// 13/19 400 - secondary body copy, descriptions
  static const TextStyle bodySecondary = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 19 / 13,
  );

  /// 14/500 - the value half of a label/value pair
  static const TextStyle fieldValue = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 12/16 600 - the label half of a label/value pair, and form field labels.
  /// A label sits above its input, never floating inside it.
  static const TextStyle fieldLabel = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  /// 14/600 - button text. One size for every standard button in the app.
  static const TextStyle button = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.2,
  );

  /// 13/600 - compact (32h) button text
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.2,
  );

  /// 14/400 - text typed into an input
  static const TextStyle input = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // ------------------------------------------------------------- SMALL TEXT --
  /// 12/16 400 - captions, timestamps, helper text. Caption grey, never
  /// muted: muted is for placeholders and disabled text only.
  static const TextStyle caption = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textCaption,
    height: 16 / 12,
  );

  /// 12/16 600 - emphasised caption
  static const TextStyle captionSemibold = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 16 / 12,
  );

  /// 11/14 700 +0.6 - overline. The one role that is not sentence case: pair
  /// it with .toUpperCase().
  static const TextStyle overline = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textCaption,
    letterSpacing: 0.6,
    height: 14 / 11,
  );

  /// 11/14 700 +0.6 - table column header: an overline on a header surface.
  /// Pair with .toUpperCase().
  static const TextStyle tableHeader = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textCaption,
    letterSpacing: 0.6,
    height: 14 / 11,
  );

  /// 13/400 - a cell of text in a data table
  static const TextStyle tableCell = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.35,
  );

  /// 13/600 - the identifying cell of a data table row (client name, subject)
  static const TextStyle tableCellStrong = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  /// 13/400 tabular - numeric cell in a data table
  static const TextStyle tableCellNumeric = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.35,
    fontFeatures: tabular,
  );

  /// 11/600 - badges & status pills
  static const TextStyle badge = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.3,
  );

  // ---------------------------------------------------------------- NUMBERS --
  /// 28/32 700 tabular - hero KPI, desktop
  static const TextStyle metricHero = TextStyle(
    fontFamily: display,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 32 / 28,
    fontFeatures: tabular,
  );

  /// 24/28 700 tabular - the hero KPI on a phone, and the large KPI anywhere.
  static const TextStyle metricLarge = TextStyle(
    fontFamily: display,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 28 / 24,
    fontFeatures: tabular,
  );

  /// 18/700 tabular - medium KPI
  static const TextStyle metricMedium = TextStyle(
    fontFamily: display,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.2,
    fontFeatures: tabular,
  );

  /// 11/14 700 +0.6 - the overline above a KPI. Pair with .toUpperCase().
  static const TextStyle metricLabel = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textCaption,
    letterSpacing: 0.6,
    height: 14 / 11,
  );

  /// 14/19 600 tabular, Green 600 - money in a row. Money is always green
  /// text, never navy.
  static const TextStyle amount = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.money,
    height: 19 / 14,
    fontFeatures: tabular,
  );

  /// 15/20 700 tabular, Green 600 - a prominent total
  static const TextStyle amountLarge = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.money,
    height: 20 / 15,
    fontFeatures: tabular,
  );
}

/// -----------------------------------------------------------------------------
/// THEME
/// -----------------------------------------------------------------------------
class AppTheme {
  AppTheme._();

  static const _controlShape = RoundedRectangleBorder(
    borderRadius: AppRadius.brMd,
  );

  /// Navy 700 at rest, 800 on hover, 900 pressed. Applied to the two filled
  /// button families so the primary action darkens the same way everywhere.
  static final WidgetStateProperty<Color> _primaryFill =
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.borderStrong;
        }
        if (states.contains(WidgetState.pressed)) {
          return AppColors.primaryBluePressed;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return AppColors.primaryBlueHover;
        }
        return AppColors.primaryBlue;
      });

  /// Horizontal padding for a standard button. Vertical padding is deliberately
  /// absent - height is owned by [AppSizing] so every button matches exactly.
  static const _buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.lg);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      primary: AppColors.primaryBlue,
      onPrimary: Colors.white,
      secondary: AppColors.primaryGreen,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTypography.text,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.standard,
      // Focus is navy, everywhere: the ring outside the control is Navy 400,
      // the border of a focused input is Navy 700.
      focusColor: AppColors.focusRing,
      hoverColor: AppColors.surfaceHover,
      highlightColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,

      // ----------------------------------------------------------------- TEXT --
      textTheme: const TextTheme(
        displaySmall: AppTypography.pageTitle,
        headlineMedium: AppTypography.pageTitle,
        headlineSmall: AppTypography.headingLarge,
        titleLarge: AppTypography.sectionTitle,
        titleMedium: AppTypography.itemTitle,
        titleSmall: AppTypography.cardTitle,
        bodyLarge: AppTypography.bodyPrimary,
        bodyMedium: AppTypography.bodySecondary,
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.button,
        labelMedium: AppTypography.captionSemibold,
        labelSmall: AppTypography.overline,
      ),

      // --------------------------------------------------------------- APPBAR --
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.sectionTitle,
        toolbarHeight: 64,
        iconTheme: IconThemeData(
          color: AppColors.textPrimary,
          size: AppSizing.iconLg,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.border)),
      ),

      // ---------------------------------------------------------------- INPUT --
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        border: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(
            color: AppColors.primaryBlue,
            width: AppSizing.borderWidthFocus,
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(
            color: AppColors.danger,
            width: AppSizing.borderWidthFocus,
          ),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.divider),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.input.copyWith(color: AppColors.textMuted),
        labelStyle: AppTypography.fieldLabel,
        floatingLabelStyle: AppTypography.fieldLabel.copyWith(
          color: AppColors.primaryBlue,
        ),
        helperStyle: AppTypography.caption,
        errorStyle: AppTypography.caption.copyWith(color: AppColors.danger),
        prefixIconColor: AppColors.textCaption,
        suffixIconColor: AppColors.textCaption,
      ),

      // -------------------------------------------------------------- BUTTONS --
      // Every button is 40h / radius 8 / 14-600 label. Compact variants opt in
      // to 32h explicitly via AppSizing.controlSm.
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(0, AppSizing.controlMd),
              padding: _buttonPadding,
              shape: _controlShape,
              textStyle: AppTypography.button,
              elevation: 0,
              iconSize: AppSizing.iconMd,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).copyWith(
              backgroundColor: _primaryFill,
              // The fill already darkens on hover and press; a translucent
              // overlay on top of it would only muddy the step.
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              minimumSize: const Size(0, AppSizing.controlMd),
              padding: _buttonPadding,
              shape: _controlShape,
              textStyle: AppTypography.button,
              elevation: 0,
              iconSize: AppSizing.iconMd,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ).copyWith(
              backgroundColor: _primaryFill,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textSecondary,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(0, AppSizing.controlMd),
          padding: _buttonPadding,
          shape: _controlShape,
          side: const BorderSide(color: AppColors.border),
          textStyle: AppTypography.button,
          iconSize: AppSizing.iconMd,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // A text button is a text action, and text actions are navy.
          foregroundColor: AppColors.link,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(0, AppSizing.controlMd),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: _controlShape,
          textStyle: AppTypography.button,
          iconSize: AppSizing.iconMd,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(AppSizing.controlSm, AppSizing.controlSm),
          padding: const EdgeInsets.all(AppSpacing.sm),
          shape: _controlShape,
          iconSize: AppSizing.iconMd,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      // ---------------------------------------------------------------- CARDS --
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: AppColors.border),
        ),
      ),

      // -------------------------------------------------------- MENUS & CHIPS --
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHeader,
        selectedColor: AppColors.primaryGreenSoft,
        disabledColor: AppColors.divider,
        labelStyle: AppTypography.badge.copyWith(
          color: AppColors.textSecondary,
        ),
        secondaryLabelStyle: AppTypography.badge,
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
        padding: AppLayout.badgePadding,
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        showCheckmark: false,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brMd,
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: AppTypography.bodySecondary,
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppRadius.brMd,
              side: BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: AppTypography.input,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppRadius.brMd,
              side: BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ),

      // ---------------------------------------------------- DIALOGS & SHEETS --
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brXl),
        titleTextStyle: AppTypography.cardTitle,
        contentTextStyle: AppTypography.bodySecondary,
        insetPadding: EdgeInsets.all(AppSpacing.xxl),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: AppTypography.bodySecondary.copyWith(
          color: Colors.white,
        ),
        actionTextColor: AppColors.navActive,
        behavior: SnackBarBehavior.floating,
        elevation: 3,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: AppRadius.brSm,
        ),
        textStyle: AppTypography.caption.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // --------------------------------------------------------- MISC CHROME --
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: AppSizing.borderWidth,
        space: AppSizing.borderWidth,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: AppSizing.iconMd,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        titleTextStyle: AppTypography.itemTitle,
        subtitleTextStyle: AppTypography.itemSubtitle,
        iconColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        horizontalTitleGap: AppSpacing.md,
        minVerticalPadding: AppSpacing.md,
      ),
      tabBarTheme: const TabBarThemeData(
        // Switching tabs is an action, and actions are navy.
        labelColor: AppColors.primaryBlue,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTypography.button,
        unselectedLabelStyle: AppTypography.button,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.border,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXs),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          // Ticking a box is a selection, and selection is navy.
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryBlue
              : Colors.transparent,
        ),
        visualDensity: VisualDensity.compact,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryBlue
              : AppColors.border,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryBlue
              : AppColors.borderStrong,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryBlue,
        linearTrackColor: AppColors.border,
        circularTrackColor: AppColors.border,
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(AppColors.surfaceHeader),
        headingTextStyle: AppTypography.tableHeader,
        dataTextStyle: AppTypography.tableCell,
        dividerThickness: AppSizing.borderWidth,
        horizontalMargin: AppSpacing.lg,
        columnSpacing: AppSpacing.xxl,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(AppRadius.xs),
        thumbColor: WidgetStatePropertyAll(
          AppColors.borderStrong.withValues(alpha: 0.8),
        ),
        crossAxisMargin: 2,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      ),
    );
  }

  /// Dark status-bar contents over the light chrome.
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );
}

class AppFormatters {
  static String formatAmount(String amount) {
    final value = double.tryParse(amount) ?? 0;
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(value);
  }

  static String formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'No date';
    final date = DateTime.tryParse(dateString);
    if (date == null) return dateString;
    return DateFormat('dd MMM yyyy').format(date);
  }

  static String formatTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return 'No time';
    final parts = timeString.split(':');
    if (parts.length < 2) return timeString;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1];
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $ampm';
  }

  static String formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '—';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  static String toApiDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  static String toApiTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }
}

Color priorityBackgroundColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'HIGH':
      return AppColors.dangerSoft;
    case 'MEDIUM':
      return AppColors.warningSoft;
    case 'LOW':
      return AppColors.yellowSoft;
    default:
      return AppColors.neutralSoft;
  }
}

Color priorityTextColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'HIGH':
      return AppColors.danger;
    case 'MEDIUM':
      return AppColors.warning;
    case 'LOW':
      // Yellow is a dot, never text: the word is brown.
      return AppColors.yellowText;
    default:
      return AppColors.neutral;
  }
}

/// The dot colour for a priority, which is where the yellow actually lives.
Color priorityDotColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'HIGH':
      return AppStatus.overdue.dot;
    case 'MEDIUM':
      return AppStatus.followUp.dot;
    case 'LOW':
      return AppStatus.lowPriority.dot;
    default:
      return AppStatus.inactive.dot;
  }
}

Color productColor(String product) {
  final p = product.trim().toUpperCase();
  switch (p) {
    case 'MF':
    case 'MUTUAL FUNDS':
      return const Color(0xFF2563EB); // Bright Royal Blue
    case 'HI':
    case 'HEALTH INSURANCE':
      return const Color(0xFF10B981); // Bright Emerald Green
    case 'GI':
    case 'GENERAL INSURANCE':
      return const Color(0xFF06B6D4); // Bright Vivid Cyan
    case 'LI':
    case 'LIFE INSURANCE':
      return const Color(0xFF8B5CF6); // Bright Violet
    case 'NCD':
    case 'NCDS':
      return const Color(0xFFF59E0B); // Bright Vivid Amber
    case 'MLD':
    case 'MLDS':
      return const Color(0xFFFF6B00); // Bright Vivid Orange
    case 'BOND':
    case 'BONDS':
      return const Color(0xFF6366F1); // Bright Indigo
    case 'CFD':
    case 'CORPORATE FDS':
    case 'CORPORATE FD':
      return const Color(0xFF14B8A6); // Bright Teal / Aqua
    case 'AIF':
    case 'AIFS':
      return const Color(0xFFA855F7); // Bright Purple
    case 'PMS':
      return const Color(0xFFEC4899); // Bright Hot Pink
    case 'ADV':
    case 'ADVISORY':
      return const Color(0xFF0EA5E9); // Bright Sky Blue
    case 'SB':
    case 'SHARES BROKING':
      return const Color(0xFF22C55E); // Bright Spring Green
    case 'US':
    case 'UNLISTED SHARES':
      return const Color(0xFFF43F5E); // Bright Rose
    case 'RE':
    case 'REAL ESTATE':
      return const Color(0xFFEAB308); // Bright Sun Yellow
    case 'LOAN':
    case 'LOANS':
      return const Color(0xFF818CF8); // Bright Periwinkle
    case 'WILL':
    case 'WILL MAKING':
      return const Color(0xFFD946EF); // Bright Neon Fuchsia
    case 'OTHER':
    case 'OTHER PRODUCTS':
      return const Color(0xFFFB7185); // Bright Coral Pink
    case 'ALL':
    case 'ALL PRODUCTS':
      return const Color(0xFF2563EB); // Bright Blue
    default:
      return const Color(0xFF2563EB);
  }
}

const productCategories = [
  ('ALL', 'All Products'),
  ('MF', 'Mutual Funds'),
  ('HI', 'Health Insurance'),
  ('GI', 'General Insurance'),
  ('LI', 'Life Insurance'),
  ('NCD', 'NCDs'),
  ('MLD', 'MLDs'),
  ('BOND', 'Bonds'),
  ('CFD', 'Corporate FDs'),
  ('AIF', 'AIFs'),
  ('PMS', 'PMS'),
  ('ADV', 'Advisory'),
  ('SB', 'Shares Broking'),
  ('US', 'Unlisted Shares'),
  ('RE', 'Real Estate'),
  ('LOAN', 'Loans'),
  ('WILL', 'Will Making'),
];

const frequencyChoices = [
  ('M', 'Monthly'),
  ('Q', 'Quarterly'),
  ('H', 'Half Yearly'),
  ('Y', 'Yearly'),
  ('O', 'One Time'),
];

const priorityChoices = [
  ('HIGH', 'High'),
  ('MEDIUM', 'Medium'),
  ('LOW', 'Low'),
];

const reminderTypeChoices = [
  ('CORPORATE', 'Corporate Event'),
  ('PERSONAL', 'Personal'),
];

const repeatTypeChoices = [
  ('NONE', 'No Repeat'),
  ('DAILY', 'Daily'),
  ('WEEKLY', 'Weekly'),
  ('MONTHLY', 'Monthly'),
];

const weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
