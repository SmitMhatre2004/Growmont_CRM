import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'attendance_models.dart';
import 'attendance_providers.dart';
import 'device_gateways.dart';
import 'mark_actions.dart';
import 'mark_flow.dart';

/// Green: a live position is inside the office radius with good accuracy and
/// is not mocked (the same test the server applies). Yellow: every other case.
enum RingTone { green, yellow }

/// The ring colour for one live reading. [distanceM] is the straight-line
/// distance to the office; null (no reading yet) is yellow.
RingTone ringToneFor({
  required GpsFix? fix,
  required double? distanceM,
  required int radiusM,
  required int maxAccuracyM,
}) {
  if (fix == null || distanceM == null) return RingTone.yellow;
  final inside = distanceM <= radiusM;
  final accurate = fix.accuracyM <= maxAccuracyM;
  return inside && accurate && !fix.isMocked ? RingTone.green : RingTone.yellow;
}

const Color kRingGreen = AppColors.primaryGreen;
const Color kRingYellow = Color(0xFFFACC15);

/// The pill-shaped fingerprint button (44 x 64) with its rotating ring that
/// follows the pill outline, shown in the phone top bar on the Dashboard.
///
/// It reads today's attendance from the same provider as the Attendance
/// screen and marks through the same flow. It only ever watches the location
/// while it is on screen and the app is in the foreground, and it never asks
/// for permission on its own: the prompt appears when the person taps.
///
/// Any trouble getting attendance hides it. It must never affect the
/// Dashboard.
class DashboardRingButton extends ConsumerStatefulWidget {
  const DashboardRingButton({super.key, this.onOpenAttendance});

  /// Opens the Attendance screen (after check-out).
  final VoidCallback? onOpenAttendance;

  @override
  ConsumerState<DashboardRingButton> createState() =>
      _DashboardRingButtonState();
}

