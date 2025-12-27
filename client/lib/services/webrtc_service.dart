import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

class WebRTCService {
  final SignalingService signalingService;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _remoteId;

  // Callbacks for UI
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;

  WebRTCService(this.signalingService) {
    _setupSignalingListeners();
  }

  void _setupSignalingListeners() {
    signalingService.onOffer = (data) async {
      print(
        "Processing offer from: ${data['target']}",
      ); // 'target' in payload might be 'sender' depending on server logic
      // In this simple server implementation, target in 'offer' from server is actually correct?
      // Server code: io.to(payload.target).emit("offer", payload);
      // Payload sent by OFF & ANS contains 'target'.
      // We need to know who SENT the offer.
      // The current server code just relays the payload.
      // So the payload MUST contain a 'sender' field if we want to know who sent it.
      // Modifying server might be needed, but for now let's assume 1-1 simple logic or the valid payload structure.

      // We will assume payload has 'sdp' and 'type'.
      await handleOffer(data);
    };

    signalingService.onAnswer = (data) async {
      await _handleAnswer(data);
    };

    signalingService.onIceCandidate = (data) async {
      await _handleIceCandidate(data);
    };
  }

  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo,
  ) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {'facingMode': 'user'},
    };

    try {
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = stream;
      onLocalStream?.call(stream);
      localVideo.srcObject = _localStream;
    } catch (e) {
      print(e.toString());
    }
  }

  // Initialize Peer Connection
  Future<void> _createPeerConnection() async {
    List<Map<String, dynamic>> iceServers = await signalingService
        .getIceServers();

    Map<String, dynamic> configuration = {
      "iceServers": iceServers.isNotEmpty
          ? iceServers
          : [
              {"urls": "stun:stun.l.google.com:19302"},
            ],
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {"OfferToReceiveAudio": true, "OfferToReceiveVideo": true},
      "optional": [],
    };

    _peerConnection = await createPeerConnection(
      configuration,
      offerSdpConstraints,
    );

    // Unified Plan is standard now
    // configurations explicitly? flutter_webrtc usually defaults to unified plan now but good to be sure if issues arise.
    // Actually, createPeerConnection takes constraints as 2nd arg. Configuration is 1st.
    // To set sdpSemantics, we put it in configuration.

    /*
    Map<String, dynamic> configuration = {
      "iceServers": ...,
      "sdpSemantics": "unified-plan"
    };
    */

    // Let's rely on default for semantics or set it if needed.
    // For now, let's focus on codec forcing.

    _peerConnection!.onIceCandidate = (candidate) {
      if (_remoteId != null) {
        signalingService.sendIceCandidate({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }, _remoteId!);
      }
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    // Add local stream
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    }
  }

  Future<void> call(String targetId) async {
    _remoteId = targetId;
    await _createPeerConnection();

    RTCSessionDescription offer = await _peerConnection!.createOffer();

    // Force H264
    var sdp = _forceCodec(offer.sdp!, 'H264');
    RTCSessionDescription safeOffer = RTCSessionDescription(sdp, offer.type);

    await _peerConnection!.setLocalDescription(safeOffer);

    signalingService.sendOffer({
      'sdp': safeOffer.sdp,
      'type': safeOffer.type,
    }, targetId);
  }

  // Queue for candidates arriving before RemoteDescription is set
  final List<RTCIceCandidate> _iceCandidatesQueue = [];

  Future<void> handleOffer(Map<String, dynamic> data) async {
    // ... (logic)

    await _createPeerConnection();

    // ... (logic)

    var sdp = data['sdp'];
    var type = data['type'];

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
    print("WebRTCService: Remote Description Set (Offer)");

    // Flush any queued candidates
    _flushIceCandidateQueue();

    RTCSessionDescription answer = await _peerConnection!.createAnswer();

    // Force H264 on Answer too
    var answerSdp = _forceCodec(answer.sdp!, 'H264');
    RTCSessionDescription safeAnswer = RTCSessionDescription(
      answerSdp,
      answer.type,
    );

    await _peerConnection!.setLocalDescription(safeAnswer);

    // ... (logic)
    if (data.containsKey('sender')) {
      _remoteId = data['sender'];
      signalingService.sendAnswer({
        'sdp': safeAnswer.sdp,
        'type': safeAnswer.type,
      }, _remoteId!);
    }
  }

  // ... (rest of methods)

  // ... (rest of methods until end of class)

  // Helper to force codec
  String _forceCodec(String sdp, String codec) {
    var lines = sdp.split('\n');
    var mLineIndex = -1;
    var codecMap = <String, String>{};
    var priorityParams = <String>[];

    // Find m=video line
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.startsWith('m=video')) {
        mLineIndex = i;
        continue;
      }

      // Parse rtpmap lines
      if (mLineIndex != -1 && line.startsWith('a=rtpmap:')) {
        // format: a=rtpmap:<payload_type> <encoding_name>/<clock_rate>
        var parts = line.substring(9).split(' ');
        if (parts.length == 2) {
          var payloadType = parts[0];
          var codecName = parts[1].split('/')[0];
          codecMap[payloadType] = codecName;
        }
      }
    }

    if (mLineIndex == -1) return sdp; // No video line

    // Identify payload types for desired codec
    var desiredPayloads = <String>[];
    codecMap.forEach((key, value) {
      if (value.toUpperCase() == codec.toUpperCase()) {
        desiredPayloads.add(key);
      }
    });

    if (desiredPayloads.isEmpty) return sdp; // Desired codec not found

    // Reconstruct m=video line
    var mLine = lines[mLineIndex];
    var mParts = mLine.split(' ');
    // Validation: m=video <port> <proto> <payloads...>
    if (mParts.length < 4) return sdp;

    var newMLine = [mParts[0], mParts[1], mParts[2]];
    newMLine.addAll(desiredPayloads); // Put desired first

    // Add rest
    for (var i = 3; i < mParts.length; i++) {
      if (!desiredPayloads.contains(mParts[i])) {
        newMLine.add(mParts[i]);
      }
    }

    lines[mLineIndex] = newMLine.join(' ');
    return lines.join('\n');
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    var sdp = data['sdp'];
    var type = data['type'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
    print("WebRTCService: Remote Description Set (Answer)");

    // Flush any queued candidates
    _flushIceCandidateQueue();
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    var candidate = RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );

    bool remoteDescriptionSet = false;
    if (_peerConnection != null) {
      // Check if remote description is set.
      var desc = await _peerConnection!.getRemoteDescription();
      if (desc != null) {
        remoteDescriptionSet = true;
      }
    }

    if (remoteDescriptionSet && _peerConnection != null) {
      print('Adding ICE candidate immediately');
      await _peerConnection!.addCandidate(candidate);
    } else {
      print(
        'Buffering ICE candidate (PC null or Remote Description not ready)',
      );
      _iceCandidatesQueue.add(candidate);
    }
  }

  Future<void> _flushIceCandidateQueue() async {
    if (_peerConnection == null) return;

    print('Flushing ${_iceCandidatesQueue.length} buffered ICE candidates');
    for (var candidate in _iceCandidatesQueue) {
      await _peerConnection!.addCandidate(candidate);
    }
    _iceCandidatesQueue.clear();
  }

  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
    }
  }

  void disconnect() {
    // Clear signaling listeners to allow fresh incoming calls
    signalingService.onOffer = null;
    signalingService.onAnswer = null;
    signalingService.onIceCandidate = null;

    if (_localStream != null) {
      print('Disposing local stream and tracks');
      _localStream!.getTracks().forEach((track) {
        track.stop();
        print('Stopped track: ${track.id}');
      });
      _localStream!.dispose();
      _localStream = null;
    }
    if (_peerConnection != null) {
      print('Closing peer connection');
      _peerConnection!.close();
      _peerConnection = null;
    }
  }
}
