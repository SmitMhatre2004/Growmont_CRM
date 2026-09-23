import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_modal_shell.dart';
import '../../../shared/widgets/inline_error_banner.dart';
import '../../../shared/widgets/password_form_field.dart';

/// Lets the signed-in user change their own password. Resolves to true once
/// it has changed.
Future<bool> showChangePasswordDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const ChangePasswordDialog(),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password changed. Other devices will need the new password.',
        ),
      ),
    );
  }
  return changed == true;
}

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
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
          .changePassword(oldPassword: _current.text, newPassword: _new.text);
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
    return AppModalShell(
      title: 'Change Password',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              InlineErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            PasswordFormField(
              controller: _current,
              labelText: 'Current password',
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your current password' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordFormField(
              controller: _new,
              labelText: 'New password',
              helperText: 'At least $kMinPasswordLength characters',
              textInputAction: TextInputAction.next,
              validator: (v) {
                final basic = PasswordFormField.validateNew(v);
                if (basic != null) return basic;
                if (v == _current.text) {
                  return 'Choose a password different from the current one';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            PasswordFormField(
              controller: _confirm,
              labelText: 'Confirm new password',
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (v) =>
                  v != _new.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: AppSizing.controlLg,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Saving...' : 'Change Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
