import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppColors {
  static const primaryBlue = Color(0xFF00337C);
  static const primaryGreen = Color(0xFF2D8A4E);
  static const background = Color(0xFFF4F9FD);
  static const sidebarText = Color(0xFF7D8592);
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
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
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
      return const Color(0xFFFEE2E2);
    case 'MEDIUM':
      return const Color(0xFFFEF9C3);
    case 'LOW':
      return const Color(0xFFDCFCE7);
    default:
      return Colors.grey.shade100;
  }
}

Color priorityTextColor(String priority) {
  switch (priority.toUpperCase()) {
    case 'HIGH':
      return const Color(0xFFB91C1C);
    case 'MEDIUM':
      return const Color(0xFFA16207);
    case 'LOW':
      return const Color(0xFF15803D);
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
