import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_messaging/firebase_messaging.dart'
    as firebase_messaging;

import 'callkit_service.dart';

class SignalingService {
  late IO.Socket _socket;
  final CallKitService _callKitService = CallKitService();

  // Callbacks
  Function(String)? onUserJoined;
  Function(List<Map<String, dynamic>>)? onUserListUpdated;
  Function(Map<String, dynamic>)? onIncomingCall;
  Function(Map<String, dynamic>)? onOffer;
  Function(Map<String, dynamic>)? onAnswer;
  // Backing field for onIceCandidate
  Function(Map<String, dynamic>)? _onIceCandidate;
  final List<Map<String, dynamic>> _iceCandidateQueue = [];

  set onIceCandidate(Function(Map<String, dynamic>)? callback) {
    _onIceCandidate = callback;
    if (callback != null) {
      // Flush buffer if we are attaching a listener
      for (var candidate in _iceCandidateQueue) {
        print('Flushing buffered ICE candidate');
        callback(candidate);
      }
      _iceCandidateQueue.clear();
    } else {
      // If listener is removed (call ended), clear buffer to avoid stale candidates
      _iceCandidateQueue.clear();
    }
  }

  Function(Map<String, dynamic>)? get onIceCandidate => _onIceCandidate;

  Function(Map<String, dynamic>)? onCallEnded;

  // Singleton
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal() {
    _callKitService.init();
  }

  // List of {username, online}
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> get users => _users;
  String? get socketId => _socket.id;

  void connect() {
    // Production URL (Render)
    String baseUrl = 'https://anytalk.onrender.com';

    // Uncomment to use local dev logic
    // if (!kIsWeb && Platform.isAndroid) {
    //   baseUrl = 'http://10.0.2.2:3000';
    // } else if (kDebugMode) {
    //   baseUrl = 'http://localhost:3000';
    // }

    // Secure Auth Token (In prod this should be secure)
    const String authToken = "secret_anytalk_key_12345";

    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': authToken},
    });

    _socket.connect();

    _socket.onConnect((_) async {
      print('Connected to signaling server');

      // Auto-relogin if we were previously logged in (e.g. reconnection)
      if (_currentUsername != null) {
        print("Restoring session for: $_currentUsername");
        _socket.emit('login', _currentUsername);
      }

      // Update FCM token mapping on server
      try {
        if (!kIsWeb && Platform.isAndroid) {
          String? token = await firebase_messaging.FirebaseMessaging.instance
              .getToken();
          if (token != null) {
            print("Sending FCM token to server: $token");
            _socket.emit('store-fcm-token', token);
          }
        }
      } catch (e) {
        print("Error getting/sending FCM token: $e");
      }
    });

    _socket.onConnectError((data) {
      print("Connection Error: $data");
    });

    _socket.on('update-user-list', (data) {
      if (data is List) {
        _users = List<Map<String, dynamic>>.from(data);
        onUserListUpdated?.call(_users);
      }
    });

    _socket.on('user-joined', (data) {
      print('User joined: $data');
      onUserJoined?.call(data.toString());
    });

    _socket.on('offer', (data) {
      print(
        'Received offer from ${data['sender']}',
      ); // 'sender' is now username
      // If we have an active listener (CallScreen), pass it there.
      // Otherwise, it's a new incoming call (HomeScreen).
      if (onOffer != null) {
        onOffer?.call(Map<String, dynamic>.from(data));
      } else {
        // Trigger generic callback (e.g. for Home Screen listener if needed)
        onIncomingCall?.call(Map<String, dynamic>.from(data));

        // Show Native UI
        _callKitService.showIncomingCall(Map<String, dynamic>.from(data));
      }
    });

    _socket.on('answer', (data) {
      print('Received answer');
      onAnswer?.call(Map<String, dynamic>.from(data));
    });

    // Modified ICE listener to buffer candidates
    _socket.on('ice-candidate', (data) {
      print('Received ICE candidate');
      if (_onIceCandidate != null) {
        _onIceCandidate?.call(Map<String, dynamic>.from(data));
      } else {
        print('Buffering ICE candidate');
        _iceCandidateQueue.add(Map<String, dynamic>.from(data));
      }
    });

    _socket.on('end-call', (data) {
      print('Received end-call signal');
      onCallEnded?.call(Map<String, dynamic>.from(data));
      _callKitService.endAllCalls(); // Ensure native UI is also dismissed
    });

    _socket.onDisconnect((_) => print('Disconnected from signaling server'));
  }

  String? _currentUsername;

  void login(String username) {
    _currentUsername = username;
    _socket.emit('login', username);
  }

  void sendOffer(Map<String, dynamic> offer, String targetUsername) {
    _socket.emit('offer', {
      'target': targetUsername,
      'sdp': offer['sdp'],
      'type': offer['type'],
    });
  }

  void sendAnswer(Map<String, dynamic> answer, String targetUsername) {
    _socket.emit('answer', {
      'target': targetUsername,
      'sdp': answer['sdp'],
      'type': answer['type'],
    });
  }

  void sendIceCandidate(Map<String, dynamic> candidate, String targetUsername) {
    _socket.emit('ice-candidate', {
      'target': targetUsername,
      'candidate': candidate,
    });
  }

  void sendEndCall(String targetUsername) {
    _socket.emit('end-call', {'target': targetUsername});
  }

  Future<List<Map<String, dynamic>>> getIceServers() async {
    Completer<List<Map<String, dynamic>>> completer = Completer();
    _socket.emitWithAck(
      'get-ice-servers',
      [],
      ack: (data) {
        if (data is List) {
          completer.complete(List<Map<String, dynamic>>.from(data));
        } else {
          completer.complete([]);
        }
      },
    );
    return completer.future;
  }
}
