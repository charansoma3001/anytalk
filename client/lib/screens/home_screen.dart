import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/signaling_service.dart';
import '../services/callkit_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SignalingService _signalingService = SignalingService();
  // List of {username, online}
  List<Map<String, dynamic>> _users = [];
  String? _selfId;

  @override
  void initState() {
    super.initState();

    // Initialize with current state
    _users = _signalingService.users;

    // Setup listener
    _signalingService.onUserListUpdated = (users) {
      if (mounted) {
        setState(() {
          _users = users;
        });
      }
    };

    // Generic Incoming Call Listener (Fallback for Desktop/Web or when app is in foreground if desired)
    _signalingService.onIncomingCall = (data) {
      print("Incoming call received: $data"); // DEBUG LOG
      // If we are on Desktop/Web, show the dialog
      // (On Mobile, CallKit handles the notification, but if app is open, we might want this too?
      //  For now, let's strictly use Dialog for non-mobile)
      if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
        if (mounted) {
          print("Showing incoming call dialog (Desktop Mode)"); // DEBUG LOG
          _showIncomingCallDialog(data);
        }
      }
    };

    // Native CallKit Listener (Mobile Only)
    CallKitService().onCallAccepted = (data) {
      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        Navigator.pushNamed(
          context,
          '/call',
          arguments: {'selfId': _selfId, 'offer': data},
        );
      }
    };

    // Check if we are on Android TV and need to override CallKit behavior
    _checkAndroidTV();
  }

  Future<void> _checkAndroidTV() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      // 'android.software.leanback' indicates Android TV
      final isTV = androidInfo.systemFeatures.contains(
        'android.software.leanback',
      );

      if (isTV) {
        // If it's TV, we want to use the In-App Dialog, NOT CallKit.
        // We override the onIncomingCall listener for this specific case.
        _signalingService.onIncomingCall = (data) {
          if (mounted) {
            _showIncomingCallDialog(data);
          }
        };
      }
    }
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Incoming Call"),
        content: Text("Incoming call from ${data['sender'] ?? 'Unknown'}"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Decline implicitly by doing nothing (for now)
            },
            child: const Text("Decline"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushNamed(
                context,
                '/call',
                arguments: {
                  'selfId': _selfId,
                  'offer': data, // Pass the offer payload
                },
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String) {
      _selfId = args;
    }

    // Logic:
    // The list is [{username, online}, ...]
    // We want to exclude "Me" (based on _selfId).
    final otherUsers = _users.where((u) => u['username'] != _selfId).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Users (${_selfId ?? "Unknown"})')),
      body: otherUsers.isEmpty
          ? const Center(child: Text("No other users found"))
          : ListView.builder(
              itemCount: otherUsers.length,
              itemBuilder: (context, index) {
                var user = otherUsers[index];
                String username = user['username'];
                bool isOnline = user['online'] == true;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isOnline ? Colors.green : Colors.grey,
                    radius: 10,
                  ),
                  title: Text(username),
                  subtitle: Text(isOnline ? "Online" : "Offline"),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.video_call,
                      color: isOnline ? Colors.green : Colors.grey,
                    ),
                    onPressed: () => _callUser(username),
                  ),
                );
              },
            ),
    );
  }

  void _callUser(String targetUsername) {
    Navigator.pushNamed(
      context,
      '/call',
      arguments: {'selfId': _selfId, 'targetId': targetUsername},
    );
  }
}
