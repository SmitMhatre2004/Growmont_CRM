import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/employee.dart';
import '../../../models/interaction.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/app_form.dart';
import '../../../shared/widgets/app_modal_shell.dart';

/// Modal dialog providing a focused reading experience for an [Interaction].
///
/// Designed with an 80/20 visual hierarchy: 80% visual weight and emphasis
/// is placed on the discussion notes with generous typography, selectable text,
/// word/character stats, and quick copying. The remaining 20% displays all
/// personal and client metadata (client, phone, rep, dates, follow-up, priority).
///
/// Also provides an integrated Edit Form tab where the 80% notes prominence is
/// preserved with an expansive multi-line editor.
class InteractionDetailModal extends ConsumerStatefulWidget {
  const InteractionDetailModal({
    super.key,
    required this.interaction,
    this.currentUser,
    this.onUpdated,
    this.initialEdit = false,
  });

  final Interaction interaction;
  final AppUser? currentUser;
  final VoidCallback? onUpdated;
  final bool initialEdit;

  @override
  ConsumerState<InteractionDetailModal> createState() =>
      _InteractionDetailModalState();
}

class _InteractionDetailModalState
    extends ConsumerState<InteractionDetailModal> {
  late Interaction _interaction;
  late bool _isEditing;

  // Edit form controllers & state
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _notesController;
  late DateTime _date;
  late bool _hasFollowUp;
  late DateTime _followUpDate;
  late TimeOfDay _followUpTime;
  late String _priority;
  String? _employeeId;
  String? _clientId;
  List<EmployeeDropdown> _employees = [];
  List<Client> _clients = [];
  bool _loadingClients = false;
  bool _saving = false;
  bool _isEmployeeRole = false;

  @override
  void initState() {
    super.initState();
    _interaction = widget.interaction;
    _isEditing = widget.initialEdit;

    _notesController = TextEditingController(
      text: _interaction.discussionNotes,
    );
    _date = DateTime.tryParse(_interaction.date) ?? DateTime.now();
    final existingFollowUp = DateTime.tryParse(_interaction.followUpDate);
    _hasFollowUp = existingFollowUp != null;
    _followUpDate = existingFollowUp ?? _date.add(const Duration(days: 2));
    if (_interaction.followUpTime.isNotEmpty) {
      final timeParts = _interaction.followUpTime.split(':');
      _followUpTime = TimeOfDay(
        hour: int.tryParse(timeParts[0]) ?? 10,
        minute: timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0,
      );
    } else {
      _followUpTime = const TimeOfDay(hour: 10, minute: 0);
    }
    _priority = _interaction.priority.isNotEmpty
        ? _interaction.priority.toUpperCase()
        : 'MEDIUM';
    _isEmployeeRole = widget.currentUser?.role == UserRole.employee;
    _employeeId = _interaction.employee.isNotEmpty
        ? _interaction.employee
        : (_isEmployeeRole ? widget.currentUser?.id : null);
    _clientId = _interaction.clientId;

    if (_isEditing) {
      _loadDropdowns();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _loadDropdowns() {
    _loadEmployees();
    if (_isEmployeeRole) {
      _loadClientsFor(_employeeId);
    }
  }

  Future<void> _loadEmployees() async {
    if (_isEmployeeRole) return;
    try {
      final list = await ref.read(apiServiceProvider).getEmployeesDropdown();
      if (mounted) {
        setState(() {
          _employees = list;
          if (_employeeId == null ||
              !_employees.any((emp) => emp.id == _employeeId)) {
            if (_employees.isNotEmpty) {
              final userInList = _employees.any(
                (emp) => emp.id == widget.currentUser?.id,
              );
              _employeeId = userInList
                  ? widget.currentUser?.id
                  : _employees.first.id;
            }
          }
        });
      }
    } catch (_) {}
    _loadClientsFor(_employeeId);
  }

  Future<void> _loadClientsFor(String? employeeId) async {
    if (employeeId == null) {
      setState(() {
        _clients = [];
        _clientId = null;
      });
      return;
    }
    setState(() => _loadingClients = true);
    try {
      final list = await ref
          .read(apiServiceProvider)
          .getClients(employeeId: employeeId);
      if (mounted) {
        setState(() {
          _clients = list;
          _loadingClients = false;
          if (_clientId == null || !_clients.any((c) => c.id == _clientId)) {
            // Keep existing client if present in the loaded list
            if (_interaction.clientId != null &&
                _clients.any((c) => c.id == _interaction.clientId)) {
              _clientId = _interaction.clientId;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  void _copyNotes() {
    final notes = _interaction.discussionNotes.trim();
    if (notes.isEmpty) return;
    Clipboard.setData(ClipboardData(text: notes));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Discussion notes copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyContact() {
    final contact = _interaction.clientContact.trim();
    if (contact.isEmpty) return;
    Clipboard.setData(ClipboardData(text: contact));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contact "$contact" copied to clipboard!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteInteraction() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Interaction'),
        content: const Text(
          'Are you sure you want to delete this interaction and its notes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await ref.read(apiServiceProvider).deleteInteraction(_interaction.id);
      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasFollowUp && _followUpDate.isBefore(_date)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Follow-up date cannot be before interaction date'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    String clientName = _interaction.clientName;
    String clientContact = _interaction.clientContact;
    if (_clientId != null && _clients.any((c) => c.id == _clientId)) {
      final matched = _clients.firstWhere((c) => c.id == _clientId);
      clientName = matched.name;
      clientContact = matched.contactNumber;
    }

    String? employeeName = _interaction.employeeName;
    if (_employeeId != null && _employees.any((e) => e.id == _employeeId)) {
      employeeName = _employees.firstWhere((e) => e.id == _employeeId).name;
    } else if (_isEmployeeRole) {
      employeeName = widget.currentUser?.name;
    }

    final payload = {
      'date': AppFormatters.toApiDate(_date),
      'client_name': clientName,
      if (_clientId != null) 'client_id': _clientId,
      'client_contact': clientContact,
      'employee': _employeeId ?? _interaction.employee,
      'employee_name': employeeName,
      'follow_up_date': _hasFollowUp
          ? AppFormatters.toApiDate(_followUpDate)
          : null,
      'follow_up_time': _hasFollowUp
          ? AppFormatters.toApiTime(_followUpTime)
          : null,
      'priority': _priority,
      'discussion_notes': _notesController.text.trim(),
    };

    try {
      final api = ref.read(apiServiceProvider);
      await api.updateInteraction(_interaction.id, payload);

      // Construct updated local model
      final updated = Interaction(
        id: _interaction.id,
        date: AppFormatters.toApiDate(_date),
        clientName: clientName,
        clientId: _clientId ?? _interaction.clientId,
        clientContact: clientContact,
        employee: _employeeId ?? _interaction.employee,
        employeeName: employeeName,
        followUpDate: _hasFollowUp ? AppFormatters.toApiDate(_followUpDate) : '',
        followUpTime: _hasFollowUp ? AppFormatters.toApiTime(_followUpTime) : '',
        priority: _priority,
        priorityDisplay: _priority,
        discussionNotes: _notesController.text.trim(),
      );

      setState(() {
        _interaction = updated;
        _isEditing = false;
        _saving = false;
      });

      widget.onUpdated?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Interaction notes and details updated successfully!',
            ),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // --- Helpers for badges & metrics ---

  Color _priorityColor(String p) {
    switch (p.trim().toUpperCase()) {
      case 'HIGH':
        return AppColors.danger;
      case 'MEDIUM':
        return AppColors.warning;
      case 'LOW':
      default:
        return AppColors.primaryBlue;
    }
  }

  Color _priorityBg(String p) {
    switch (p.trim().toUpperCase()) {
      case 'HIGH':
        return AppColors.dangerSoft;
      case 'MEDIUM':
        return AppColors.warningSoft;
      case 'LOW':
      default:
        return AppColors.surfaceHover;
    }
  }

  Widget _buildPriorityBadge(String priority) {
    final fg = _priorityColor(priority);
    final bg = _priorityBg(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  int get _wordCount {
    final text = _interaction.discussionNotes.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppLayout.isMobile(context);

    if (_isEditing) {
      // Editing uses the standard form width and footer so it matches the
      // Add Interaction form field for field.
      return AppModalShell(
        title: 'Edit Interaction',
        footer: AppFormActions(
          submitLabel: 'Save Changes',
          busy: _saving,
          onSubmit: _saveChanges,
          onCancel: () => setState(() => _isEditing = false),
        ),
        child: _buildEditMode(),
      );
    }

    return AppModalShell(
      maxWidth: 860.0,
      title: 'Client Interaction',
      child: isMobile
          ? ConstrainedBox(
              // Restrict height to 70% of the screen so it sits above the bottom nav
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.70,
              ),
              child: _buildReadMode(isMobile),
            )
          : _buildReadMode(isMobile),
    );
  }

  // =========================================================================
  // READ MODE (80% Weight on Notes, 20% on Personal Data)
  // =========================================================================

  Widget _buildReadMode(bool isMobile) {
    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPersonalDataCard(isMobile: true),
          const SizedBox(height: 8),
          Flexible(
            // Allows the notes section to take remaining space and scroll internally
            child: _buildNotesReadingCanvas(isMobile: true),
          ),
          const SizedBox(height: 8),
          _buildBottomActionsRow(isMobile: true),
        ],
      );
    }

    // Wide layout: Client & Metadata on the left (30%), Notes canvas on the right (70%)
    // Both cards have the exact same height via IntrinsicHeight & stretch
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left: Client & Metadata Rail
              Expanded(
                flex: 30,
                child: _buildPersonalDataCard(isMobile: false),
              ),
              const SizedBox(width: AppSpacing.lg),
              // Right: Dominant Notes Reading Canvas (70% weight)
              Expanded(
                flex: 70,
                child: _buildNotesReadingCanvas(isMobile: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildBottomActionsRow(isMobile: false),
      ],
    );
  }

  /// The star of the screen: large, spacious reading canvas for discussion notes.
  Widget _buildNotesReadingCanvas({required bool isMobile}) {
    final notes = _interaction.discussionNotes.trim();
    final hasNotes = notes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Notes Canvas Header: title, stats pill, copy button
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : AppSpacing.md,
              vertical: isMobile ? 6 : AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surfaceHeader,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg - 1),
              ),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.subject_rounded,
                    size: 16,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'DISCUSSION NOTES',
                    style: TextStyle(
                      fontFamily: AppTypography.display,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasNotes) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '$_wordCount words',
                      style: AppTypography.caption.copyWith(fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Copy Notes',
                    child: InkWell(
                      onTap: _copyNotes,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: AppTypography.captionSemibold.copyWith(
                                color: AppColors.primaryBlue,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Notes Content Body: Generous typography, readable, selectable
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 12.0 : AppSpacing.xl),
              child: hasNotes
                  ? SelectableText(
                      notes,
                      // Body copy: 14/20 Inter 500, like every other block of
                      // prose in the product.
                      style: AppTypography.bodyPrimary,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.note_alt_outlined,
                            size: 36,
                            color: AppColors.textMuted.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No notes recorded for this interaction',
                            style: AppTypography.itemSubtitle,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _isEditing = true);
                              _loadDropdowns();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Notes Now'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact personal data & interaction metadata rail (occupies ~20-25%).
  Widget _buildPersonalDataCard({required bool isMobile}) {
    final clientName = _interaction.clientName.isNotEmpty
        ? _interaction.clientName
        : 'Unknown Client';
    final clientContact = _interaction.clientContact.trim();
    final repName =
        _interaction.employeeName ??
        (_interaction.employee.isNotEmpty ? _interaction.employee : 'Staff');
    final hasFollowUp = _interaction.followUpDate.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12.0 : AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceHeader,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section tag
          const Text(
            'CLIENT & METADATA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: isMobile ? 8 : AppSpacing.md),

          // Client avatar + name + phone
          Row(
            children: [
              CircleAvatar(
                radius: isMobile ? 14 : 20,
                backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                child: Text(
                  clientName.isNotEmpty ? clientName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: isMobile ? 12 : 16,
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 8 : AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: AppTypography.tableCellStrong.copyWith(
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (clientContact.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              clientContact,
                              style: AppTypography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Copy contact',
                            child: InkWell(
                              onTap: _copyContact,
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: EdgeInsets.symmetric(
              vertical: isMobile ? 8 : AppSpacing.md,
            ),
            child: const Divider(height: 1, color: AppColors.border),
          ),

          // Priority
          _metadataRow(
            icon: Icons.flag_outlined,
            label: 'Priority',
            valueWidget: _buildPriorityBadge(_interaction.priority),
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 6 : AppSpacing.md),

          // Interaction Date
          _metadataRow(
            icon: Icons.calendar_today_outlined,
            label: 'Logged Date',
            value: AppFormatters.formatDate(_interaction.date),
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 6 : AppSpacing.md),

          // Follow-up
          _metadataRow(
            icon: Icons.notification_important_outlined,
            label: 'Follow-Up',
            value: hasFollowUp
                ? '${AppFormatters.formatDate(_interaction.followUpDate)}${_interaction.followUpTime.isNotEmpty ? ' • ${AppFormatters.formatTime(_interaction.followUpTime)}' : ''}'
                : 'None scheduled',
            isMobile: isMobile,
          ),
          SizedBox(height: isMobile ? 6 : AppSpacing.md),

          // Representative
          _metadataRow(
            icon: Icons.badge_outlined,
            label: 'Logged By',
            value: repName,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _metadataRow({
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
    bool isMobile = false,
  }) {
    if (isMobile) {
      // Compact horizontal layout for mobile to save vertical space
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          SizedBox(
            width: 80, // Fixed width for labels to align values neatly
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  valueWidget ??
                  Text(
                    value ?? '—',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
            ),
          ),
        ],
      );
    }

    // Original spacious layout for desktop/tablet
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              valueWidget ??
                  Text(
                    value ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionsRow({required bool isMobile}) {
    if (isMobile) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                setState(() => _isEditing = true);
                _loadDropdowns();
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _deleteInteraction,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              side: const BorderSide(color: AppColors.border),
            ),
            child: const Icon(
              Icons.delete_outline,
              size: 16,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 36),
              side: const BorderSide(color: AppColors.border),
            ),
            child: const Text('Close', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _deleteInteraction,
          icon: const Icon(
            Icons.delete_outline,
            size: AppSizing.iconSm,
            color: AppColors.danger,
          ),
          label: const Text(
            'Delete',
            style: TextStyle(color: AppColors.danger),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.icon(
          onPressed: () {
            setState(() => _isEditing = true);
            _loadDropdowns();
          },
          icon: const Icon(Icons.edit_outlined, size: AppSizing.iconSm),
          label: const Text('Edit Interaction'),
        ),
      ],
    );
  }

  // =========================================================================
  // EDIT MODE - the same form, fields and order as Add Interaction
  // =========================================================================

  Widget _buildEditMode() {
    return Form(
      key: _formKey,
      child: AppFormColumn(
        gap: kFormSectionGap,
        children: [
          AppFormSection(
            title: 'Client',
            children: [
              AppFormField(
                label: 'Employee',
                child: _isEmployeeRole || _employees.isEmpty
                    ? AppReadOnlyField(
                        value: _isEmployeeRole
                            ? widget.currentUser?.name ?? ''
                            : _interaction.employeeName ?? '',
                      )
                    : AppDropdownField<String>(
                        key: ValueKey(
                          'edit_employee_${_employeeId}_${_employees.length}',
                        ),
                        value: _employees.any((e) => e.id == _employeeId)
                            ? _employeeId
                            : null,
                        hint: 'Select employee',
                        items: [
                          for (final e in _employees)
                            DropdownMenuItem(
                              value: e.id,
                              child: Text(
                                e.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _employeeId = v);
                          _loadClientsFor(v);
                        },
                      ),
              ),
              AppFormField(
                label: 'Client',
                child: _clients.isEmpty
                    ? AppReadOnlyField(
                        value: _interaction.clientName,
                        helperText: _loadingClients ? 'Loading...' : null,
                      )
                    : AppDropdownField<String>(
                        key: ValueKey(
                          'edit_client_${_clientId}_${_clients.length}',
                        ),
                        value: _clients.any((c) => c.id == _clientId)
                            ? _clientId
                            : null,
                        hint: 'Select client',
                        items: [
                          for (final c in _clients)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _clientId = v),
                      ),
              ),
            ],
          ),
          AppFormSection(
            title: 'Interaction',
            children: [
              modalFieldPair(
                context,
                AppFormField(
                  label: 'Interaction date',
                  child: AppDateField(
                    value: _date,
                    onChanged: (d) => setState(() => _date = d),
                  ),
                ),
                AppFormField(
                  label: 'Priority',
                  child: AppDropdownField<String>(
                    key: ValueKey('edit_priority_$_priority'),
                    value: _priority,
                    items: choiceItems(priorityChoices),
                    onChanged: (v) {
                      if (v != null) setState(() => _priority = v);
                    },
                  ),
                ),
              ),
              AppFormField(
                label: 'Discussion notes',
                optional: true,
                child: TextFormField(
                  controller: _notesController,
                  autofocus: true,
                  minLines: 6,
                  maxLines: 16,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'What was discussed, decisions, next steps',
                  ),
                ),
              ),
            ],
          ),
          AppToggleSection(
            title: 'Follow-up',
            subtitle: 'Set a date to follow up with this client',
            value: _hasFollowUp,
            onChanged: (v) => setState(() {
              _hasFollowUp = v;
              if (v && _followUpDate.isBefore(_date)) _followUpDate = _date;
            }),
            child: modalFieldPair(
              context,
              AppFormField(
                label: 'Follow-up date',
                child: AppDateField(
                  value: _followUpDate,
                  onChanged: (d) => setState(() => _followUpDate = d),
                ),
              ),
              AppFormField(
                label: 'Follow-up time',
                child: AppTimeField(
                  value: _followUpTime,
                  onChanged: (t) => setState(() => _followUpTime = t),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
