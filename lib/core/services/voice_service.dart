import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webrtc_interface/webrtc_interface.dart' show MediaStreamTrack;
import '../errors/app_exception.dart';
import 'voice_gate.dart';

/// Connection state exposed to the UI.
enum VoiceConnState { disconnected, connecting, connected, reconnecting, failed }

/// High-level voice feature service built on LiveKit (WebRTC SFU).
///
/// Join flow:
///   UI → join() → POST {edge}/voice-token (Supabase JWT authorizes;
///   server verifies membership + 20-user cap) → lk.Room.connect(url, token)
///   → publish mic → gate attached → upsert voice_participants.
///
/// All audio flows through the SFU: each client publishes ONE track and
/// receives N-1 (no mesh). Mute gates the local track; deafen disables
/// remote publications. Both are instant local operations.
///
/// IMPORTANT: `stopAudioCaptureOnMute` is disabled. With the LiveKit
/// default (true), a mute STOPS capture and destroys the underlying
/// MediaStreamTrack; unmuting creates a NEW track, leaving our VoiceGate
/// writing `enabled` into a dead track — PTT would keep transmitting.
/// Keeping capture alive makes track identity stable for the gate's
/// lifetime, and `track.enabled = false` is itself a real media gate
/// (no frames are captured or sent).
class VoiceService {
  VoiceService({required this.supabase, required String edgeFunctionBase})
      : _edgeBase = edgeFunctionBase;

  final SupabaseClient supabase;
  final String _edgeBase;

  lk.Room? _room;
  VoiceGate? _gate;
  final List<lk.CancelListenFunc> _cancelFns = [];
  bool _deafened = false;
  VoiceConnState _state = VoiceConnState.disconnected;
  final _stateCtrl = StreamController<VoiceConnState>.broadcast();
  final _speakingCtrl = StreamController<Map<String, bool>>.broadcast();

  // ---- exposed state ------------------------------------------------------
  VoiceConnState get state => _state;
  String? currentChannelId;
  String? currentServerId;
  bool get isMuted => _gate?.muted ?? false;
  bool get isDeafened => _deafened;
  bool get isInVoice => _room != null;

  Stream<VoiceConnState> get onConnState => _stateCtrl.stream;
  Stream<Map<String, bool>> get onSpeaking => _speakingCtrl.stream;

  // ---- join/leave ---------------------------------------------------------
  Future<void> join({
    required String channelId,
    required String serverId,
    required bool pttMode,
    required int vadSensitivity,
    required bool noiseSuppression,
    required bool echoCancellation,
    required bool autoGainControl,
  }) async {
    if (_room != null) {
      throw const AppException('voice_busy',
          message: 'Already in a voice channel.');
    }
    _setState(VoiceConnState.connecting);
    currentChannelId = channelId;
    currentServerId = serverId;

    try {
      final tokenInfo = await _fetchToken(channelId);

      final room = lk.Room(
        roomOptions: lk.RoomOptions(
          // adaptiveStream/dynacast stay at their defaults (false): audio-only
          // app, no bitrate adaptation needed. dtx+red defaults are ideal for
          // voice: silence is not transmitted (dtx) and packets are redundant
          // (red) for loss resilience.
          defaultAudioCaptureOptions: lk.AudioCaptureOptions(
            noiseSuppression: noiseSuppression,
            echoCancellation: echoCancellation,
            autoGainControl: autoGainControl,
            // Keep the MediaStreamTrack alive across mute/unmute so the
            // VoiceGate's `enabled` toggles always hit the live track.
            // (See class doc: the LiveKit default creates a new track on
            // unmute, which would silently break PTT.)
            stopAudioCaptureOnMute: false,
          ),
        ),
      );
      _room = room;

      final listener = room.createListener(synchronized: true);
      listener
        ..on<lk.ParticipantConnectedEvent>((_) => _emitSpeaking())
        ..on<lk.ParticipantDisconnectedEvent>((_) => _emitSpeaking())
        ..on<lk.TrackMutedEvent>((_) => _emitSpeaking())
        ..on<lk.TrackUnmutedEvent>((_) => _emitSpeaking())
        ..on<lk.ActiveSpeakersChangedEvent>((event) {
          // LiveKit server-side VAD: which identities are speaking right now.
          final speakingIds = event.speakers.map((s) => s.identity).toSet();
          _gate?.setExternalSpeaking(speakingIds.contains(_localIdentity));
          _emitSpeaking(externalSpeakingIds: speakingIds);
        })
        ..on<lk.RoomDisconnectedEvent>((_) async {
          _setState(VoiceConnState.disconnected);
          await _cleanup();
        })
        ..on<lk.RoomReconnectingEvent>(
            (_) => _setState(VoiceConnState.reconnecting))
        ..on<lk.RoomReconnectedEvent>((_) => _setState(VoiceConnState.connected));
      _cancelFns.add(listener.dispose);

      await room.connect(
        tokenInfo.url,
        tokenInfo.token,
        fastConnectOptions: lk.FastConnectOptions(
          microphone: const lk.TrackOption(enabled: true),
        ),
      );

      // Publish local mic (audio processing configured via capture options).
      await room.localParticipant?.setMicrophoneEnabled(true);

      // Attach the shared gate to the local mic track.
      final pubs = room.localParticipant?.trackPublications.values
          .whereType<lk.LocalTrackPublication<lk.LocalAudioTrack>>()
          .toList();
      final gate = VoiceGate(onSpeakingChanged: (_) => _emitSpeaking());
      gate.configure(pttMode: pttMode, vadSensitivity: vadSensitivity);
      final nativeTrack = pubs?.firstOrNull?.track?.mediaStreamTrack;
      await gate
          .attach(nativeTrack == null ? null : _GateTrackAdapter(nativeTrack));
      _gate = gate;

      // Mirror occupancy for other clients (Supabase Realtime).
      await supabase.from('voice_participants').upsert({
        'channel_id': channelId,
        'profile_id': supabase.auth.currentUser!.id,
        'server_id': serverId,
      });

      _setState(VoiceConnState.connected);
      _emitSpeaking();
    } on AppException {
      await _cleanup();
      rethrow;
    } catch (e) {
      await _cleanup();
      throw AppErrors.from(e, context: 'Voice join failed');
    }
  }

