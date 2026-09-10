import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';
import '../../../core/config/app_config.dart';

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
    _role = e?.role ?? 'EMPLOYEE';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.existing == null && _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password is required for new employees'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

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
      if (widget.existing != null) {
        await api.updateEmployee(widget.existing!.id, map);
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
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.modalMaxWidth),
        child: SingleChildScrollView(
          padding: AppLayout.modalPadding,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.existing != null
                          ? 'Edit Employee'
                          : 'Add Employee',
                      style: AppTypography.sectionTitle,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
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
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    helperText:
                        'Username is enough — $kAllowedEmailDomain '
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
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(
                      value: 'EMPLOYEE',
                      child: Text('Employee'),
                    ),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                  ],
                  onChanged: (v) => setState(() => _role = v!),
                ),
                if (widget.existing == null) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password *',
                      helperText: 'At least 6 characters',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Password is required';
                      }
                      if (v.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
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
        ),
      ),
    );
  }
}
