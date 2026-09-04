import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/employee.dart';

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
    _dob = e != null && e.dob.isNotEmpty ? DateTime.parse(e.dob) : DateTime(1990);
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.existing == null && _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password is required for new employees'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _loading = true);
    final formData = FormData.fromMap({
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'mobile_no': _mobile.text.trim(),
      'gender': _gender,
      'dob': AppFormatters.toApiDate(_dob),
      'role': _role,
      if (_password.text.isNotEmpty) 'password': _password.text,
      if (_avatar != null) 'avatar': await MultipartFile.fromFile(_avatar!.path),
    });

    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existing != null) {
        await api.updateEmployee(widget.existing!.id, formData);
      } else {
        await api.createEmployee(formData);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Material(
          child: Form(
            key: _formKey,
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.existing != null ? 'Edit Employee' : 'Add Employee',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
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
                          : const Icon(Icons.camera_alt, size: 32),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name *'), validator: (v) => v!.isEmpty ? 'Required' : null),
                TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email *'), validator: (v) => v!.isEmpty ? 'Required' : null),
                TextFormField(controller: _mobile, decoration: const InputDecoration(labelText: 'Mobile *'), validator: (v) => v!.isEmpty ? 'Required' : null),
                ListTile(
                  title: const Text('Date of Birth *'),
                  subtitle: Text(AppFormatters.formatDate(AppFormatters.toApiDate(_dob))),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _dob, firstDate: DateTime(1950), lastDate: DateTime.now());
                    if (d != null) setState(() => _dob = d);
                  },
                ),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('Male')),
                    DropdownMenuItem(value: 'F', child: Text('Female')),
                    DropdownMenuItem(value: 'O', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _gender = v!),
                ),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'EMPLOYEE', child: Text('Employee')),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                  ],
                  onChanged: (v) => setState(() => _role = v!),
                ),
                if (widget.existing == null)
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password *'),
                  ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _loading ? null : _submit, child: Text(_loading ? 'Saving...' : 'Save')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
