import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// -----------------------------------------------------------------------------
/// COLOR
/// -----------------------------------------------------------------------------
class AppColors {
  AppColors._();

  // Brand
  static const primaryBlue = Color(0xFF00337C);
  static const primaryGreen = Color(0xFF2D8A4E);
  static const primaryGreenDark = Color(0xFF246E3F);
  static const primaryGreenSoft = Color(0xFFECFDF3);

  // Chrome
  static const background = Color(0xFFF1F5F9);
  static const sidebarBg = Color(0xFF0F4A31);
  static const sidebarBgDeep = Color(0xFF092E1E); // gradient end
  static const sidebarText = Color(0xFFFFFFFF);

  // Surfaces
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHeader = Color(0xFFF8FAFC); // Slate 50 - table/panel head
  static const surfaceHover = Color(0xFFF1F5F9); // Slate 100 - row hover
  static const surfaceSelected = Color(0xFFEFF6FF); // Blue 50 - selected row
  static const surfaceSunken = Color(0xFFF8FAFC);

  // Text
  static const textPrimary = Color(0xFF0F172A); // Slate 900 - titles, values
  static const textSecondary = Color(0xFF475569); // Slate 600 - body, subtitles
  static const textMuted = Color(0xFF94A3B8); // Slate 400 - captions, hints
  static const textOnDark = Color(0xFFFFFFFF);

  // Lines
  static const border = Color(0xFFE2E8F0); // Slate 200
  static const borderStrong = Color(0xFFCBD5E1); // Slate 300
  static const divider = Color(0xFFF1F5F9); // Slate 100

  // Status
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEF2F2);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFFF7ED);
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFECFDF3);
  static const info = Color(0xFF2563EB);
  static const infoSoft = Color(0xFFEFF6FF);
  static const yellow = Color(0xFFEAB308); // priority: LOW - vibrant yellow
  static const yellowSoft = Color(0xFFFEF9C3);
  static const neutral = Color(0xFF64748B);
  static const neutralSoft = Color(0xFFF1F5F9);
}

/// Accent ramps for stat tiles, avatar monograms and chart series.
///
/// These are the only colours outside [AppColors] that may appear in a screen,
/// and they exist so those surfaces stay a coherent family instead of a drift
/// of one-off hex values. Each ramp reads: deep -> base -> border -> tint.
class AppAccents {
  AppAccents._();

  // Blue - the default accent, and the chart series ramp.
  static const blueDeep = Color(0xFF1E3A8A);
  static const blueStrong = Color(0xFF1D4ED8);
  static const blueBase = Color(0xFF2563EB);
  static const blueLabel = Color(0xFF1E40AF);
  static const blueMid = Color(0xFF3B82F6);
  static const blueLight = Color(0xFF60A5FA);
  static const blueMuted = Color(0xFF93C5FD);
  static const blueBorder = Color(0xFFBFDBFE);
  static const blueTint = Color(0xFFDBEAFE);
  static const blueSoft = Color(0xFFEFF6FF);

  // Green - revenue, positive deltas, "active" states.
  static const greenDeep = Color(0xFF166534);
  static const greenStrong = Color(0xFF15803D);
  static const greenTeal = Color(0xFF047857);
  static const greenBase = Color(0xFF16A34A);
  static const greenBright = Color(0xFF4ADE80);
  static const greenBorder = Color(0xFFA7F3D0);
  static const greenBorderSoft = Color(0xFFBBF7D0);
  static const greenTint = Color(0xFFECFDF5);
  static const greenSoft = Color(0xFFF0FDF4);

  // Purple - interactions / chats.
  static const purpleBase = Color(0xFF9333EA);
  static const purpleSoft = Color(0xFFFAF5FF);
  static const indigoBase = Color(0xFF6366F1);
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
  /// 32/700 - page title, desktop
  static const TextStyle pageTitle = TextStyle(
    fontFamily: display,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 1.2,
  );

  /// 24/700 - page title, mobile
  static const TextStyle pageTitleMobile = TextStyle(
    fontFamily: display,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.25,
  );

  /// 22/700 - major heading inside a page
  static const TextStyle headingLarge = TextStyle(
    fontFamily: display,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.3,
  );

  /// 18/700 - section heading (Clients, Sales, Reminders)
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: display,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  /// 16/600 - card & modal title
  static const TextStyle cardTitle = TextStyle(
    fontFamily: display,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.35,
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

  /// 15/600 - list item title, client name, row subject
  static const TextStyle itemTitle = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  /// 13/400 - list item subtitle, contact info, secondary attributes
  static const TextStyle itemSubtitle = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// 14/500 - primary body copy
  static const TextStyle bodyPrimary = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Color(0xFF1E293B),
    height: 1.45,
  );

  /// 13/400 - secondary body copy, descriptions
  static const TextStyle bodySecondary = TextStyle(
    fontFamily: text,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  /// 14/500 - the value half of a label/value pair
  static const TextStyle fieldValue = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// 12/600 - the label half of a label/value pair, form field labels
  static const TextStyle fieldLabel = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 1.35,
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
  /// 12/400 - captions, timestamps, helper text
  static const TextStyle caption = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.35,
  );

  /// 12/600 - emphasised caption
  static const TextStyle captionSemibold = TextStyle(
    fontFamily: text,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: 1.35,
  );

  /// 11/700 - overline / mini category header. Pair with .toUpperCase().
  static const TextStyle overline = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF64748B),
    letterSpacing: 0.6,
    height: 1.3,
  );

  /// 11/700 - table column header. Pair with .toUpperCase().
  static const TextStyle tableHeader = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF475569),
    letterSpacing: 0.5,
    height: 1.3,
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
  /// 28/700 tabular - hero KPI
  static const TextStyle metricHero = TextStyle(
    fontFamily: display,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 1.15,
    fontFeatures: tabular,
  );

  /// 24/700 tabular - large KPI
  static const TextStyle metricLarge = TextStyle(
    fontFamily: display,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.15,
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

  /// 11/600 - KPI caption under a number. Pair with .toUpperCase().
  static const TextStyle metricLabel = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFF64748B),
    letterSpacing: 0.5,
    height: 1.3,
  );

  /// 14/600 tabular green - currency amount in a row
  static const TextStyle amount = TextStyle(
    fontFamily: text,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.primaryGreen,
    height: 1.35,
    fontFeatures: tabular,
  );

  /// 15/700 tabular - a prominent total
  static const TextStyle amountLarge = TextStyle(
    fontFamily: text,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryGreen,
    height: 1.3,
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
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),

      // -------------------------------------------------------------- BUTTONS --
      // Every button is 40h / radius 8 / 14-600 label. Compact variants opt in
      // to 32h explicitly via AppSizing.controlSm.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderStrong,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(0, AppSizing.controlMd),
          padding: _buttonPadding,
          shape: _controlShape,
          textStyle: AppTypography.button,
          elevation: 0,
          iconSize: AppSizing.iconMd,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, AppSizing.controlMd),
          padding: _buttonPadding,
          shape: _controlShape,
          textStyle: AppTypography.button,
          elevation: 0,
          iconSize: AppSizing.iconMd,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          foregroundColor: AppColors.textSecondary,
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
        actionTextColor: AppColors.primaryGreenSoft,
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
        labelColor: AppColors.primaryGreen,
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
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryGreen
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
              ? AppColors.primaryGreen
              : AppColors.border,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primaryGreen
              : AppColors.borderStrong,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryGreen,
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
      return AppColors.yellow;
    default:
      return AppColors.neutral;
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
