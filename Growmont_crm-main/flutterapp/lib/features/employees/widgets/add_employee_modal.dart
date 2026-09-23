import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../shared/widgets/app_modal_shell.dart';
import '../../../shared/widgets/password_form_field.dart';
import '../../auth/auth_provider.dart';

class AddEmployeeModal extends ConsumerStatefulWidget {
  const AddEmployeeModal({super.key, this.existing});

  final Employee? existing;

  @override
  ConsumerState<AddEmployeeModal> createState() => _AddEmployeeModalState();
}

class _AddEmployeeModalState extends ConsumerState<AddEmployeeModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _email;
  late TextEditingController _mobile;
  late TextEditingController _password;
  late DateTime _dob;
  String _gender = 'M';
  String _role = 'EMPLOYEE';
  XFile? _avatar;
  Uint8List? _avatarBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _mobile = TextEditingController(text: e?.mobileNo ?? '');
    _password = TextEditingController();
    _dob = e != null && e.dob.isNotEmpty
        ? DateTime.parse(e.dob)
        : DateTime(1990);
    _gender = e?.gender ?? 'M';
    _role = (e?.role ?? 'EMPLOYEE').toUpperCase() == 'ADMIN'
        ? 'ADMIN'
        : 'EMPLOYEE';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _avatar = file;
        _avatarBytes = bytes;
      });
    }
  }

  /// A bare username is completed to a full company address, so an admin can
  /// type "rohan" and get rohan@growmont.com — the same shorthand the login
  /// screen accepts. An address typed in full must already be on the domain;
  /// [_validateEmail] rejects anything else before we get here.
  String _normalisedEmail() {
    final raw = _email.text.trim();
    if (raw.contains('@')) return raw;
    return '$raw$kAllowedEmailDomain';
  }

  String? _validateEmail(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return 'Required';
    if (!raw.contains('@')) {
      // Bare username — _normalisedEmail() will append the domain.
      return null;
    }
    if (!raw.toLowerCase().endsWith(kAllowedEmailDomain)) {
      return 'Employee emails must be $kAllowedEmailDomain';
    }
    if (raw.split('@').first.isEmpty) return 'Enter a valid email address';
    return null;
  }

  /// An admin editing their own record can't change their role or sign-in
  /// email — the server refuses both, so another admin is always needed.
  bool get _isSelf =>
      widget.existing != null &&
      ref.read(authProvider).user?.id == widget.existing!.id;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final map = <String, dynamic>{
      'name': _name.text.trim(),
      'email': _normalisedEmail(),
      'mobile_no': _mobile.text.trim(),
      'gender': _gender,
      'dob': AppFormatters.toApiDate(_dob),
      'role': _role,
      if (_password.text.isNotEmpty) 'password': _password.text,
    };

    try {
      if (_avatarBytes != null) {
        try {
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${_avatar?.name ?? 'avatar.jpg'}';
          final storageRef = FirebaseStorage.instance.ref().child(
            'avatars/$fileName',
          );
          final uploadTask = await storageRef.putData(
            _avatarBytes!,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final url = await uploadTask.ref.getDownloadURL();
          map['avatar_url'] = url;
        } catch (_) {
          // If storage fails, continue with employee creation
        }
      }

      final api = ref.read(apiServiceProvider);
      final existing = widget.existing;
      if (existing != null) {
        // The sign-in email and the role belong to the account, not just the
        // record, so they change through the server; the rest is a profile
        // edit.
        final email = map.remove('email') as String;
        final role = map.remove('role') as String;
        if (email.toLowerCase() != existing.email.toLowerCase()) {
          await api.changeEmployeeEmail(existing.id, email);
        }
        if (role != existing.role.toUpperCase()) {
          await api.setEmployeeRole(existing.id, role);
        }
        await api.updateEmployee(existing.id, map);
      } else {
        await api.createEmployee(map);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: widget.existing != null ? 'Edit Employee' : 'Add Employee',
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 40,
                  child: _avatarBytes != null
                      ? ClipOval(
                          child: Image.memory(
                            _avatarBytes!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          size: AppSizing.iconDisplay,
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _email,
              enabled: !_isSelf,
              decoration: InputDecoration(
                labelText: 'Email *',
                helperText: _isSelf
                    ? 'Ask another admin to change your sign-in email'
                    : widget.existing != null
                    ? 'This is the address they log in with'
                    : 'Username is enough — $kAllowedEmailDomain '
                          'is added automatically',
              ),
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _mobile,
              decoration: const InputDecoration(labelText: 'Mobile *'),
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date of Birth *'),
              subtitle: Text(
                AppFormatters.formatDate(AppFormatters.toApiDate(_dob)),
              ),
              trailing: const Icon(
                Icons.calendar_today,
                size: AppSizing.iconMd,
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dob,
                  firstDate: DateTime(1950),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _dob = d);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: 'M', child: Text('Male')),
                DropdownMenuItem(value: 'F', child: Text('Female')),
                DropdownMenuItem(value: 'O', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _role,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Role',
                helperText: _isSelf
                    ? 'Ask another admin to change your role'
                    : _role == 'ADMIN'
                    ? 'Admins manage accounts and see every record'
                    : null,
              ),
              items: const [
                DropdownMenuItem(value: 'EMPLOYEE', child: Text('Employee')),
                DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
              ],
              onChanged: _isSelf ? null : (v) => setState(() => _role = v!),
            ),
            if (widget.existing == null) ...[
              const SizedBox(height: AppSpacing.md),
              PasswordFormField(
                controller: _password,
                labelText: 'Password *',
                helperText: 'At least $kMinPasswordLength characters',
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              height: AppSizing.controlLg,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                ),
                child: Text(_loading ? 'Saving...' : 'Save Employee'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
