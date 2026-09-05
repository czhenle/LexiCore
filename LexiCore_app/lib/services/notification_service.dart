import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Study reminders, all three halves:
///
/// * **Local** — `init()` / `scheduleDailyReminder()` schedule an on-device
///   notification. Works offline, but fires blind: it cannot check whether
///   today's task is already done at the moment it goes off.
/// * **Server prefs** — `syncReminderPrefsToServer()` mirrors the same
///   settings (plus the device's timezone, which the server has no other way
///   to know) into `notification_prefs`, so the `push-reminder` edge function
///   knows WHEN a student wants nudging.
/// * **Push delivery** — `initFcm()` registers this device's FCM token into
///   `device_tokens`, so `push-reminder` has somewhere to actually send the
///   smarter version: one that checks the student's plan first and stays
///   quiet once today's task is already done.
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  static const int _dailyReminderId = 1001;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _fcmInitialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();
    try {
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));
    } catch (e) {
      debugPrint('Could not resolve device timezone, defaulting to UTC: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    await _plugin.cancel(id: _dailyReminderId);
    await _plugin.zonedSchedule(
      id: _dailyReminderId,
      title: "Today's Task is waiting! 📚",
      body: "Don't forget your English practice today!",
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_study_reminder',
          'Study Reminders',
          channelDescription: 'Daily reminder to complete your study task',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDailyReminder() => _plugin.cancel(id: _dailyReminderId);

  /// Registers this device for push and starts listening for tokens/messages.
  ///
  /// Wrapped end to end: a Firebase misconfiguration, a refused permission,
  /// or a platform quirk should never stop the app from starting — the local
  /// reminder already works standalone and must keep working regardless.
  Future<void> initFcm() async {
    // HomeScreen is rebuilt from scratch in several places (ResultScreen and
    // WeeklyAssessmentScreen both finish with pushAndRemoveUntil(HomeScreen)),
    // so its initState — and this method — runs again after every completed
    // session. Without this guard each run would attach ANOTHER onMessage /
    // onTokenRefresh listener, none of which are ever cancelled: duplicate
    // token writes on refresh, and duplicate handling of every foreground
    // push, growing for as long as the app stays open.
    if (_fcmInitialized) return;
    _fcmInitialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      final token = await messaging.getToken();
      if (token != null) await _saveDeviceToken(token);
      // Tokens rotate (reinstall, restore, FCM's own housekeeping) — a stale
      // token is a silently undelivered reminder, so keep following it.
      messaging.onTokenRefresh.listen(_saveDeviceToken);

      // FCM does NOT display a notification while the app is foregrounded
      // (only backgrounded/killed) — hand foreground pushes to the same local
      // plugin so a reminder looks and sounds identical in every app state.
      FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n == null) return;
        _plugin.show(
          id: _dailyReminderId,
          title: n.title ?? "Today's Task is waiting! 📚",
          body: n.body ?? '',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_study_reminder',
              'Study Reminders',
              channelDescription: 'Daily reminder to complete your study task',
              importance: Importance.defaultImportance,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      });
    } catch (e) {
      debugPrint('FCM init skipped (local reminders still active): $e');
    }
  }

  /// Registers this device's token against the CURRENT student.
  ///
  /// Goes through the `register_device_token` RPC rather than upserting
  /// `device_tokens` directly: an FCM token identifies a device, not a
  /// person, so when a second student signs in on a shared family/classroom
  /// tablet the previous student's row has to be cleared first — otherwise
  /// their reminder gets delivered to a screen someone else is now using.
  /// RLS (correctly) won't let one student delete another's row, so that
  /// cleanup lives in a security-definer function on the server.
  Future<void> _saveDeviceToken(String token) async {
    if (Supabase.instance.client.auth.currentUser?.id == null) return;
    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('Device token save failed: $e');
    }
  }

  /// Mirrors the on-device reminder settings into Supabase, so the server-side
  /// `push-reminder` function knows WHEN (and whether) to nudge this student.
  ///
  /// The device stays the source of truth — this is a one-way sync. The
  /// timezone matters as much as the time: without it the server has no way to
  /// tell when "17:00" is for this particular student.
  ///
  /// Deliberately silent on failure. A student whose prefs didn't reach the
  /// server still gets their locally scheduled reminder, so this is never
  /// worth interrupting them over.
  Future<void> syncReminderPrefsToServer({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return; // signed out — picked up on the next sync point

    var timezone = 'Asia/Kuala_Lumpur';
    try {
      timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (e) {
      debugPrint('Could not resolve device timezone for reminder sync: $e');
    }

    try {
      await Supabase.instance.client.from('notification_prefs').upsert({
        'user_id': uid,
        'enabled': enabled,
        'reminder_hour': hour,
        'reminder_minute': minute,
        'timezone': timezone,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Reminder prefs sync failed: $e');
    }
  }

  /// Reads the saved on-device settings and syncs them, for call sites that
  /// don't already have the values to hand — HomeScreen uses this so a brand
  /// new sign-up (where the splash sync ran before any session existed) still
  /// reaches the server on its very first session, not the next cold start.
  Future<void> syncSavedReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await syncReminderPrefsToServer(
      enabled: prefs.getBool('reminder_enabled') ?? true,
      hour: prefs.getInt('reminder_hour') ?? 17,
      minute: prefs.getInt('reminder_minute') ?? 0,
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
