import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/api/endpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../models/sale.dart';
import '../../models/user.dart';
import '../auth/auth_provider.dart';
import 'widgets/add_sale_modal.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  List<Sale> _sales = [];
  String _selectedProduct = 'ALL';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(apiServiceProvider).getSales();
      if (mounted) setState(() { _sales = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('Failed to load sales');
      }
    }
  }

  List<Sale> get _filtered {
    if (_selectedProduct == 'ALL') return _sales;
    return _sales.where((s) => s.product == _selectedProduct).toList();
  }

  Future<void> _deleteSale(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sale'),
        content: const Text('Are you sure you want to delete this sale?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(apiServiceProvider).deleteSale(id);
      _showSuccess('Sale deleted');
      _loadSales();
    } catch (_) {
      _showError('Failed to delete sale');
    }
  }

  Future<void> _exportSales() async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/sales_export.xlsx';
      await ref.read(apiClientProvider).downloadFile(Endpoints.exportSales, path);
      await Share.shareXFiles([XFile(path)], text: 'Sales Export');
    } catch (_) {
      _showError('Export failed');
    }
  }

  Future<void> _importSales() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(result.files.single.path!),
      });
      await ref.read(apiServiceProvider).importSales(formData);
      _showSuccess('Import successful');
      _loadSales();
    } catch (_) {
      _showError('Import failed');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final user = ref.watch(authProvider).user;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Sales', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
              ),
              IconButton(onPressed: _exportSales, icon: const Icon(Icons.download), tooltip: 'Export'),
              IconButton(onPressed: _importSales, icon: const Icon(Icons.upload), tooltip: 'Import'),
              FilledButton.icon(
                onPressed: () => _showSaleModal(context, user),
                icon: const Icon(Icons.add),
                label: const Text('Add Sale'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 240, child: _filterPanel()),
                      const SizedBox(width: 16),
                      Expanded(child: _salesList()),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(height: 120, child: _filterPanel(horizontal: true)),
                      const SizedBox(height: 16),
                      Expanded(child: _salesList()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterPanel({bool horizontal = false}) {
    final children = productCategories.map((cat) {
      final count = cat.$1 == 'ALL'
          ? _sales.length
          : _sales.where((s) => s.product == cat.$1).length;
      final selected = _selectedProduct == cat.$1;
      return InkWell(
        onTap: () => setState(() => _selectedProduct = cat.$1),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue.withValues(alpha: 0.11) : null,
            border: selected ? const Border(left: BorderSide(color: AppColors.primaryBlue, width: 4)) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cat.$2, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text('$count sales', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filter by Product', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (horizontal)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: children.map((c) => SizedBox(width: 160, child: c)).toList()),
              )
            else
              Expanded(child: ListView(children: children)),
          ],
        ),
      ),
    );
  }

  Widget _salesList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_filtered.isEmpty) {
      return const Center(child: Text('No sales found'));
    }

    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final sale = _filtered[index];
          return _SaleListItem(
            sale: sale,
            onEdit: () => _showSaleModal(context, ref.read(authProvider).user, sale: sale),
            onDelete: () => _deleteSale(sale.id),
          );
        },
      ),
    );
  }

  Future<void> _showSaleModal(BuildContext context, AppUser? user, {Sale? sale}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddSaleModal(existing: sale, currentUser: user),
    );
    if (saved == true) _loadSales();
  }
}

class _SaleListItem extends StatelessWidget {
  const _SaleListItem({required this.sale, required this.onEdit, required this.onDelete});
  final Sale sale;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _field('Date', AppFormatters.formatDate(sale.date)),
                  _field('Client', sale.clientName),
                  _field('Product', sale.productDisplay ?? sale.product),
                  _field('Amount', AppFormatters.formatAmount(sale.amount)),
                  _field('Frequency', sale.frequencyDisplay ?? sale.frequency),
                  _field('Sales Rep', sale.salesRepName ?? ''),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: onDelete),
          ],
        ),
        if (sale.company.isNotEmpty || sale.scheme.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${sale.company} • ${sale.scheme}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
      ],
    );
  }

  Widget _field(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