  Future<void> leave() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      try {
        await supabase.from('voice_participants').delete().eq('profile_id', uid);
      } catch (_) {
        // best-effort; the LiveKit disconnect is authoritative
      }
    }
    await _cleanup();
    _setState(VoiceConnState.disconnected);
  }

  // ---- controls ------------------------------------------------------------
  Future<void> setMuted(bool value) async {
    _gate?.setMuted(value);
    // Also signal mute metadata so other clients' UIs update.
    await _room?.localParticipant?.setMicrophoneEnabled(!value);
  }

  void setDeafened(bool value) {
    _deafened = value;
    final room = _room;
    if (room == null) return;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (value) {
          pub.disable();
        } else {
          pub.enable();
        }
      }
    }
  }

  void setPttPressed(bool pressed) => _gate?.setPttPressed(pressed);

  void applySettings({required bool pttMode, required int vadSensitivity}) {
    _gate?.configure(pttMode: pttMode, vadSensitivity: vadSensitivity);
    _gate?.refreshMode();
  }

  String? get _localIdentity =>
      supabase.auth.currentUser?.id ?? _room?.localParticipant?.identity;

  void _setState(VoiceConnState s) {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
  }

  // ---- token fetch ---------------------------------------------------------
  Future<_TokenInfo> _fetchToken(String channelId) async {
    final jwt = supabase.auth.currentSession?.accessToken;
    if (jwt == null) {
      throw const AppException('voice_auth', message: 'Not signed in.');
    }
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$_edgeBase/voice-token'),
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'channel_id': channelId}),
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const AppException('voice_unreachable',
          message: 'Voice server timed out. Try again.');
    } catch (_) {
      throw const AppException('voice_unreachable',
          message: 'Voice server unreachable. Try again later.');
    }

    if (res.statusCode != 200) {
      final body = _decodeBody(res.body);
      final code = body['error'] as String?;
      if (res.statusCode == 409 ||
          code == 'CHANNEL_FULL' ||
          code == 'room is full') {
        throw AppException(
          'voice_channel_full',
          message: 'That voice channel is full (20 max).',
        );
      }
      throw AppException(
        'voice_join_denied',
        message: code ?? 'Voice server rejected join.',
      );
    }

    final body = _decodeBody(res.body);
    final token = body['token'] as String?;
    final url = body['url'] as String?;
    if (token == null || url == null || url.isEmpty) {
      throw const AppException('voice_join_denied',
          message: 'Voice server returned an incomplete response.');
    }
    return _TokenInfo(
      token: token,
      url: url,
      roomName: body['roomName'] as String? ?? 'wc_$channelId',
    );
  }

  // ---- events --------------------------------------------------------------
  void _emitSpeaking({Set<String>? externalSpeakingIds}) {
    final room = _room;
    if (room == null) {
      _speakingCtrl.add(const {});
      return;
    }
    final map = <String, bool>{};
    for (final p in room.remoteParticipants.values) {
      map[p.identity] =
          externalSpeakingIds?.contains(p.identity) ?? p.isSpeaking;
    }
    if (_gate != null) {
      map[supabase.auth.currentUser?.id ?? 'me'] = _gate!.speaking;
    }
    _speakingCtrl.add(map);
  }

  Future<void> _cleanup() async {
    for (final cancel in _cancelFns) {
      try {
        await cancel();
      } catch (_) {}
    }
    _cancelFns.clear();
    _gate?.dispose();
    _gate = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
    currentChannelId = null;
    currentServerId = null;
    _deafened = false;
  }

  Future<void> dispose() async {
    await _cleanup();
    await _stateCtrl.close();
    await _speakingCtrl.close();
  }
}

Map<String, dynamic> _decodeBody(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}

class _TokenInfo {  const _TokenInfo({
    required this.token,
    required this.url,
    required this.roomName,
  });

  final String token;
  final String url;
  final String roomName;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
/// Adapts the flutter_webrtc MediaStreamTrack to the gate's minimal
/// [GateTrack] interface (enabled flag only). Typed via the
/// webrtc_interface contract instead of `dynamic`.
class _GateTrackAdapter implements GateTrack {
  _GateTrackAdapter(this._track);

  final MediaStreamTrack _track;

  @override
  bool get enabled => _track.enabled;

  @override
  set enabled(bool value) => _track.enabled = value;
}
