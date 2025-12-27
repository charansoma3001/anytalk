import 'package:flutter/material.dart';
import '../services/signaling_service.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _controller = TextEditingController();
  final SignalingService _signalingService = SignalingService();

  void _join() {
    if (_controller.text.isNotEmpty) {
      _signalingService.connect();
      // Allow connection to establish
      Future.delayed(const Duration(milliseconds: 500), () {
        _signalingService.login(_controller.text);
        Navigator.pushReplacementNamed(
          context,
          '/home',
          arguments: _controller.text,
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _checkCallKitEvents();
  }

  Future<void> _checkCallKitEvents() async {
    try {
      var calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List && calls.isNotEmpty) {
        print("Found active call on startup: ${calls.first}");
        // If there is an active call, we can assume the user wants to be in it.
        // The payload is in 'extra'.
        _handleCallAccept(Map<String, dynamic>.from(calls.first));

        // Also clear the system notification now that we are handling it
        // (Or we leave it until we are in CallScreen? CallScreen disposes it).
      }
    } catch (e) {
      print("Error checking CallKit events: $e");
    }
  }

  void _handleCallAccept(Map<String, dynamic> body) {
    if (body['extra'] == null) return;
    final data = Map<String, dynamic>.from(body['extra']);
    final selfId = data['target']; // The one who was called (us)

    if (selfId != null) {
      print("Auto-logging in and answering call for $selfId");
      _controller.text = selfId; // Fill UI

      _signalingService.connect();
      // Wait for connection then navigate
      Future.delayed(const Duration(milliseconds: 500), () {
        _signalingService.login(selfId);

        Navigator.pushReplacementNamed(
          context,
          '/call',
          arguments: {
            'selfId': selfId,
            'offer': data, // Pass the offer so we can answer immediately
          },
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AnyTalk Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Enter your ID'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _join, child: const Text('Join')),
          ],
        ),
      ),
    );
  }
}
