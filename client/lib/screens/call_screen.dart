import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SignalingService _signalingService = SignalingService();
  late WebRTCService _webRTCService;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final TextEditingController _targetController = TextEditingController();
  String? _selfId;
  bool _inCall = false;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    _webRTCService = WebRTCService(_signalingService);

    _webRTCService.onLocalStream = (stream) {
      setState(() {
        _localRenderer.srcObject = stream;
      });
    };

    _webRTCService.onRemoteStream = (stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    };

    // Open user media on load
    _webRTCService.openUserMedia(_localRenderer, _remoteRenderer);

    // Listen for remote hangup
    _signalingService.onCallEnded = (data) {
      if (mounted) {
        _webRTCService.disconnect();
        _webRTCService.disconnect();
        // Do not switch to "not in call" state to avoid UI flash
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Call ended by remote user")),
        );
      }
    };
  }

  @override
  void dispose() {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    // Clean up listener to avoid side effects?
    // Ideally SignalingService handles multiple listeners or we null it.
    // For now, this is fine as CallScreen is pushed/popped.
    _signalingService.onCallEnded = null;

    _webRTCService.disconnect();
    super.dispose();
  }

  void _makeCall() {
    if (_targetController.text.isNotEmpty) {
      _webRTCService.call(_targetController.text);
      setState(() {
        _inCall = true;
      });
    }
  }

  void _hangUp() {
    if (_targetController.text.isNotEmpty) {
      _signalingService.sendEndCall(_targetController.text);
    }

    _webRTCService.disconnect();
    _webRTCService.disconnect();
    // Do not switch to "not in call" state to avoid UI flash
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _selfId = args['selfId'];

      // Case 1: Outgoing call (we have a targetId)
      final target = args['targetId'];
      if (target != null && _targetController.text.isEmpty) {
        _targetController.text = target;
        if (!_inCall) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _makeCall();
          });
        }
      }

      // Case 2: Incoming call (we accepted an offer)
      final offer = args['offer'];
      if (offer != null && !_inCall) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // We set _inCall to true visually, handleOffer does the rest
          setState(() {
            _inCall = true;
            _targetController.text = offer['sender'] ?? 'Unknown';
          });
          await _webRTCService.openUserMedia(_localRenderer, _remoteRenderer);
          await _webRTCService.handleOffer(offer);
        });
      }
    } else if (args is String) {
      _selfId = args;
    }

    return Scaffold(
      appBar: AppBar(title: Text('Call ${_selfId ?? ""}')),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.black54),
                        child: RTCVideoView(_localRenderer, mirror: true),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.black54),
                        child: RTCVideoView(_remoteRenderer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: !_inCall
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetController,
                      decoration: const InputDecoration(
                        labelText: 'Enter Target ID to Call',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.person),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _makeCall,
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.call),
                    heroTag: "call_btn",
                  ),
                ],
              ),
            )
          : null,
      floatingActionButton: _inCall
          ? FloatingActionButton(
              onPressed: _hangUp,
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end),
              heroTag: "hangup_btn",
            )
          : FloatingActionButton(
              onPressed: _webRTCService.switchCamera,
              child: const Icon(Icons.switch_camera),
              heroTag: "switch_cam_btn",
            ),
      floatingActionButtonLocation: _inCall
          ? FloatingActionButtonLocation.centerFloat
          : FloatingActionButtonLocation.endFloat,
    );
  }
}
