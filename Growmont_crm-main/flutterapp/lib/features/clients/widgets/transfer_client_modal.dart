import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/client.dart';
import '../../../models/client_transfer.dart';
import '../../../models/employee.dart';
import '../../../models/user.dart';
import '../../../shared/widgets/app_form.dart';
import '../../../shared/widgets/app_modal_shell.dart';

class TransferClientModal extends ConsumerStatefulWidget {
  const TransferClientModal({
    super.key,
    required this.client,
    required this.currentUser,
    this.onTransferred,
  });

  final Client client;
  final AppUser? currentUser;
  final ValueChanged<ClientTransfer>? onTransferred;

  @override
  ConsumerState<TransferClientModal> createState() => _TransferClientModalState();
}

class _TransferClientModalState extends ConsumerState<TransferClientModal> {
  final _formKey = GlobalKey<FormState>();
  String? _targetEmployeeId;
  String? _reason;
  final _customReasonController = TextEditingController();
  final _newReasonController = TextEditingController();
  final _notesController = TextEditingController();
  List<EmployeeDropdown> _employees = [];
  List<String> _reasons = [];
  bool _loadingEmployees = true;
  bool _showAddReasonField = false;
  bool _savingNewReason = false;
  bool _submitting = false;

  static const String _addNewReasonMarker = '__ADD_NEW_REASON__';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _loadReasons();
  }

  @override
  void dispose() {
    _customReasonController.dispose();
    _newReasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isAdmin => widget.currentUser?.isAdmin ?? false;

  bool get _canTransfer {
    if (_isAdmin) return true;
    final currentUid = widget.currentUser?.id;
    if (currentUid == null || currentUid.isEmpty) return false;
    // An employee can ONLY transfer their own client
    return widget.client.employeeId == currentUid;
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await ref.read(apiServiceProvider).getEmployeesDropdown();
      if (mounted) {
        setState(() {
          // Filter out the current owner so we can't transfer to the same person
          _employees = list.where((e) {
            final isCurrentOwner = e.id == widget.client.employeeId;
            final isSelf = !_isAdmin && e.id == widget.currentUser?.id;
            return !isCurrentOwner && !isSelf;
          }).toList();
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  Future<void> _loadReasons() async {
    try {
      final list = await ref.read(apiServiceProvider).getTransferReasons();
      if (mounted) {
        setState(() {
          _reasons = list;
          if (_reason != null && !_reasons.contains(_reason)) {
            _reason = _reasons.isNotEmpty ? _reasons.first : null;
          } else if (_reason == null && _reasons.isNotEmpty) {
            _reason = _reasons.first;
          }
        });
      }
    } catch (_) {
      // Leave the list empty; the dropdown still offers "create a reason".
    }
  }

  Future<void> _saveAndSelectNewReason() async {
    final text = _newReasonController.text.trim();
    if (text.isEmpty) return;

    setState(() => _savingNewReason = true);

    try {
      final api = ref.read(apiServiceProvider);
      await api.saveTransferReason(text);

      if (mounted) {
        setState(() {
          if (!_reasons.contains(text)) {
            _reasons.insert(0, text);
          }
          _reason = text;
          _showAddReasonField = false;
          _savingNewReason = false;
        });
        _newReasonController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added and saved "$text" to transfer reasons.'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!_reasons.contains(text)) {
            _reasons.insert(0, text);
          }
          _reason = text;
          _showAddReasonField = false;
          _savingNewReason = false;
        });
        _newReasonController.clear();
      }
    }
  }

  Future<void> _submitTransfer() async {
    if (!_canTransfer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not authorized to transfer this client.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if (_targetEmployeeId == null || _targetEmployeeId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a recipient employee.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final targetEmployee = _employees.firstWhere(
      (e) => e.id == _targetEmployeeId,
      orElse: () => EmployeeDropdown(id: _targetEmployeeId!, name: 'Staff', role: 'EMPLOYEE'),
    );

    var finalReason = (_reason ?? '').trim();
    final typedNewReason = _newReasonController.text.trim();
    if (finalReason.isEmpty && typedNewReason.isNotEmpty) {
      finalReason = typedNewReason;
    } else if (finalReason == 'Other' && _customReasonController.text.trim().isNotEmpty) {
      finalReason = _customReasonController.text.trim();
    }

    if (finalReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or create a transfer reason.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final fromEmpName = widget.client.employeeName?.isNotEmpty == true
        ? widget.client.employeeName!
        : (widget.client.employeeId.isNotEmpty ? widget.client.employeeId : 'Unassigned');

    setState(() => _submitting = true);

    try {
      final api = ref.read(apiServiceProvider);

      // Save custom reason permanently if user specified one
      if (finalReason.isNotEmpty && !_reasons.contains(finalReason)) {
        try {
          await api.saveTransferReason(finalReason);
        } catch (_) {}
      }

      final transfer = await api.transferClient(
        clientId: widget.client.id,
        clientName: widget.client.name,
        fromEmployeeId: widget.client.employeeId,
        fromEmployeeName: fromEmpName,
        toEmployeeId: targetEmployee.id,
        toEmployeeName: targetEmployee.name,
        transferredById: widget.currentUser?.id ?? '',
        transferredByName: widget.currentUser?.name ?? 'Admin',
        transferredByRole: _isAdmin ? 'ADMIN' : 'EMPLOYEE',
        reason: finalReason,
        notes: _notesController.text.trim(),
      );

      widget.onTransferred?.call(transfer);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transferred ${widget.client.name} to ${targetEmployee.name}',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: 'Transfer Client Ownership',
      subtitle: 'Hand ${widget.client.name} over to another employee.',
      footer: _canTransfer
          ? AppFormActions(
              submitLabel: 'Confirm Transfer',
              busyLabel: 'Transferring...',
              busy: _submitting,
              icon: Icons.swap_horiz_rounded,
              onSubmit: _submitTransfer,
              onCancel: () => Navigator.of(context).pop(false),
            )
          : Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
            ),
      child: !_canTransfer ? _buildUnauthorizedView() : _buildTransferForm(),
    );
  }

  Widget _buildUnauthorizedView() {
    final currentOwner = widget.client.employeeName?.isNotEmpty == true
        ? widget.client.employeeName!
        : 'another staff member';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_person_outlined,
            color: AppColors.warning,
            size: AppSizing.iconXl,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transfer Restricted', style: AppTypography.itemTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'As an employee, you can only transfer clients currently '
                  'assigned to you. This client is currently assigned to '
                  '$currentOwner.',
                  style: AppTypography.bodySecondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Only an administrator can transfer any client between '
                  'employees.',
                  style: AppTypography.captionSemibold.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final currentOwnerName = widget.client.employeeName?.isNotEmpty == true
        ? widget.client.employeeName!
        : (widget.client.employeeId.isNotEmpty
              ? widget.client.employeeId
              : 'Unassigned');
    final target = _employees
        .where((e) => e.id == _targetEmployeeId)
        .firstOrNull;
    final accent = _isAdmin ? AppColors.primaryGreen : AppColors.primaryBlue;

    Widget assignee(String label, String name, {required bool highlight}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xs),
          Text(
            name,
            style: AppTypography.bodyPrimary.copyWith(
              color: highlight ? AppColors.primaryBlue : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceHeader,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: AppSizing.avatarMd / 2,
                backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.12),
                child: Text(
                  widget.client.name.isNotEmpty
                      ? widget.client.name[0].toUpperCase()
                      : 'C',
                  style: AppTypography.itemTitle.copyWith(
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.client.name,
                      style: AppTypography.itemTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.client.contactNumber.isNotEmpty)
                      Text(
                        widget.client.contactNumber,
                        style: AppTypography.itemSubtitle,
                      ),
                  ],
                ),
              ),
              Container(
                padding: AppLayout.badgePadding,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: AppRadius.brSm,
                ),
                child: Text(
                  _isAdmin ? 'Admin Transfer' : 'Staff Handover',
                  style: AppTypography.badge.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: assignee(
                  'Current assignee',
                  currentOwnerName,
                  highlight: false,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.primaryBlue,
                  size: AppSizing.iconLg,
                ),
              ),
              Expanded(
                child: assignee(
                  'New assignee',
                  target?.name ?? 'Not selected',
                  highlight: target != null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransferForm() {
    return Form(
      key: _formKey,
      child: AppFormColumn(
        gap: kFormSectionGap,
        children: [
          _buildSummary(),
          AppFormColumn(
            children: [
              AppFormField(
                label: 'Transfer to',
                child: AppDropdownField<String>(
                  key: ValueKey(
                    'transfer_to_${_targetEmployeeId}_${_employees.length}',
                  ),
                  value: _targetEmployeeId,
                  hint: 'Select staff member',
                  helperText: _loadingEmployees
                      ? 'Loading staff...'
                      : _employees.isEmpty
                      ? 'No other eligible staff members found to receive '
                            'this client.'
                      : null,
                  items: [
                    for (final e in _employees)
                      DropdownMenuItem(
                        value: e.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              e.role.toUpperCase(),
                              style: AppTypography.overline,
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _loadingEmployees
                      ? null
                      : (v) => setState(() => _targetEmployeeId = v),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Select who receives this client'
                      : null,
                ),
              ),
              AppFormField(
                label: 'Transfer reason',
                trailing: TextButton.icon(
                  onPressed: () => setState(
                    () => _showAddReasonField = !_showAddReasonField,
                  ),
                  style: TextButton.styleFrom(
                    // Kept to about the label's height so this row doesn't
                    // push its dropdown further down than other fields.
                    minimumSize: const Size(0, AppSpacing.xxl),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    textStyle: AppTypography.buttonSmall,
                  ),
                  icon: Icon(
                    _showAddReasonField ? Icons.close : Icons.add,
                    size: AppSizing.iconSm,
                  ),
                  label: Text(
                    _showAddReasonField ? 'Cancel' : 'Add Custom Reason',
                  ),
                ),
                child: AppFormColumn(
                  gap: AppSpacing.sm,
                  children: [
                    if (_showAddReasonField) _buildNewReasonBox(),
                    AppDropdownField<String>(
                      key: ValueKey(
                        'transfer_reason_${_reason}_${_reasons.length}',
                      ),
                      value: _reasons.contains(_reason) ? _reason : null,
                      hint: 'Select or create a reason',
                      items: [
                        for (final r in _reasons)
                          DropdownMenuItem(
                            value: r,
                            child: Text(r, overflow: TextOverflow.ellipsis),
                          ),
                        DropdownMenuItem(
                          value: _addNewReasonMarker,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.add,
                                size: AppSizing.iconSm,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Create New Reason...',
                                style: AppTypography.bodyPrimary.copyWith(
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == _addNewReasonMarker) {
                          setState(() => _showAddReasonField = true);
                        } else if (v != null) {
                          setState(() {
                            _reason = v;
                            _showAddReasonField = false;
                          });
                        }
                      },
                      validator: (v) {
                        if ((_reason == null || _reason!.isEmpty) &&
                            _newReasonController.text.trim().isEmpty) {
                          return 'Select or create a transfer reason';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              if (_reason == 'Other')
                AppFormField(
                  label: 'Specify reason',
                  child: TextFormField(
                    controller: _customReasonController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Why this client is moving (will be saved)',
                    ),
                    validator: (v) =>
                        _reason == 'Other' && (v == null || v.trim().isEmpty)
                        ? 'Enter a reason'
                        : null,
                  ),
                ),
              AppFormField(
                label: 'Handover notes',
                optional: true,
                child: TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'Open follow-ups, portfolio preferences, anything the '
                        'new owner should know',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Inline box for typing a brand-new reason, saved for the whole team.
  Widget _buildNewReasonBox() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceHeader,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('New Reason Title', style: AppTypography.fieldLabel),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('new_reason_field'),
                  controller: _newReasonController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Relocated to Pune branch',
                  ),
                  onFieldSubmitted: (_) => _saveAndSelectNewReason(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _savingNewReason ? null : _saveAndSelectNewReason,
                child: Text(_savingNewReason ? 'Saving...' : 'Save & Select'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Saved for future transfers across your team.',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}
