import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

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
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final stamp = '\n[$dateStr] ';
    final sel = _controller.selection;
    if (sel.isValid && sel.start >= 0) {
      final current = _controller.text;
      final newText = current.replaceRange(sel.start, sel.end, stamp);
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(
        offset: sel.start + stamp.length,
      );
    } else {
      _controller.text = '${_controller.text}$stamp';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final showTextLabel = constraints.maxWidth >= 340;
            return Row(
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  color: AppColors.textCaption,
                  size: AppSizing.iconMd,
                ),
                const SizedBox(width: AppSpacing.xs),
                const Expanded(
                  child: Text(
                    'Sticky Notes',
                    style: AppTypography.sectionTitle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: 'Add Timestamp',
                  child: InkWell(
                    onTap: _insertTimestamp,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: AppSizing.iconXs,
                            color: AppColors.link,
                          ),
                          if (showTextLabel) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            const Text(
                              '+Time',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.link,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Tooltip(
                  message: 'Copy Notes',
                  child: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: AppSizing.iconXs),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _copyToClipboard,
                  ),
                ),
                Tooltip(
                  message: 'Clear Notes',
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: AppSizing.iconXs,
                      color: AppColors.danger,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _clearNotes,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          maxLines: 6,
          // An ordinary input on an ordinary card: the notes pad is not a
          // state, so it does not get to own a colour.
          style: AppTypography.bodySecondary,
          decoration: InputDecoration(
            hintText: 'Write your notes here...',
            hintStyle: AppTypography.bodySecondary.copyWith(
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.all(AppSpacing.md),
            border: const OutlineInputBorder(
              borderRadius: AppRadius.brMd,
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: AppRadius.brMd,
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: AppRadius.brMd,
              borderSide: BorderSide(
                color: AppColors.primaryBlue,
                width: AppSizing.borderWidthFocus,
              ),
            ),
          ),
          onChanged: _saveNotes,
        ),
      ],
    );
  }
}
