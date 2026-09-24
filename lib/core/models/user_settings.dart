enum VoiceMode { voiceActivity, pushToTalk }

VoiceMode voiceModeFromDb(String? s) =>
    s == 'push_to_talk' ? VoiceMode.pushToTalk : VoiceMode.voiceActivity;

/// DB stores snake_case (enforced by a CHECK constraint); Dart enum names
/// are camelCase, so never rely on `.name` here.
String voiceModeToDb(VoiceMode m) =>
    m == VoiceMode.pushToTalk ? 'push_to_talk' : 'voice_activity';

/// User settings synced via the `user_settings` table (per-user row).
class UserSettings {
  const UserSettings({
    this.theme = 'system',
    this.voiceMode = VoiceMode.voiceActivity,
    this.pttKey = 'V',
    this.pttMouseButton = 0,
    this.micDeviceId,
    this.speakerDeviceId,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.vadSensitivity = 50,
  });

  final String theme;
  final VoiceMode voiceMode;

  /// Windows: keyboard key name for push-to-talk (e.g. 'V', 'Space', 'LAlt').
  final String pttKey;

  /// Windows: extra mouse button. 0=none, 4=XBUTTON1, 5=XBUTTON2, 6=middle.
  final int pttMouseButton;

  final String? micDeviceId;
  final String? speakerDeviceId;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;

  /// 0..100 — higher means the user must speak louder to activate.
  final int vadSensitivity;

  UserSettings copyWith({
    String? theme,
    VoiceMode? voiceMode,
    String? pttKey,
    int? pttMouseButton,
    String? micDeviceId,
    String? speakerDeviceId,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGainControl,
    int? vadSensitivity,
  }) {
    return UserSettings(
      theme: theme ?? this.theme,
      voiceMode: voiceMode ?? this.voiceMode,
      pttKey: pttKey ?? this.pttKey,
      pttMouseButton: pttMouseButton ?? this.pttMouseButton,
      micDeviceId: micDeviceId ?? this.micDeviceId,
      speakerDeviceId: speakerDeviceId ?? this.speakerDeviceId,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      autoGainControl: autoGainControl ?? this.autoGainControl,
      vadSensitivity: vadSensitivity ?? this.vadSensitivity,
    );
  }

  factory UserSettings.fromDbJson(Map<String, dynamic> json) {
    return UserSettings(
      theme: (json['theme'] as String?) ?? 'system',
      voiceMode: voiceModeFromDb(json['voice_mode'] as String?),
      pttKey: (json['ptt_key'] as String?) ?? 'V',
      pttMouseButton: (json['ptt_mouse_button'] as num?)?.toInt() ?? 0,
      micDeviceId: json['mic_device_id'] as String?,
      speakerDeviceId: json['speaker_device_id'] as String?,
      noiseSuppression: (json['noise_suppression'] as bool?) ?? true,
      echoCancellation: (json['echo_cancellation'] as bool?) ?? true,
      autoGainControl: (json['auto_gain_control'] as bool?) ?? true,
      vadSensitivity: (json['vad_sensitivity'] as num?)?.toInt() ?? 50,
    );
  }

  Map<String, dynamic> toDbJson() => {
        'theme': theme,
        'voice_mode': voiceModeToDb(voiceMode),
        'ptt_key': pttKey,
        'ptt_mouse_button': pttMouseButton,
        'mic_device_id': micDeviceId,
        'speaker_device_id': speakerDeviceId,
        'noise_suppression': noiseSuppression,
        'echo_cancellation': echoCancellation,
        'auto_gain_control': autoGainControl,
        'vad_sensitivity': vadSensitivity,
      };
}
