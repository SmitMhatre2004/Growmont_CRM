import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../models/reminder.dart';

/// Schedules on-device notifications for the signed-in user's reminders,
/// played with Growmont's own chime so they stand out from other apps.
///
/// Scheduling is local (no push server): it works offline and fires even when
/// the app is closed. The whole schedule is rebuilt from the reminder list on
/// every change, so edits and deletes are picked up without extra bookkeeping.
///
/// Mobile only (Android/iOS); a no-op everywhere else.
class ReminderNotifications {
  ReminderNotifications._();
  static final instance = ReminderNotifications._();

  // Android locks a channel's sound the first time the channel is created, so
  // changing the tone later requires a new channel id (e.g. reminders_v2).
  static const _channelId = 'reminders_v1';
  static const _channelName = 'Reminders';
  static const _channelDescription = 'Alerts for your scheduled CRM reminders';

  // res/raw/growmont_reminder.wav on Android. On iOS the same file must be
  // added to the Runner target in Xcode; until then iOS uses the default sound.
  static const _androidSound = RawResourceAndroidNotificationSound(
    'growmont_reminder',
  );
  static const _iosSound = 'growmont_reminder.wav';

  // iOS keeps at most 64 pending notifications; stay under it on both platforms.
  static const _maxScheduled = 60;

  static const _weekdayByName = {
    'Mon': DateTime.monday,
    'Tue': DateTime.tuesday,
    'Wed': DateTime.wednesday,
    'Thu': DateTime.thursday,
    'Fri': DateTime.friday,
    'Sat': DateTime.saturday,
    'Sun': DateTime.sunday,
  };

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  Future<void> _queue = Future.value();

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Initializes the plugin, timezone data and the Android channel, and asks
  /// for notification permission. Safe to call repeatedly.
  Future<bool> init() => _ready ??= _init();

  Future<bool> _init() async {
    if (!isSupported) return false;
    try {
      tz_data.initializeTimeZones();
      try {
        final local = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(local.identifier));
      } catch (e) {
        // Growmont operates in India; better than silently scheduling in UTC.
        debugPrint('ReminderNotifications: timezone lookup failed ($e)');
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      }

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
            sound: _androidSound,
            vibrationPattern: Int64List.fromList([0, 250, 150, 250, 150, 500]),
          ),
        );
        await android.requestNotificationsPermission();
      }

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return true;
    } catch (e) {
      debugPrint('ReminderNotifications: init failed ($e)');
      return false;
    }
  }

  /// Replaces every scheduled reminder notification with ones for [reminders].
  /// Calls are serialized so overlapping updates can't interleave.
  Future<void> sync(List<Reminder> reminders) {
    return _queue = _queue.then((_) => _sync(reminders)).catchError((Object e) {
      debugPrint('ReminderNotifications: sync failed ($e)');
    });
  }

  /// Removes all scheduled reminder notifications (e.g. on sign-out). Skipped
  /// if nothing was ever set up, so a signed-out launch never asks permission.
  Future<void> clear() => _ready == null ? Future.value() : sync(const []);

  Future<void> _sync(List<Reminder> reminders) async {
    if (!await init()) return;

    final now = tz.TZDateTime.now(tz.local);
    final slots = <_Slot>[];
    for (final r in reminders) {
      slots.addAll(_slotsFor(r, now));
    }
    slots.sort((a, b) => a.when.compareTo(b.when));

    final mode = await _scheduleMode();
    await _plugin.cancelAllPendingNotifications();
    for (final s in slots.take(_maxScheduled)) {
      await _plugin.zonedSchedule(
        id: s.id,
        scheduledDate: s.when,
        title: s.reminder.eventName,
        body: _body(s.reminder),
        payload: s.reminder.id,
        notificationDetails: _details(s.reminder),
        androidScheduleMode: mode,
        matchDateTimeComponents: s.repeat,
      );
    }
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  NotificationDetails _details(Reminder r) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: r.priority == 'HIGH' ? Priority.max : Priority.high,
        category: AndroidNotificationCategory.reminder,
        sound: _androidSound,
        ticker: 'Reminder: ${r.eventName}',
        styleInformation: r.description.isEmpty
            ? null
            : BigTextStyleInformation(_body(r)),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: _iosSound,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  String _body(Reminder r) {
    final label = switch (r.priority) {
      'HIGH' => 'High priority',
      'LOW' => 'Low priority',
      _ => 'Medium priority',
    };
    return r.description.isEmpty ? label : '$label · ${r.description}';
  }

  /// Every upcoming notification for [r]: one for a one-off reminder, one per
  /// selected weekday for a weekly reminder, otherwise one repeating entry.
  List<_Slot> _slotsFor(Reminder r, tz.TZDateTime now) {
    final day = DateTime.tryParse(r.date);
    if (day == null) return const [];
    final parts = r.time.split(':');
    final hour = int.tryParse(parts[0]) ?? 10;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final start = tz.TZDateTime(
      tz.local,
      day.year,
      day.month,
      day.day,
      hour,
      minute,
    );
    // Repeats begin at the reminder's own date, or today if that has passed.
    final from = start.isAfter(now) ? start : now;

    tz.TZDateTime at(int y, int m, int d) =>
        tz.TZDateTime(tz.local, y, m, d, hour, minute);

    if (!r.repeatReminder || r.repeatType == 'NONE') {
      return start.isAfter(now) ? [_Slot(r, 0, start, null)] : const [];
    }

    if (r.repeatEveryDay || r.repeatType == 'DAILY') {
      var next = at(from.year, from.month, from.day);
      if (next.isBefore(from)) next = next.add(const Duration(days: 1));
      return [_Slot(r, 0, next, DateTimeComponents.time)];
    }

    if (r.repeatType == 'WEEKLY') {
      final days = r.repeatDays
          .map((d) => _weekdayByName[d])
          .whereType<int>()
          .toSet();
      if (days.isEmpty) days.add(start.weekday);
      return [
        for (final wd in days)
          _Slot(
            r,
            wd,
            _nextWeekday(at(from.year, from.month, from.day), wd, from),
            DateTimeComponents.dayOfWeekAndTime,
          ),
      ];
    }

    if (r.repeatType == 'MONTHLY') {
      var y = from.year, m = from.month;
      var next = at(y, m, start.day);
      while (next.isBefore(from) || next.day != start.day) {
        // Skip months too short for this day (e.g. the 31st).
        if (++m > 12) {
          m = 1;
          y++;
        }
        next = at(y, m, start.day);
      }
      return [_Slot(r, 0, next, DateTimeComponents.dayOfMonthAndTime)];
    }

    return const [];
  }

  tz.TZDateTime _nextWeekday(tz.TZDateTime d, int weekday, tz.TZDateTime from) {
    var next = d.add(Duration(days: (weekday - d.weekday) % 7));
    if (next.isBefore(from)) next = next.add(const Duration(days: 7));
    return next;
  }
}

class _Slot {
  _Slot(this.reminder, int slot, this.when, this.repeat)
    : id = _stableId('${reminder.id}#$slot');

  final Reminder reminder;
  final tz.TZDateTime when;
  final DateTimeComponents? repeat;
  final int id;

  /// Notification ids must be 32-bit ints; reminder ids are Firestore strings.
  /// FNV-1a keeps the id stable across runs (String.hashCode is not).
  static int _stableId(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }
}
