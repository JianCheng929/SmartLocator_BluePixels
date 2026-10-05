import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ── ADD这两行 ──────────────────────────────────
  static final FlutterLocalNotificationsPlugin _notify = _plugin;
  static const NotificationDetails _batteryChannel = NotificationDetails(
    android: AndroidNotificationDetails(
      'smartlocator_battery',
      'SmartLocator Battery',
      channelDescription: 'Battery level alerts',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFE91E63),
    ),
  );
  // ───────────────────────────────────────────────
  static bool _initialized = false;

  static Future<void> init({
    void Function(String?)? onNotificationTap,
  }) async {
    if (_initialized) return;
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings settings =
        InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        onNotificationTap?.call(details.payload);
      },
    );
    _initialized = true;
  }

  // ── Start tracking sound (called when item tracking page opens) ──────────
  static Future<void> showTrackingStart() async {
    await init();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'smartlocator_start',
      'SmartLocator Start',
      channelDescription: 'Tracking started alert',
      importance: Importance.high,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('notification_start'),
      playSound: true,
      color: Color(0xFF1976D2),
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      0,
      'Tracking Started!',
      'SmartLocator is now tracking your item. Buzzer is active.',
      details,
      payload: 'tracking_page',
    );
  }

  // ── Disconnection ────────────────────────────────────────────────────────
  static Future<void> showDisconnection() async {
    await init();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'smartlocator_ble',
      'SmartLocator BLE',
      channelDescription: 'BLE connection status',
      importance: Importance.high,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('notification_disconnected'),
      playSound: true,
      color: Color(0xFFE53935),
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      1,
      'Disconnection!',
      'SmartLocator is disconnected. Track your items using last-seen data.',
      details,
      payload: 'bt_page',
    );
  }

  // ── Reconnection ─────────────────────────────────────────────────────────
  static Future<void> showReconnection() async {
    await init();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'smartlocator_reconnect',
      'SmartLocator Reconnect',
      channelDescription: 'BLE reconnection alert',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      sound: RawResourceAndroidNotificationSound('notification_reconnect'),
      playSound: true,
      color: Color(0xFF00C853),
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      2,
      'Reconnection! Signal Found!',
      'SmartLocator is successfully reconnected and operates. Enjoy to use!',
      details,
      payload: 'bt_page',
    );
  }

  // ── Positive (Closed By / Nearby) ────────────────────────────────────────
  static Future<void> showPositive(String zone) async {
    await init();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'smartlocator_positive',
      'SmartLocator Proximity',
      channelDescription: 'Proximity zone alerts',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      sound: RawResourceAndroidNotificationSound(
          'notification_positive_nearby_closedby'),
      playSound: true,
      color: Color(0xFF4CAF50),
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      3,
      zone == 'CLOSED BY' ? 'Item Right Beside You!' : 'Item Nearby!',
      zone == 'CLOSED BY'
          ? 'Your tracked item is RIGHT BESIDE you!'
          : 'Your tracked item is NEARBY. You are close!',
      details,
      payload: 'tracking_page',
    );
  }

  // ── Bell alert (Far / Too Far) ───────────────────────────────────────────
  static Future<void> showBellAlert(String zone) async {
    await init();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'smartlocator_bell',
      'SmartLocator Distance Alert',
      channelDescription: 'Distance warning alerts',
      importance: Importance.high,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(
          'notification_bell_far_toofar'),
      playSound: true,
      color: Color(0xFFFF9800),
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _plugin.show(
      4,
      zone == 'FAR' ? 'Item Getting Far!' : 'Item Too Far Away!',
      zone == 'FAR'
          ? 'Your tracked item is getting farther. Move closer.'
          : 'Your item is TOO FAR. You may lose signal soon!',
      details,
      payload: 'tracking_page',
    );
  }

  static Future<void> cancel() async {
    await _plugin.cancelAll();
  }

  static Future<void> showBatteryDecreasing(
    int percent, String status) async {
  await init();
  await _notify.show(
    200 + percent,
    'SmartLocator Battery Is Decreasing...',
    'Battery at $percent%. $status',
    _batteryChannel,
  );
  }

    static Future<void> showBatteryLockWarning() async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'battery_lock',
      'Battery Lock Warning',
      channelDescription: 'SmartLocator battery critically low (<2%)',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('timingalert'),
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      99,
      'SmartLocator Battery Critically Low! (<2%)',
      'Battery below 2% - Please recharge now. Features locking in 60s!',
      details,
    );
  }
}
