import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

class CallKitService {
  static final CallKitService _instance = CallKitService._internal();
  factory CallKitService() => _instance;
  CallKitService._internal();

  Function(Map<String, dynamic>)? onCallAccepted;
  Function(String)? onCallDeclined;

  void init() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterCallkitIncoming.onEvent.listen((event) {
        switch (event!.event) {
          case Event.actionCallAccept:
            // User accepted the call
            if (event.body['extra'] != null) {
              onCallAccepted?.call(
                Map<String, dynamic>.from(event.body['extra']),
              );
            }
            break;
          case Event.actionCallDecline:
            // User declined the call
            onCallDeclined?.call(event.body['id']);
            break;
          case Event.actionCallEnded:
            onCallDeclined?.call(event.body['id']);
            break;
          default:
            break;
        }
      });
    }
  }

  Future<void> showIncomingCall(Map<String, dynamic> data) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    final uuid = data['uuid'] ?? const Uuid().v4();
    final senderName = data['sender'] ?? 'Unknown Caller';

    // Create CallKit params
    final params = CallKitParams(
      id: uuid,
      nameCaller: senderName,
      appName: 'AnyTalk',
      avatar: 'https://i.pravatar.cc/100', // Placeholder avatar
      handle: senderName,
      type: 0, // 0 for video, 1 for audio
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: data, // Pass the offer payload as extra data
      headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification:
            false, // Reverted to false as we don't have a custom layout
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'https://i.pravatar.cc/500',
        actionColor: '#4CAF50',
        isShowFullLockedScreen: true, // Ensure it shows on top of lockscreen/TV
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: '',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'videoChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> endAllCalls() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    await FlutterCallkitIncoming.endAllCalls();
  }
}
