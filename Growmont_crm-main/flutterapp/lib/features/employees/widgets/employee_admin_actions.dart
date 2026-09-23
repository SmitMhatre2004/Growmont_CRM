import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../shared/widgets/app_modal_shell.dart';
import '../../../shared/widgets/inline_error_banner.dart';
import '../../../shared/widgets/password_form_field.dart';
import '../../auth/auth_provider.dart';
import '../../profile/widgets/change_password_dialog.dart';

// Everything an admin can do to one employee account, shared by the
// Employees list and the employee detail screen. Each action runs through a
// Cloud Function (see FirestoreService), which re-checks that the caller is
// an admin and refuses the ones that would let an admin lock themselves out
// — so the menu hides those for your own account rather than offering
// something the server will reject.

enum _AdminAction { edit, password, role, access, delete }

class EmployeeAdminMenu extends ConsumerWidget {
  const EmployeeAdminMenu({
    super.key,
    required this.employee,
    required this.onEdit,
    required this.onChanged,
    this.onDeleted,
  });

  final Employee employee;
  final VoidCallback onEdit;

  /// Called after the account changed, to reload what's on screen.
  final VoidCallback onChanged;

  /// Called after the account was deleted; defaults to [onChanged].
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelf = ref.watch(authProvider).user?.id == employee.id;
    final isAdminRole = employee.role.toUpperCase() == 'ADMIN';

    return PopupMenuButton<_AdminAction>(
      icon: const Icon(
        Icons.more_vert,
        size: AppSizing.iconMd,
        color: AppColors.textMuted,
      ),
      padding: EdgeInsets.zero,
      tooltip: 'Manage employee',
      onSelected: (action) => _run(context, ref, action, isSelf),
      itemBuilder: (_) => [
        _item(
          _AdminAction.edit,
          Icons.edit_outlined,
          AppColors.info,
          'Edit details',
        ),
        _item(
          _AdminAction.password,
          Icons.key_outlined,
          AppColors.info,
          isSelf ? 'Change my password' : 'Set new password',
        ),
        if (!isSelf) ...[
          _item(
            _AdminAction.role,
            isAdminRole
                ? Icons.remove_moderator_outlined
                : Icons.admin_panel_settings_outlined,
            AppColors.primaryBlue,
            isAdminRole ? 'Remove admin rights' : 'Make admin',
          ),
          _item(
            _AdminAction.access,
            employee.isActive ? Icons.block_outlined : Icons.lock_open_outlined,
            employee.isActive ? AppColors.warning : AppColors.primaryGreen,
            employee.isActive
                ? 'Restrict access'
                : (employee.isPending ? 'Approve access' : 'Restore access'),
          ),
          const PopupMenuDivider(),
          _item(
            _AdminAction.delete,
            Icons.delete_outline,
            AppColors.danger,
            'Delete',
            labelColor: AppColors.danger,
          ),
        ],
      ],
    );
  }

  PopupMenuItem<_AdminAction> _item(
    _AdminAction value,
    IconData icon,
    Color iconColor,
    String label, {
    Color? labelColor,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: AppSizing.iconSm, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: TextStyle(fontSize: 13, color: labelColor)),
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _AdminAction action,
    bool isSelf,
  ) async {
    final api = ref.read(apiServiceProvider);
    final name = employee.name.isNotEmpty ? employee.name : employee.email;
    final isAdminRole = employee.role.toUpperCase() == 'ADMIN';

    switch (action) {
      case _AdminAction.edit:
        onEdit();

      case _AdminAction.password:
        if (isSelf) {
          await showChangePasswordDialog(context);
          return;
        }
        final set = await showDialog<bool>(
          context: context,
          builder: (_) => _SetPasswordDialog(employee: employee),
        );
        if (set == true && context.mounted) {
          _snack(
            context,
            'Password updated. $name has been signed out and must use the '
            'new password to log in.',
          );
        }

      case _AdminAction.role:
        final newRole = isAdminRole ? 'EMPLOYEE' : 'ADMIN';
        final done = await _confirm(
          context,
          title: isAdminRole ? 'Remove admin rights?' : 'Make $name an admin?',
          message: isAdminRole
              ? '$name will only see their own clients, sales and '
                    'interactions, and will no longer be able to manage '
                    'employee accounts.'
              : 'Admins can add, edit, restrict and delete employee '
                    'accounts, set passwords, make other admins, and see '
                    'every client, sale and interaction.',
          confirmLabel: isAdminRole ? 'Remove Admin' : 'Make Admin',
          action: () => api.setEmployeeRole(employee.id, newRole),
        );
        if (done && context.mounted) {
          _snack(
            context,
            isAdminRole ? '$name is now an employee' : '$name is now an admin',
          );
          onChanged();
        }

      case _AdminAction.access:
        final restricting = employee.isActive;
        final done = await _confirm(
          context,
          title: restricting
              ? 'Restrict $name?'
              : (employee.isPending ? 'Approve $name?' : 'Restore access?'),
          message: restricting
              ? '$name will be signed out on every device and blocked from '
                    'logging in. Their records are kept and you can restore '
                    'access at any time.'
              : '$name will be able to log in as '
                    '${isAdminRole ? 'an admin' : 'an employee'} straight away.',
          confirmLabel: restricting
              ? 'Restrict'
              : (employee.isPending ? 'Approve' : 'Restore'),
          destructive: restricting,
          action: () => api.setEmployeeAccess(employee.id, active: !restricting),
        );
        if (done && context.mounted) {
          _snack(
            context,
            restricting ? '$name has been restricted' : '$name can log in now',
          );
          onChanged();
        }

      case _AdminAction.delete:
        final done = await _confirm(
          context,
          title: 'Delete $name?',
          message: 'Their sign-in account is removed and they can no longer '
              'log in. Their clients, sales and interactions stay in the '
              'CRM. This cannot be undone — to block someone temporarily, '
              'restrict their access instead.',
          confirmLabel: 'Delete',
          destructive: true,
          action: () => api.deleteEmployee(employee.id),
        );
        if (done && context.mounted) {
          _snack(context, '$name has been deleted');
          (onDeleted ?? onChanged)();
        }
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
    bool destructive = false,
  }) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmActionDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        destructive: destructive,
        action: action,
      ),
    );
    return done == true;
  }
}

