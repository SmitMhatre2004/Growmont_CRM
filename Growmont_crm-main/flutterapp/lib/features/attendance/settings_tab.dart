import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_form.dart';
import '../../shared/widgets/inline_error_banner.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'attendance_service.dart';
import 'attendance_widgets.dart';
import 'device_gateways.dart';

/// Admin: office location, radius, shift times and weekly off.
class AttendanceSettingsTab extends ConsumerWidget {
  const AttendanceSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = AppLayout.isMobile(context);
    final pad = isMobile ? AppSpacing.lg : AppSpacing.xxl;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, AppSpacing.xxl),
      children: [
        AttendanceAsync<AttendanceSettings>(
          value: ref.watch(attendanceSettingsProvider),
          onRetry: () => ref.invalidate(attendanceSettingsProvider),
          builder: (s) => _SettingsForm(initial: s),
        ),
      ],
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial});

  final AttendanceSettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final _lat = TextEditingController(
    text: widget.initial.office?.lat.toString() ?? '',
  );
  late final _lng = TextEditingController(
    text: widget.initial.office?.lng.toString() ?? '',
  );
  late final _radius = TextEditingController(text: '${widget.initial.radiusM}');
  late final _accuracy = TextEditingController(
    text: '${widget.initial.maxAccuracyM}',
  );
  late final _grace = TextEditingController(
    text: '${widget.initial.graceMinutes}',
  );
  late final _fullDayHours = TextEditingController(
    text: _hoursText(widget.initial.fullDayMinutes ?? 360),
  );
  late TimeOfDay _arrival = _toTime(widget.initial.arrival, 10);
  late TimeOfDay _leave = _toTime(widget.initial.leave, 19);
  late Set<int> _off = {...widget.initial.weeklyOff};

  bool _locating = false;
  double? _gpsAccuracy;
  bool _saving = false;
  String? _error;
  String? _success;

  /// 360 -> "6", 390 -> "6.5".
  static String _hoursText(int minutes) {
    final h = minutes / 60;
    return h == h.roundToDouble()
        ? '${h.round()}'
        : h.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static TimeOfDay _toTime(String hhmm, int fallbackHour) {
    final p = hhmm.split(':');
    final h = p.length == 2 ? int.tryParse(p[0]) : null;
    final m = p.length == 2 ? int.tryParse(p[1]) : null;
    return TimeOfDay(hour: h ?? fallbackHour, minute: m ?? 0);
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final c in [_lat, _lng, _radius, _accuracy, _grace, _fullDayHours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    final location = ref.read(locationGatewayProvider);
    String? problem;
    try {
      final access = await location.ensureAccess();
      switch (access) {
        case LocationAccess.serviceOff:
          problem = 'Location is turned off on this phone.';
        case LocationAccess.denied:
          problem = 'Location permission was not given.';
        case LocationAccess.deniedForever:
          problem =
              'Location permission is blocked. Allow it in the app settings.';
        case LocationAccess.granted:
          final fix = await location.currentFix();
          _lat.text = fix.lat.toStringAsFixed(6);
          _lng.text = fix.lng.toStringAsFixed(6);
          _gpsAccuracy = fix.accuracyM;
      }
    } on TimeoutException {
      problem = 'Could not get a GPS reading in time. Try again near a window.';
    } catch (_) {
      problem = 'Could not read your location. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      _error = problem;
    });
  }

  /// Parses the form, or returns a message saying what is wrong.
  (AttendanceSettings?, String?) _collect() {
    int? whole(TextEditingController c, int min, int max) {
      final v = int.tryParse(c.text.trim());
      return v == null || v < min || v > max ? null : v;
    }

    LatLng? office;
    final latText = _lat.text.trim();
    final lngText = _lng.text.trim();
    if (latText.isNotEmpty || lngText.isNotEmpty) {
      final lat = double.tryParse(latText);
      final lng = double.tryParse(lngText);
      if (lat == null || lat < -90 || lat > 90) {
        return (null, 'Latitude must be a number between -90 and 90.');
      }
      if (lng == null || lng < -180 || lng > 180) {
        return (null, 'Longitude must be a number between -180 and 180.');
      }
      office = LatLng(lat, lng);
    }
    final radius = whole(_radius, 10, 500);
    if (radius == null) return (null, 'Radius must be 10 to 500 metres.');
    final accuracy = whole(_accuracy, 5, 100);
    if (accuracy == null) {
      return (null, 'Maximum GPS accuracy must be 5 to 100 metres.');
    }
    final grace = whole(_grace, 0, 60);
    if (grace == null) return (null, 'Grace must be 0 to 60 minutes.');
    final hours = double.tryParse(_fullDayHours.text.trim());
    final fullDay = hours == null ? null : (hours * 60).round();
    if (fullDay == null || fullDay < 60 || fullDay > 1440) {
      return (null, 'Full day after must be 1 to 24 hours.');
    }
    final gap =
        (_leave.hour * 60 + _leave.minute) -
        (_arrival.hour * 60 + _arrival.minute);
    if (gap < 60) {
      return (null, 'Leave time must be at least an hour after arrival.');
    }
    if (_off.length >= 7) return (null, 'Not every day can be a weekly off.');

    return (
      AttendanceSettings(
        office: office,
        radiusM: radius,
        maxAccuracyM: accuracy,
        arrival: _fmt(_arrival),
        leave: _fmt(_leave),
        graceMinutes: grace,
        fullDayMinutes: fullDay,
        weeklyOff: (_off.toList()..sort()),
      ),
      null,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final (settings, problem) = _collect();
    if (settings == null) {
      setState(() {
        _error = problem;
        _success = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(attendanceServiceProvider).saveSettings(settings);
      ref.invalidate(attendanceSettingsProvider);
      ref.invalidate(attendanceTodayProvider);
      if (mounted) {
        setState(() {
          _saving = false;
          _success = 'Settings saved.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = attendanceErrorMessage(e);
        });
      }
    }
  }

  /// Two fields side by side at every width. A field is never given less
  /// than half the row, so on a 320 px phone each still shows 5+ digits.
  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: b),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final canMark = ref.watch(canMarkAttendanceProvider);
    final radius = int.tryParse(_radius.text.trim());
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return AttendancePanel(
      title: 'Attendance settings',
      icon: Icons.tune,
      child: AppFormColumn(
        children: [
          if (_error != null) InlineErrorBanner(message: _error!),
          if (_success != null)
            Text(
              _success!,
              style: AppTypography.bodySecondary.copyWith(
                color: AppColors.success,
              ),
            ),
          Text('Office location', style: AppTypography.cardTitle),
          if (canMark)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: AppSizing.iconSm),
                label: Text(
                  _locating ? 'Getting location...' : 'Use my current location',
                ),
              ),
            ),
          if (_gpsAccuracy != null)
            Text(
              'Set from GPS with about ${_gpsAccuracy!.round()} m accuracy.',
              style: AppTypography.caption,
            ),
          _pair(
            AppFormField(label: 'Latitude', child: _number(_lat, signed: true)),
            AppFormField(
              label: 'Longitude',
              child: _number(_lng, signed: true),
            ),
          ),
          _pair(
            AppFormField(
              label: 'Radius (m)',
              child: _number(_radius, whole: true, onChanged: true),
            ),
            AppFormField(
              label: 'Max accuracy (m)',
              child: _number(_accuracy, whole: true),
            ),
          ),
          if (radius != null && radius < 20)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: AppRadius.brMd,
              ),
              child: Text(
                'A radius under 20 m is risky: phone GPS is often 10 to 20 m '
                'off indoors, so people standing in the office may be '
                'refused.',
                style: AppTypography.bodySecondary.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ),
          Text('Shift', style: AppTypography.cardTitle),
          _pair(
            AppFormField(
              label: 'Arrival',
              child: AppTimeField(
                value: _arrival,
                onChanged: (t) => setState(() => _arrival = t),
              ),
            ),
            AppFormField(
              label: 'Leave',
              child: AppTimeField(
                value: _leave,
                onChanged: (t) => setState(() => _leave = t),
              ),
            ),
          ),
          _pair(
            AppFormField(
              label: 'Grace (min)',
              child: _number(_grace, whole: true),
            ),
            AppFormField(
              label: 'Full day after (h)',
              child: _number(_fullDayHours),
            ),
          ),
          Text(
            'Working fewer hours than "Full day after" counts as a half day.',
            style: AppTypography.caption,
          ),
          Text('Weekly off', style: AppTypography.cardTitle),
          Row(
            children: [
              for (var d = 1; d <= 7; d++) ...[
                if (d > 1) const SizedBox(width: 4),
                Expanded(
                  child: _DayChip(
                    key: ValueKey('off-$d'),
                    label: dayNames[d - 1],
                    selected: _off.contains(d),
                    onTap: () => setState(() {
                      _off.contains(d) ? _off.remove(d) : _off.add(d);
                    }),
                  ),
                ),
              ],
            ],
          ),
          Text(
            'Changing the weekly off applies from today; past months stay '
            'as they were. Shift changes apply to days recorded afterwards.',
            style: AppTypography.caption,
          ),
          AppFormActions(
            submitLabel: 'Save settings',
            busy: _saving,
            cancelLabel: 'Reset',
            onCancel: () => setState(() {
              final s = widget.initial;
              _lat.text = s.office?.lat.toString() ?? '';
              _lng.text = s.office?.lng.toString() ?? '';
              _radius.text = '${s.radiusM}';
              _accuracy.text = '${s.maxAccuracyM}';
              _grace.text = '${s.graceMinutes}';
              _fullDayHours.text = _hoursText(s.fullDayMinutes ?? 360);
              _arrival = _toTime(s.arrival, 10);
              _leave = _toTime(s.leave, 19);
              _off = {...s.weeklyOff};
              _error = null;
              _success = null;
            }),
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  Widget _number(
    TextEditingController c, {
    bool signed = false,
    bool whole = false,
    bool onChanged = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(
        signed: signed,
        decimal: !whole,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(whole ? r'[0-9]' : r'[0-9.\-]'),
        ),
      ],
      onChanged: onChanged ? (_) => setState(() {}) : null,
    );
  }
}

/// One tappable weekday. Seven fit on a 320 px phone.
class _DayChip extends StatelessWidget {
  const _DayChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brMd,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : AppColors.surface,
            borderRadius: AppRadius.brMd,
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: AppTypography.buttonSmall.copyWith(
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
