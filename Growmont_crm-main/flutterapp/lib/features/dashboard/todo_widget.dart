import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class TodoWidget extends ConsumerStatefulWidget {
  const TodoWidget({super.key, this.userId});

  final dynamic userId;

  @override
  ConsumerState<TodoWidget> createState() => _TodoWidgetState();
}

class _TodoWidgetState extends ConsumerState<TodoWidget> {
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final notes = await ref.read(tokenStorageProvider).getStickyNotes();
    if (notes != null) _controller.text = notes;
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveNotes(String value) async {
    await ref.read(tokenStorageProvider).saveStickyNotes(value);
  }

  void _insertTimestamp() {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final stamp = '\n[$dateStr] ';
    final sel = _controller.selection;
    if (sel.isValid && sel.start >= 0) {
      final current = _controller.text;
      final newText = current.replaceRange(sel.start, sel.end, stamp);
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: sel.start + stamp.length);
    } else {
      _controller.text = '${_controller.text}$stamp';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    }
    _saveNotes(_controller.text);
  }

  void _copyToClipboard() {
    if (_controller.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notes copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearNotes() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Sticky Notes?'),
        content: const Text('Are you sure you want to clear all sticky notes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _controller.clear();
              _saveNotes('');
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.note_alt_outlined, color: Colors.grey.shade800, size: 18),
            const SizedBox(width: 6),
            const Text(
              'Sticky Notes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: 'Add Timestamp',
              child: InkWell(
                onTap: _insertTimestamp,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 2),
                      Text('+Time', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Copy Notes',
              child: IconButton(
                icon: const Icon(Icons.copy_outlined, size: 15),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: _copyToClipboard,
              ),
            ),
            Tooltip(
              message: 'Clear Notes',
              child: IconButton(
                icon: Icon(Icons.delete_outline, size: 15, color: Colors.red.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: _clearNotes,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLines: 6,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Write your notes here...',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade500, width: 1.5),
            ),
          ),
          onChanged: _saveNotes,
        ),
      ],
    );
  }
}
