/// Mirrors the `voice_participants` table — who is in which voice channel.
class VoiceParticipant {
  const VoiceParticipant({
    required this.channelId,
    required this.profileId,
    required this.serverId,
    required this.joinedAt,
  });

  final String channelId;
  final String profileId;
  final String serverId;
  final DateTime joinedAt;

  factory VoiceParticipant.fromDbJson(Map<String, dynamic> json) {
    return VoiceParticipant(
      channelId: json['channel_id'] as String,
      profileId: json['profile_id'] as String,
      serverId: json['server_id'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}
