import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'blaze_storage.dart';
import 'launch_bridge.dart';

@pragma('vm:entry-point')
Future<void> _bgMessageHandler(RemoteMessage _) async {}

class SignalService {
  final _notif = FlutterLocalNotificationsPlugin();
  final BlazeStorage _store;

  FirebaseMessaging? _msg;
  String? _token;
  bool _ready = false;

  Function(String url)? onPushUrl;
  Function(String token)? onTokenRotated;

  SignalService(this._store);

  String? get token => _token;

  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _msg = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_bgMessageHandler);

      await _setupLocalNotif();

      _token = await _msg!.getToken();
      _msg!.onTokenRefresh.listen((t) {
        _token = t;
        onTokenRotated?.call(t);
      });

      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onWarmTap);

      final cold = await _msg!.getInitialMessage();
      if (cold != null) _onColdStart(cold);

      _ready = true;
    } catch (_) {
      // Firebase not configured — push disabled
    }
  }

  Future<void> _setupLocalNotif() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notif.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload == null) return;
        try {
          final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
          final url = data['url'] as String?;
          if (url != null && url.isNotEmpty) onPushUrl?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final android = _notif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'Push notifications channel',
        importance: Importance.high,
      ));
    }
  }

  Future<bool> requestPermission() async {
    if (_msg == null) return false;
    final settings = await _msg!.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );
    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    await _store.setNotifGranted(granted);
    // Mark OS-denied so we never loop-show the screen again
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await _store.setNotifOsDenied();
    }
    return granted;
  }

  void _onForeground(RemoteMessage msg) async {
    final notif = msg.notification;
    if (notif == null || !Platform.isAndroid) return;

    final imgUrl = msg.notification?.android?.imageUrl;
    AndroidNotificationDetails? details;

    if (imgUrl != null && imgUrl.isNotEmpty) {
      final bytes = await _fetchImage(imgUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          'high_importance_channel', 'High Importance Notifications',
          importance: Importance.high, priority: Priority.high,
          icon: '@drawable/ic_notification',
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }

    details ??= const AndroidNotificationDetails(
      'high_importance_channel', 'High Importance Notifications',
      importance: Importance.high, priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    final payload = msg.data.isNotEmpty ? jsonEncode(msg.data) : null;
    await _notif.show(
      notif.hashCode, notif.title, notif.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  void _onColdStart(RemoteMessage msg) {
    final url = msg.data['url'] as String?;
    if (url != null && url.isNotEmpty) _store.savePushUrl(url);
  }

  void _onWarmTap(RemoteMessage msg) {
    final url = msg.data['url'] as String?;
    if (url != null && url.isNotEmpty) onPushUrl?.call(url);
  }

  Future<Uint8List?> _fetchImage(String url) async {
    try {
      final resp = await httpBridge.get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }
}
