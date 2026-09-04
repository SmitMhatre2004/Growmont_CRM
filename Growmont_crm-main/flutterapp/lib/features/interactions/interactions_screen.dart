import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/api/endpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../models/interaction.dart';
import '../../models/user.dart';
import '../auth/auth_provider.dart';
import 'widgets/add_interaction_modal.dart';

class InteractionsScreen extends ConsumerStatefulWidget {
  const InteractionsScreen({super.key});

  @override
  ConsumerState<InteractionsScreen> createState() => _InteractionsScreenState();
}

class _InteractionsScreenState extends ConsumerState<InteractionsScreen> {
  List<Interaction> _interactions = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(apiServiceProvider).getInteractions();
      if (mounted) setState(() { _interactions = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Interaction> get _filtered {
    if (_search.isEmpty) return _interactions;
    final q = _search.toLowerCase();
    return _interactions.where((i) =>
        i.clientName.toLowerCase().contains(q) ||
        i.clientContact.contains(q) ||
        (i.employeeName?.toLowerCase().contains(q) ?? false)).toList();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Interaction'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteInteraction(id);
    _load();
  }

  Future<void> _export() async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/interactions_export.xlsx';
      await ref.read(apiClientProvider).downloadFile(Endpoints.exportInteractions, path);
      await Share.shareXFiles([XFile(path)]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result?.files.single.path == null) return;
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(result!.files.single.path!),
      });
      await ref.read(apiServiceProvider).importInteractions(formData);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Interactions',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
              ),
              IconButton(onPressed: _export, icon: const Icon(Icons.download)),
              IconButton(onPressed: _import, icon: const Icon(Icons.upload)),
              FilledButton.icon(
                onPressed: () => _showModal(user),
                icon: const Icon(Icons.add),
                label: const Text('Add Interaction'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search clients...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    child: _filtered.isEmpty
                        ? const Center(child: Text('No interactions found'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, i) {
                              final item = _filtered[i];
                              return ListTile(
                                title: Text(item.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${item.clientContact} • Follow-up: ${AppFormatters.formatDate(item.followUpDate)} ${AppFormatters.formatTime(item.followUpTime)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(item.priorityDisplay ?? item.priority, style: const TextStyle(fontSize: 11)),
                                      backgroundColor: priorityBackgroundColor(item.priority),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showModal(user, existing: item),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _delete(item.id),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModal(AppUser? user, {Interaction? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddInteractionModal(existing: existing, currentUser: user),
    );
    if (saved == true) _load();
  }
}
