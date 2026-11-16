import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client_note.dart';
import '../../auth/auth_provider.dart';

/// "Notes" card on a client's detail screen: a short bullet list (newest
/// first) plus a compact add field. Authors can delete their own notes;
/// admins can delete any.
class ClientNotesSection extends ConsumerStatefulWidget {
  const ClientNotesSection({
    super.key,
    required this.clientId,
    required this.clientOwnerId,
  });

  final String clientId;
  final String clientOwnerId;

  @override
  ConsumerState<ClientNotesSection> createState() => _ClientNotesSectionState();
}

class _ClientNotesSectionState extends ConsumerState<ClientNotesSection> {
  final _controller = TextEditingController();
  late final FocusNode _focus;
  Stream<List<ClientNote>>? _stream;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onKey);
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= ref.read(apiServiceProvider).streamClientNotes(widget.clientId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_saving && ClientNote.validate(_controller.text) != null;

  /// Enter submits; Shift+Enter falls through to insert a newline.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      if (_canSubmit) _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submit() async {
    final user = ref.read(authProvider).user;
    final text = ClientNote.validate(_controller.text);
    if (user == null || text == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(apiServiceProvider)
          .createClientNote(
            clientId: widget.clientId,
            clientOwnerId: widget.clientOwnerId,
            text: text,
            authorId: user.id,
            authorName: user.name,
          );
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not add note')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete(ClientNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).deleteClientNote(note.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not delete note')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Notes', style: AppTypography.cardTitle),
              const SizedBox(height: AppSpacing.sm),
              StreamBuilder<List<ClientNote>>(
                stream: _stream,
                builder: (context, snapshot) {
                  final notes = snapshot.data ?? const <ClientNote>[];
                  if (notes.isEmpty) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    return const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        'No notes',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in notes)
                        _noteTile(
                          note,
                          canDelete:
                              user != null &&
                              (user.isAdmin || note.authorId == user.id),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  );
                },
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(ClientNote.maxLength),
                      ],
                      style: AppTypography.bodySecondary.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Add a note',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    key: const ValueKey('add-note'),
                    tooltip: 'Add note',
                    onPressed: _canSubmit ? _submit : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteTile(ClientNote note, {required bool canDelete}) {
    final who = note.authorName.isEmpty ? 'Unknown' : note.authorName;
    final when = DateFormat('d MMM yyyy').format(note.createdAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ${note.text}', style: AppTypography.bodyPrimary),
                Text('$who · $when', style: AppTypography.caption),
              ],
            ),
          ),
          if (canDelete)
            InkResponse(
              key: ValueKey('delete-note-${note.id}'),
              onTap: () => _confirmDelete(note),
              radius: 16,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  semanticLabel: 'Delete note',
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
