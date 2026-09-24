/// A private group (Discord-like "server"). Mirrors the `servers` table.
class Server {
  const Server({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
    this.iconUrl,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;
  final String? iconUrl;
  final DateTime createdAt;

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      inviteCode: json['invite_code'] as String,
      iconUrl: json['icon_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A channel within a server (text or voice).
class Channel {
  const Channel({
    required this.id,
    required this.serverId,
    required this.name,
    required this.kind,
    required this.position,
  });

  final String id;
  final String serverId;
  final String name;
  final String kind; // 'text' | 'voice'
  final int position;

  bool get isVoice => kind == 'voice';
  bool get isText => kind == 'text';

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String,
      serverId: json['server_id'] as String,
      name: json['name'] as String,
      kind: (json['kind'] as String?) ?? 'text',
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Membership row: who belongs to a server.
class ServerMember {
  const ServerMember({required this.serverId, required this.profileId});

  final String serverId;
  final String profileId;

  factory ServerMember.fromJson(Map<String, dynamic> json) =>
      ServerMember(
        serverId: json['server_id'] as String,
        profileId: json['profile_id'] as String,
      );
}