/// A confirmation that runs [action] itself, so a failure is shown in place
/// and the admin can retry or cancel, instead of the dialog closing first.
class _ConfirmActionDialog extends StatefulWidget {
  const _ConfirmActionDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.action,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final Future<void> Function() action;

  @override
  State<_ConfirmActionDialog> createState() => _ConfirmActionDialogState();
}

class _ConfirmActionDialogState extends State<_ConfirmActionDialog> {
  bool _running = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await widget.action();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              InlineErrorBanner(message: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _running ? null : _go,
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          child: Text(_running ? 'Working...' : widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Sets a new password for another employee.
class _SetPasswordDialog extends ConsumerStatefulWidget {
  const _SetPasswordDialog({required this.employee});

  final Employee employee;

  @override
  ConsumerState<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<_SetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _generated;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _generate() {
    final password = PasswordFormField.generate();
    setState(() {
      _generated = password;
      _password.text = password;
      _confirm.text = password;
    });
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(apiServiceProvider)
          .setEmployeePassword(widget.employee.id, _password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    return AppModalShell(
      title: 'Set New Password',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For ${emp.name.isNotEmpty ? emp.name : emp.email} '
              '(${emp.email}). They will be signed out on every device and '
              'must log in with the new password.',
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              InlineErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            PasswordFormField(
              controller: _password,
              labelText: 'New password',
              helperText: 'At least $kMinPasswordLength characters',
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordFormField(
              controller: _confirm,
              labelText: 'Confirm new password',
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (v) =>
                  v != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : _generate,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Generate a strong password'),
              ),
            ),
            if (_generated != null && _generated == _password.text)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHeader,
                  borderRadius: AppRadius.brMd,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _generated!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _generated!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: AppSizing.controlLg,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Saving...' : 'Set Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small badge for an account that can't currently log in; renders
/// nothing for an active one.
class EmployeeStatusChip extends StatelessWidget {
  const EmployeeStatusChip({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    if (employee.isActive) return const SizedBox.shrink();
    final (label, color, background) = switch (employee.status) {
      EmployeeStatus.pending => (
        'PENDING',
        AppColors.warning,
        AppColors.warningSoft,
      ),
      EmployeeStatus.rejected => (
        'REJECTED',
        AppColors.danger,
        AppColors.dangerSoft,
      ),
      _ => ('RESTRICTED', AppColors.danger, AppColors.dangerSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    );
  }
}
