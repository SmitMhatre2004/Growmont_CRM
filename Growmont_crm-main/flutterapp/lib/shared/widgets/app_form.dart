import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// -----------------------------------------------------------------------------
/// GROWMONT FORM KIT
/// -----------------------------------------------------------------------------
/// Every add/edit form in the app is built from these pieces so they all read
/// the same way:
///
///  * Modal title (18/700) - from [AppModalShell]
///  * Section heading (11/700 overline) - [AppFormSection]
///  * Field label (12/600, above the input, never floating) - [AppFormField]
///  * Input text (14/400) - the theme's input style
///  * Helper / error text (12/400) - the theme's helper style
///
/// Every input is the same height (text, dropdown, date, time), fields are
/// 16pt apart, sections 24pt apart, and the footer is always Cancel + primary.
/// Required is the default; the few optional fields say so in their label.
/// -----------------------------------------------------------------------------

/// Vertical gap between two fields in a section.
const double kFormFieldGap = AppSpacing.lg;

/// Vertical gap between two sections.
const double kFormSectionGap = AppSpacing.xxl;

/// Lays [children] out top to bottom with a uniform [gap] between them.
class AppFormColumn extends StatelessWidget {
  const AppFormColumn({
    super.key,
    required this.children,
    this.gap = kFormFieldGap,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}

/// A titled group of fields. The title is an uppercase overline so it sits
/// clearly above the field labels in the hierarchy without competing with
/// the modal title.
class AppFormSection extends StatelessWidget {
  const AppFormSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!.toUpperCase(), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.md),
        ],
        AppFormColumn(children: children),
      ],
    );
  }
}

/// A label that sits above its input.
///
/// [trailing] goes on the right of the label row - a small text action such
/// as "Add custom reason".
class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
    this.trailing,
  });

  final String label;
  final Widget child;

  /// Appends a quiet "Optional" to the label.
  final bool optional;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (optional)
                      TextSpan(
                        text: '  Optional',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
                style: AppTypography.fieldLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// A dropdown the same height as a text input.
///
/// Flutter gives a dense dropdown a 24pt minimum inner height against the
/// ~20pt of a line of input text, so with the theme's padding a dropdown
/// would stand 4pt taller than the field beside it. Trimming 2pt top and
/// bottom brings it level.
///
/// Like [DropdownButtonFormField], [value] is only read on first build: give
/// the field a [Key] that changes with the value to reset it from outside.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = 'Select',
    this.helperText,
    this.validator,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;

  /// Null disables the field.
  final ValueChanged<T?>? onChanged;
  final String hint;
  final String? helperText;
  final FormFieldValidator<T>? validator;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.md - AppSpacing.xxs,
  );

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      // Without this the selected value renders in the theme's 16/500 body
      // style, bigger and heavier than the text in the field beside it.
      style: AppTypography.input,
      hint: Text(
        hint,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.input.copyWith(color: AppColors.textMuted),
      ),
      decoration: InputDecoration(
        contentPadding: _padding,
        helperText: helperText,
        helperMaxLines: 2,
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}

/// Builds dropdown items from the app's `(value, label)` choice lists.
List<DropdownMenuItem<String>> choiceItems(List<(String, String)> choices) => [
  for (final c in choices)
    DropdownMenuItem(
      value: c.$1,
      child: Text(c.$2, overflow: TextOverflow.ellipsis),
    ),
];

/// A value the user can see but not change (e.g. an employee's own name on
/// a form where admins pick the employee). Greyed so it doesn't read as an
/// input waiting for text.
class AppReadOnlyField extends StatelessWidget {
  const AppReadOnlyField({super.key, required this.value, this.helperText});

