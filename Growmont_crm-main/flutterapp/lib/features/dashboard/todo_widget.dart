import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class TodoWidget extends ConsumerStatefulWidget {
  const TodoWidget({super.key, required this.userId});

  final int userId;

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.note_alt_outlined, color: Colors.amber.shade800),
            const SizedBox(width: 8),
            Text(
              'Sticky Notes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Write your notes here...',
            filled: true,
            fillColor: Colors.yellow.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.amber.shade200),
            ),
          ),
          onChanged: _saveNotes,
        ),
      ],
    );
  }
}
