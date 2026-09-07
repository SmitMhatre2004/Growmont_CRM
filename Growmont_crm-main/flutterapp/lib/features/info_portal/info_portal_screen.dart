import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/interaction.dart';
import '../../models/sale.dart';
import '../auth/auth_provider.dart';
import '../interactions/widgets/add_interaction_modal.dart';
import '../sales/widgets/add_sale_modal.dart';

class InfoPortalScreen extends ConsumerStatefulWidget {
  const InfoPortalScreen({super.key});

  @override
  ConsumerState<InfoPortalScreen> createState() => _InfoPortalScreenState();
}

class _InfoPortalScreenState extends ConsumerState<InfoPortalScreen> {
  List<Sale> _sales = [];
  List<Interaction> _interactions = [];
  String _search = '';
  String _activeTab = 'interactions';
  bool _loading = true;
  bool _showFilters = false;

  final _dateFromController = TextEditingController();
  final _dateToController = TextEditingController();
  final _clientController = TextEditingController();
  final _salesRepController = TextEditingController();
  String _productFilter = '';
  String _priorityFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dateFromController.dispose();
    _dateToController.dispose();
    _clientController.dispose();
    _salesRepController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final results = await Future.wait([api.getSales(), api.getInteractions()]);
      if (mounted) {
        setState(() {
          _sales = results[0] as List<Sale>;
          _interactions = results[1] as List<Interaction>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Sale> get _filteredSales {
    return _sales.where((s) {
      if (_search.isNotEmpty &&
          !s.clientName.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      if (_dateFromController.text.isNotEmpty && s.date.compareTo(_dateFromController.text) < 0) {
        return false;
      }
      if (_dateToController.text.isNotEmpty && s.date.compareTo(_dateToController.text) > 0) {
        return false;
      }
      if (_clientController.text.isNotEmpty &&
          !s.clientName.toLowerCase().contains(_clientController.text.toLowerCase())) {
        return false;
      }
      if (_salesRepController.text.isNotEmpty &&
          !(s.salesRepName?.toLowerCase().contains(_salesRepController.text.toLowerCase()) ?? false)) {
        return false;
      }
      if (_productFilter.isNotEmpty && s.product != _productFilter) return false;
      return true;
    }).toList();
  }

  List<Interaction> get _filteredInteractions {
    return _interactions.where((i) {
      if (_search.isNotEmpty &&
          !i.clientName.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      if (_dateFromController.text.isNotEmpty && i.date.compareTo(_dateFromController.text) < 0) {
        return false;
      }
      if (_dateToController.text.isNotEmpty && i.date.compareTo(_dateToController.text) > 0) {
        return false;
      }
      if (_clientController.text.isNotEmpty &&
          !i.clientName.toLowerCase().contains(_clientController.text.toLowerCase())) {
        return false;
      }
      if (_priorityFilter.isNotEmpty && i.priority != _priorityFilter) return false;
      return true;
    }).toList();
  }

  Future<void> _deleteSale(dynamic id) async {
    final ok = await _confirmDelete();
    if (!ok) return;
    await ref.read(apiServiceProvider).deleteSale(id);
    _load();
  }

  Future<void> _deleteInteraction(dynamic id) async {
    final ok = await _confirmDelete();
    if (!ok) return;
    await ref.read(apiServiceProvider).deleteInteraction(id);
    _load();
  }

  Future<bool> _confirmDelete() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete'),
            content: const Text('Are you sure you want to delete this record?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editSale(Sale sale) async {
    final user = ref.read(authProvider).user;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddSaleModal(existing: sale, currentUser: user),
    );
    if (saved == true) _load();
  }

  Future<void> _editInteraction(Interaction interaction) async {
    final user = ref.read(authProvider).user;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddInteractionModal(existing: interaction, currentUser: user),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Info Portal',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
          ),
          const SizedBox(height: 4),
          Text('Combined admin view', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _showFilters = !_showFilters),
                icon: Icon(_showFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
                tooltip: 'Filters',
              ),
            ],
          ),
          if (_showFilters) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _dateFromController,
                        decoration: const InputDecoration(labelText: 'Date From', hintText: 'YYYY-MM-DD'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _dateToController,
                        decoration: const InputDecoration(labelText: 'Date To', hintText: 'YYYY-MM-DD'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _clientController,
                        decoration: const InputDecoration(labelText: 'Client'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_activeTab == 'sales')
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _salesRepController,
                          decoration: const InputDecoration(labelText: 'Sales Rep'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    if (_activeTab == 'sales')
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _productFilter.isEmpty ? null : _productFilter,
                          decoration: const InputDecoration(labelText: 'Product'),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('All Products')),
                            ...productCategories
                                .where((c) => c.$1 != 'ALL')
                                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2))),
                          ],
                          onChanged: (v) => setState(() => _productFilter = v ?? ''),
                        ),
                      ),
                    if (_activeTab == 'interactions')
                      SizedBox(
                        width: 160,
                        child: DropdownButtonFormField<String>(
                          value: _priorityFilter.isEmpty ? null : _priorityFilter,
                          decoration: const InputDecoration(labelText: 'Priority'),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('All Priorities')),
                            DropdownMenuItem(value: 'HIGH', child: Text('High')),
                            DropdownMenuItem(value: 'MEDIUM', child: Text('Medium')),
                            DropdownMenuItem(value: 'LOW', child: Text('Low')),
                          ],
                          onChanged: (v) => setState(() => _priorityFilter = v ?? ''),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilterChip(
                label: const Text('Interactions'),
                selected: _activeTab == 'interactions',
                onSelected: (_) => setState(() => _activeTab = 'interactions'),
                selectedColor: AppColors.primaryGreen,
                labelStyle: TextStyle(color: _activeTab == 'interactions' ? Colors.white : null),
                checkmarkColor: Colors.white,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Sales'),
                selected: _activeTab == 'sales',
                onSelected: (_) => setState(() => _activeTab = 'sales'),
                selectedColor: AppColors.primaryGreen,
                labelStyle: TextStyle(color: _activeTab == 'sales' ? Colors.white : null),
                checkmarkColor: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    child: _activeTab == 'sales' ? _salesTable() : _interactionsTable(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _salesTable() {
    final items = _filteredSales;
    if (items.isEmpty) return const Center(child: Text('No sales found'));

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = items[i];
        return ListTile(
          title: Text(s.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${AppFormatters.formatDate(s.date)} • ${s.salesRepName ?? ''} • ${s.productDisplay ?? s.product} • ${AppFormatters.formatAmount(s.amount)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _editSale(s)),
              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteSale(s.id)),
            ],
          ),
        );
      },
    );
  }

  Widget _interactionsTable() {
    final items = _filteredInteractions;
    if (items.isEmpty) return const Center(child: Text('No interactions found'));

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        return ListTile(
          title: Text(item.clientName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${item.clientContact} • ${item.employeeName ?? ''} • ${AppFormatters.formatDate(item.followUpDate)} • ${item.priorityDisplay ?? item.priority}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue),
                onPressed: () => _editInteraction(item),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteInteraction(item.id),
              ),
            ],
          ),
        );
      },
    );
  }
}