  final String value;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceHeader,
        helperText: helperText,
        helperMaxLines: 2,
        enabled: false,
      ),
      child: Text(
        value,
        style: AppTypography.input.copyWith(color: AppColors.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A tappable field that looks exactly like a text input, for values chosen
/// from a picker (dates, times). Shows [placeholder] when [value] is null.
class AppPickerField extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.value,
    required this.icon,
    required this.onTap,
    this.placeholder = 'Select',
    this.onClear,
  });

  final String? value;
  final IconData icon;
  final VoidCallback? onTap;
  final String placeholder;

  /// When given and [value] is set, a small clear button replaces the icon.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final canClear = onClear != null && value != null;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brMd,
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            hintText: placeholder,
            suffixIconConstraints: const BoxConstraints(
              minWidth: AppSizing.controlMd,
              minHeight: 0,
            ),
            suffixIcon: canClear
                ? IconButton(
                    tooltip: 'Clear',
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: AppSizing.iconSm),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                : Icon(icon, size: AppSizing.iconMd),
          ),
          child: Text(
            value ?? '',
            style: AppTypography.input,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// A date input. Opens the platform date picker on tap.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  /// Defaults to 1 Jan 2000.
  final DateTime? firstDate;

  /// Defaults to 1 Jan 2100.
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final firstDate = this.firstDate ?? DateTime(2000);
    final lastDate = this.lastDate ?? DateTime(2100);
    return AppPickerField(
      value: AppFormatters.formatDate(AppFormatters.toApiDate(value)),
      icon: Icons.calendar_today_outlined,
      onTap: () async {
        // showDatePicker asserts the initial date is inside the range; an
        // old record can hold a date before today's firstDate.
        var initial = value;
        if (initial.isBefore(firstDate)) initial = firstDate;
        if (initial.isAfter(lastDate)) initial = lastDate;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// A time input. Opens the platform time picker on tap. [value] may be null
/// for an optional time, in which case [placeholder] shows and, if
/// [onClear] is given, a set time can be cleared again.
class AppTimeField extends StatelessWidget {
  const AppTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.initialTime,
    this.placeholder = 'Select time',
    this.onClear,
  });

  final TimeOfDay? value;
  final ValueChanged<TimeOfDay> onChanged;

  /// Where the picker opens when [value] is null.
  final TimeOfDay? initialTime;
  final String placeholder;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return AppPickerField(
      value: value?.format(context),
      icon: Icons.schedule_outlined,
      placeholder: placeholder,
      onClear: onClear,
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime:
              value ?? initialTime ?? const TimeOfDay(hour: 10, minute: 0),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// An on/off row that reveals more fields when switched on - used for
/// optional blocks such as a follow-up or a repeat schedule. Bordered like
/// an input so the revealed fields read as belonging to the switch.
class AppToggleSection extends StatelessWidget {
  const AppToggleSection({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Shown below the switch while [value] is true.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => onChanged(!value),
            borderRadius: AppRadius.brMd,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTypography.bodyPrimary),
                        if (subtitle != null)
                          Text(subtitle!, style: AppTypography.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: value
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: child,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// The footer of every form: a secondary Cancel and the primary action.
/// Right-aligned on wide screens; two equal full-width buttons on phones.
class AppFormActions extends StatelessWidget {
  const AppFormActions({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.busy = false,
    this.busyLabel = 'Saving...',
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.icon,
  });

  final String submitLabel;
  final VoidCallback? onSubmit;
  final bool busy;
  final String busyLabel;
  final String cancelLabel;

  /// Defaults to closing the dialog.
  final VoidCallback? onCancel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);
    final size = Size(
      0,
      isMobile ? AppSizing.controlLg : AppSizing.controlMd,
    );
    final cancel = OutlinedButton(
      onPressed: busy ? null : (onCancel ?? () => Navigator.maybePop(context)),
      style: OutlinedButton.styleFrom(minimumSize: size),
      child: Text(cancelLabel),
    );
    final label = Text(
      busy ? busyLabel : submitLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    // On a phone each button gets half the width; an icon there costs the
    // label its last few characters.
    final submit = icon == null || isMobile
        ? FilledButton(
            onPressed: busy ? null : onSubmit,
            style: FilledButton.styleFrom(minimumSize: size),
            child: label,
          )
        : FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            style: FilledButton.styleFrom(minimumSize: size),
            icon: Icon(icon, size: AppSizing.iconSm),
            label: label,
          );

    if (isMobile) {
      return Row(
        children: [
          Expanded(child: cancel),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: submit),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        cancel,
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: submit),
      ],
    );
  }
}
