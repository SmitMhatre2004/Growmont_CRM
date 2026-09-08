import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppColors {
  static const primaryBlue = Color(0xFF00337C);
  static const primaryGreen = Color(0xFF2D8A4E);
  static const background = Color(0xFFF1F5F9);
  static const sidebarBg = Color(0xFF0F4A31);
  static const sidebarText = Color(0xFFFFFFFF);

  // Core typographic and surface tokens
  static const textPrimary = Color(
    0xFF0F172A,
  ); // Slate 900: high contrast, primary titles, names & values
  static const textSecondary = Color(
    0xFF475569,
  ); // Slate 600: secondary info, subtitles, regular body
  static const textMuted = Color(
    0xFF94A3B8,
  ); // Slate 400: captions, timestamps, placeholder text
  static const border = Color(
    0xFFE2E8F0,
  ); // Slate 200: subtle borders for clean cards & dividers
  static const surfaceHeader = Color(
    0xFFF8FAFC,
  ); // Slate 50: clean subtle table & panel headers
}

/// Centralized typographic scale establishing clear visual hierarchy
/// based on text importance across headings, metadata, numbers and actions.
class AppTypography {
  AppTypography._();

  // Page Title (Primary Screen Headings - Desktop / Wide)
  static const TextStyle pageTitle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 1.2,
  );

  // Page Title for mobile / compact screens
  static const TextStyle pageTitleMobile = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  // Page Subtitle / Section description
  static const TextStyle pageSubtitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // Section Heading (e.g. Clients, Sales, Reminders)
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  // Section Subtitle
  static const TextStyle sectionSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Card / Modal Title
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  // Item Title (Names in lists, main row subject, client names)
  static const TextStyle itemTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Item Subtitle (Contact info, timestamps, secondary attributes)
  static const TextStyle itemSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.35,
  );

  // Table Column Header (Clean, legible uppercase)
  static const TextStyle tableHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Color(0xFF475569),
    letterSpacing: 0.6,
  );

  // Primary Body Text
  static const TextStyle bodyPrimary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: Color(0xFF1E293B),
    height: 1.4,
  );

  // Secondary Body Text / Descriptions
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // Caption / Metadata / Timestamps
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  // Caption Emphasized
  static const TextStyle captionSemibold = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  // Overline / Mini Category Header / KPI labels
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF64748B),
    letterSpacing: 0.7,
  );

  // Badges & Pills
  static const TextStyle badge = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  // Large KPI Metric Numbers
  static const TextStyle metricLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  // Medium KPI Metric Numbers
  static const TextStyle metricMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  // KPI Metric Labels
  static const TextStyle metricLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: Color(0xFF64748B),
    letterSpacing: 0.5,
  );

  // Financial / Currency Amount (Prominent High-Contrast)
  static const TextStyle amount = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryGreen,
  );
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
        primary: AppColors.primaryGreen,
        secondary: AppColors.primaryBlue,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: const TextTheme(
        headlineMedium: AppTypography.pageTitle,
        titleLarge: AppTypography.sectionTitle,
        titleMedium: AppTypography.itemTitle,
        titleSmall: AppTypography.cardTitle,
        bodyLarge: AppTypography.bodyPrimary,
        bodyMedium: AppTypography.bodySecondary,
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.captionSemibold,
        labelSmall: AppTypography.overline,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
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
      return const Color(0xFFFEF2F2);
    case 'MEDIUM':
      return const Color(0xFFFFF7ED);
    case 'LOW':
      return const Color(0xFFFEFCE8);
    default:
      return Colors.grey.shade100;
  }
}

Color priorityTextColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'HIGH':
      return const Color.fromARGB(255, 220, 50, 50);
    case 'MEDIUM':
      return const Color.fromARGB(255, 255, 167, 66);
    case 'LOW':
      return const Color.fromRGBO(255, 237, 39, 1);
    default:
      return Colors.grey.shade700;
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
