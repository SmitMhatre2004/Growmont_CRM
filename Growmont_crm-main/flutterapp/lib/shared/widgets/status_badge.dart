import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A status badge: 22h, radius 6, 11/600, and always a dot plus a word.
///
/// Colour never works alone in this product. Someone who cannot separate the
/// green pill from the amber one still reads "Won" and "Follow-up due", so the
/// dot is an accent on the label rather than a replacement for it.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  /// Sale closed, payment received, active client.
  const StatusBadge.won({super.key, this.label = 'Won'})
    : tone = AppStatus.won;

  /// Needs attention today; nothing is broken yet.
  const StatusBadge.followUp({super.key, this.label = 'Follow-up due'})
    : tone = AppStatus.followUp;

  /// Overdue, failed, destructive.
  const StatusBadge.overdue({super.key, this.label = 'Overdue'})
    : tone = AppStatus.overdue;

  /// New lead, neutral notice, sync in progress.
  const StatusBadge.fresh({super.key, this.label = 'New'})
    : tone = AppStatus.fresh;

  /// Interactions only: calls, chats, meetings.
  const StatusBadge.chat({super.key, required this.label})
    : tone = AppStatus.chat;

  /// Archived, transferred, dismissed.
  const StatusBadge.inactive({super.key, required this.label})
    : tone = AppStatus.inactive;

  final String label;
  final StatusTone tone;

  /// The dot is 6pt so it reads as punctuation next to 11pt text rather than
  /// as a second element competing with it.
  static const double _dotSize = 6;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: AppRadius.brSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(color: tone.dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          // A badge sits in whatever slot its row gives it, so the word
          // shortens rather than pushing the layout out of shape.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: AppTypography.badge.copyWith(color: tone.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// The priority badge used by reminders, mapped onto the same tones.
///
/// Low priority is the one case where the dot and the word part company: the
/// yellow is legible as a dot but not as 11pt text, so the label is brown.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final String priority;

  StatusTone get _tone {
    switch (priority.toUpperCase()) {
      case 'HIGH':
        return AppStatus.overdue;
      case 'MEDIUM':
        return AppStatus.followUp;
      case 'LOW':
        return AppStatus.lowPriority;
      default:
        return AppStatus.inactive;
    }
  }

  String get _label {
    final p = priority.trim();
    if (p.isEmpty) return 'None';
    return p[0].toUpperCase() + p.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: _label, tone: _tone);
}
