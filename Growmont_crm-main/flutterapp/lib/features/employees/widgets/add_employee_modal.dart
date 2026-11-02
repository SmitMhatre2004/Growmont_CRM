import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../shared/widgets/app_form.dart';
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
      footer: AppFormActions(
        submitLabel: 'Save Employee',
        busy: _loading,
        onSubmit: _submit,
      ),
      child: Form(
        key: _formKey,
        child: AppFormColumn(
          gap: kFormSectionGap,
          children: [
            Center(
              child: Column(
                children: [
                  InkWell(
                    onTap: _pickAvatar,
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: AppSizing.avatarXl / 2,
                      backgroundColor: AppColors.surfaceHeader,
                      child: _avatarBytes != null
                          ? ClipOval(
                              child: Image.memory(
                                _avatarBytes!,
                                width: AppSizing.avatarXl,
                                height: AppSizing.avatarXl,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.add_a_photo_outlined,
                              size: AppSizing.iconXl,
                              color: AppColors.textCaption,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _pickAvatar,
                    child: Text(
                      _avatarBytes != null ? 'Change photo' : 'Upload photo',
                    ),
                  ),
                ],
              ),
            ),
            AppFormSection(
              title: 'Profile',
              children: [
                AppFormField(
                  label: 'Full name',
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Full name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a name'
                        : null,
                  ),
                ),
                AppFormField(
                  label: 'Email',
                  child: TextFormField(
                    controller: _email,
                    enabled: !_isSelf,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'username',
                      helperMaxLines: 2,
                      helperText: _isSelf
                          ? 'Ask another admin to change your sign-in email'
                          : widget.existing != null
                          ? 'This is the address they log in with'
                          : 'Username is enough — $kAllowedEmailDomain '
                                'is added automatically',
                    ),
                    validator: _validateEmail,
                  ),
                ),
                modalFieldPair(
                  context,
                  AppFormField(
                    label: 'Mobile number',
                    child: TextFormField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: 'Mobile number',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter a mobile number'
                          : null,
                    ),
                  ),
                  AppFormField(
                    label: 'Date of birth',
                    child: AppDateField(
                      value: _dob,
                      firstDate: DateTime(1950),
                      lastDate: DateTime.now(),
                      onChanged: (d) => setState(() => _dob = d),
                    ),
                  ),
                ),
                AppFormField(
                  label: 'Gender',
                  child: AppDropdownField<String>(
                    value: _gender,
                    items: choiceItems(const [
                      ('M', 'Male'),
                      ('F', 'Female'),
                      ('O', 'Other'),
                    ]),
                    onChanged: (v) => setState(() => _gender = v!),
                  ),
                ),
              ],
            ),
            AppFormSection(
              title: 'Access',
              children: [
                AppFormField(
                  label: 'Role',
                  child: AppDropdownField<String>(
                    value: _role,
                    helperText: _isSelf
                        ? 'Ask another admin to change your role'
                        : _role == 'ADMIN'
                        ? 'Admins manage accounts and see every record'
                        : null,
                    items: choiceItems(const [
                      ('EMPLOYEE', 'Employee'),
                      ('ADMIN', 'Admin'),
                    ]),
                    onChanged: _isSelf
                        ? null
                        : (v) => setState(() => _role = v!),
                  ),
                ),
                if (widget.existing == null)
                  PasswordFormField(
                    controller: _password,
                    labelText: 'Password',
                    helperText: 'At least $kMinPasswordLength characters',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
