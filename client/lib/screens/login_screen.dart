import 'package:flutter/material.dart';
import '../services/signaling_service.dart';

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
