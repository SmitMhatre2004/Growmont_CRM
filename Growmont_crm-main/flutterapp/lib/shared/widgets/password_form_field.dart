import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// A password input with a show/hide toggle and the app's minimum-length
/// rule. Used wherever a password is set or confirmed.
class PasswordFormField extends StatefulWidget {
  const PasswordFormField({
    super.key,
    required this.controller,
    this.labelText = 'Password',
    this.helperText,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;

  /// Replaces the default minimum-length check when given.
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;

  /// The default check for a new password.
  static String? validateNew(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < kMinPasswordLength) {
      return 'Password must be at least $kMinPasswordLength characters';
    }
    return null;
  }

  /// A 12-character password with no easily confused characters (0/O, 1/l),
  /// for an admin to set and hand over.
  static String generate() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#%';
    final rand = Random.secure();
    return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  State<PasswordFormField> createState() => _PasswordFormFieldState();
}

class _PasswordFormFieldState extends State<PasswordFormField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: widget.validator ?? PasswordFormField.validateNew,
    );
  }
}
