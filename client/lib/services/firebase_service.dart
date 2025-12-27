import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'callkit_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> init() async {
    // Request permission (Apple only, Android 13+)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    // Get the token
    String? token = await _firebaseMessaging.getToken();
    print("FCM Token: $token");

    // Setup Listeners
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
      }

      _handleMessage(message);
    });

    // Background messaging is handled by a top-level function, configured in main.dart
  }

  void _handleMessage(RemoteMessage message) {
    if (message.data['type'] == 'offer' || message.data['type'] == 'call') {
      // It's a call! Hand it off to CallKit
      // We pass the data directly
      CallKitService().showIncomingCall(message.data);
    }
  }

  // Top-level function for background handling
  static Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    await Firebase.initializeApp();
    print("Handling a background message: ${message.messageId}");

    if (message.data['type'] == 'offer' || message.data['type'] == 'call') {
      // We cannot access the singleton CallKitService easily here from isolate,
      // but CallKitService().showIncomingCall is largely static/plugin based.
      // However, to be safe, we re-instantiate or just call the plugin directly via service wrapper.
      await CallKitService().showIncomingCall(message.data);
    }
  }
}