class _DashboardRingButtonState extends ConsumerState<DashboardRingButton>
    with WidgetsBindingObserver {
  StreamSubscription<GpsFix>? _sub;
  GpsFix? _fix;
  bool _resumed = true;
  bool _disposed = false;
  int _syncId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
    // After the first frame, so the providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    if (resumed) {
      // The person may have changed the permission in Settings meanwhile.
      ref.invalidate(attendanceTodayProvider);
    }
    _sync();
  }

  /// Starts or cancels the location stream to match: watch only while this
  /// button is mounted (Dashboard visible), the app is resumed, attendance is
  /// configured, and permission is already granted.
  Future<void> _sync() async {
    if (_disposed) return;
    final id = ++_syncId;
    final today = ref.read(attendanceTodayProvider).valueOrNull;
    final wanted =
        _resumed &&
        ref.read(canMarkAttendanceProvider) &&
        today != null &&
        today.configured &&
        today.settings.office != null;
    if (!wanted) {
      await _stop();
      return;
    }
    if (_sub != null) return;
    final location = ref.read(locationGatewayProvider);
    LocationAccess access;
    try {
      access = await location.checkAccess();
    } catch (_) {
      access = LocationAccess.denied;
    }
    // Stale: the screen changed while we were asking.
    if (_disposed || id != _syncId || !_resumed) return;
    if (access != LocationAccess.granted) {
      await _stop();
      return;
    }
    if (_sub != null) return;
    _sub = location
        .watchFix(distanceFilterM: 5)
        .listen(
          (fix) {
            if (mounted) setState(() => _fix = fix);
          },
          onError: (_) {
            if (mounted) setState(() => _fix = null);
          },
        );
  }

  Future<void> _stop() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (!_disposed && mounted && _fix != null) setState(() => _fix = null);
  }

  bool get _watching => _sub != null;

  Future<void> _onTap(TodayInfo today) async {
    if (ref.read(attendanceMarkBusyProvider)) return;
    final record = today.record;
    if (record?.hasCheckOut == true) {
      widget.onOpenAttendance?.call();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (today.shiftOver) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'The shift is over for today, so you can no longer check in.',
          ),
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    final action = record?.hasCheckIn == true ? 'out' : 'in';
    final outcome = await performMark(context, action);
    if (_disposed || !mounted) return;
    // A permission prompt may have just been answered.
    unawaited(_sync());
    if (outcome is MarkFailed) {
      final fix = outcome.fix;
      final label = markFixLabel(fix);
      final location = ref.read(locationGatewayProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(outcome.message),
            duration: const Duration(seconds: 6),
            action: label == null
                ? null
                : SnackBarAction(
                    label: label,
                    onPressed: () {
                      switch (fix) {
                        case MarkFix.retry:
                          _onTap(today);
                        case MarkFix.openAppSettings:
                          location.openAppSettings();
                        case MarkFix.openLocationSettings:
                          location.openLocationSettings();
                        case MarkFix.none:
                          break;
                      }
                    },
                  ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phones only, and nothing below this line touches Firebase on a
    // platform that cannot mark.
    if (!ref.watch(canMarkAttendanceProvider)) return const SizedBox.shrink();

    // Re-evaluate the stream whenever attendance changes.
    ref.listen(attendanceTodayProvider, (_, _) => _sync());

    final todayAsync = ref.watch(attendanceTodayProvider);
    final today = todayAsync.valueOrNull;
    if (today == null || todayAsync.hasError) return const SizedBox.shrink();
    if (!today.configured || today.settings.office == null) {
      return const SizedBox.shrink();
    }

    final busy = ref.watch(attendanceMarkBusyProvider);
    final done = today.record?.hasCheckOut == true;
    final shiftOver = today.shiftOver;

    final fix = _fix;
    final office = today.settings.office!;
    final distance = fix == null
        ? null
        : ref
              .read(locationGatewayProvider)
              .distanceM(fix.lat, fix.lng, office.lat, office.lng);
    final live = ringToneFor(
      fix: fix,
      distanceM: distance,
      radiusM: today.settings.radiusM,
      maxAccuracyM: today.settings.maxAccuracyM,
    );

    final tone = done
        ? RingTone.green
        : shiftOver
        ? RingTone.yellow
        : live;
    // Static when there is nothing more to do today.
    final spinning = !done && !shiftOver;
    final hasIn = today.record?.hasCheckIn == true;

    final label = done
        ? 'Attendance complete for today. Open attendance'
        : shiftOver
        ? 'Shift over, you can no longer check in'
        : '${hasIn ? 'Mark check-out' : 'Mark present'}. '
              '${tone == RingTone.green ? 'You are at the office' : 'You are not in range of the office'}';

    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: done ? 'Attendance' : (hasIn ? 'Check out' : 'Mark present'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkResponse(
            key: const ValueKey('dashboard-ring'),
            onTap: busy ? null : () => _onTap(today),
            customBorder: const StadiumBorder(),
            child: RingVisual(
              tone: tone,
              spinning: spinning,
              busy: busy,
              complete: done,
              watching: _watching,
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of the attendance pill. The profile and employee-detail cards use
/// the same size, so the control looks identical everywhere.
const double kAttendancePillHeight = 44;

/// Width of the attendance pill.
const double kAttendancePillWidth = 64;

/// The ring itself: a pill (rounded rectangle, full radius) with a
/// gradient arc that travels clockwise around its outline about once every
/// 1.6 s. Static under reduced motion, when not [spinning], and for the
/// completed state (a solid ring and a check). [solid] gives the same solid
/// ring with the fingerprint, for display-only uses.
class RingVisual extends StatefulWidget {
  const RingVisual({
    super.key,
    required this.tone,
    this.spinning = true,
    this.busy = false,
    this.complete = false,
    this.watching = false,
    this.solid = false,
    this.size = kAttendancePillHeight,
    this.width = kAttendancePillWidth,
  });

  final RingTone tone;
  final bool spinning;
  final bool busy;
  final bool complete;
  final bool watching;
  final bool solid;

  /// The pill's height.
  final double size;

  /// The pill's width.
  final double width;

  @override
  State<RingVisual> createState() => _RingVisualState();
}

class _RingVisualState extends State<RingVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _animate =>
      widget.spinning &&
      !widget.complete &&
      !widget.solid &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTurn();
  }

  @override
  void didUpdateWidget(RingVisual old) {
    super.didUpdateWidget(old);
    _syncTurn();
  }

  void _syncTurn() {
    if (_animate) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.tone == RingTone.green ? kRingGreen : kRingYellow;
    final ink = widget.tone == RingTone.green
        ? AppColors.primaryGreenDark
        : AppColors.yellowText;
    final innerH = widget.size - 12;
    return SizedBox(
      width: widget.width,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _turn,
              builder: (_, _) => CustomPaint(
                painter: RingPainter(
                  color: color,
                  angle: _turn.value * 2 * math.pi,
                  solid: widget.complete || widget.solid,
                ),
              ),
            ),
          ),
          Container(
            width: widget.width - 12,
            height: innerH,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(innerH / 2),
            ),
            child: widget.busy
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: ink,
                      ),
                    ),
                  )
                : Icon(
                    widget.complete ? Icons.check_rounded : Icons.fingerprint,
                    size: 26,
                    color: ink,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The display-only pill used by the profile and employee-detail attendance
/// cards: the same shape, size and ring as the Dashboard button, as a solid
/// green ring. [onTap] (own profile) opens the Attendance screen.
class AttendancePillBadge extends StatelessWidget {
  const AttendancePillBadge({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const pill = RingVisual(
      key: ValueKey('attendance-pill-badge'),
      tone: RingTone.green,
      spinning: false,
      solid: true,
    );
    if (onTap == null) return const ExcludeSemantics(child: pill);
    return Semantics(
      button: true,
      label: 'Open attendance',
      excludeSemantics: true,
      child: InkResponse(
        key: const ValueKey('attendance-pill-tap'),
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: pill,
      ),
    );
  }
}

/// A pill (stadium) outline as a path that starts at the top centre and runs
/// clockwise, so a distance along it maps to a place on the ring.
Path pillOutline(Rect r) {
  final radius = r.height / 2;
  final cy = r.center.dy;
  final path = Path()..moveTo(r.center.dx, r.top);
  path.lineTo(r.right - radius, r.top);
  path.arcTo(
    Rect.fromCircle(center: Offset(r.right - radius, cy), radius: radius),
    -math.pi / 2,
    math.pi,
    false,
  );
  path.lineTo(r.left + radius, r.bottom);
  path.arcTo(
    Rect.fromCircle(center: Offset(r.left + radius, cy), radius: radius),
    math.pi / 2,
    math.pi,
    false,
  );
  path.close();
  return path;
}

/// A faint full track plus an arc that fades from clear to [color] along the
/// pill outline, advanced clockwise by [angle] (one full turn = 2 pi).
/// [solid] draws one full ring instead.
class RingPainter extends CustomPainter {
  const RingPainter({
    required this.color,
    required this.angle,
    this.solid = false,
  });

  final Color color;
  final double angle;
  final bool solid;

  static const int _segments = 28;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.4;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final outline = pillOutline(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (solid) {
      canvas.drawPath(outline, paint..color = color);
      return;
    }
    canvas.drawPath(outline, paint..color = color.withValues(alpha: 0.22));
    final metric = outline.computeMetrics().first;
    final total = metric.length;
    final lit = total * 0.75;
    final start = (angle / (2 * math.pi)) * total;
    final seg = lit / _segments;
    // The lit 3/4 of the outline, tail faint and head bright.
    for (var i = 0; i < _segments; i++) {
      final from = start + i * seg;
      final t = (i + 1) / _segments;
      paint.color = color.withValues(alpha: t * t);
      _drawRange(canvas, metric, total, from, from + seg + 0.5, paint);
    }
  }

  /// Draws [from]..[to] of the outline, wrapping past its end.
  static void _drawRange(
    Canvas canvas,
    PathMetric metric,
    double total,
    double from,
    double to,
    Paint paint,
  ) {
    final a = from % total;
    final b = a + (to - from);
    if (b <= total) {
      canvas.drawPath(metric.extractPath(a, b), paint);
    } else {
      canvas.drawPath(metric.extractPath(a, total), paint);
      canvas.drawPath(metric.extractPath(0, b - total), paint);
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.color != color || old.angle != angle || old.solid != solid;
}
