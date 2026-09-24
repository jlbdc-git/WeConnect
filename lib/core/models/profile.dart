import 'package:supabase_flutter/supabase_flutter.dart';

/// A user's public profile. Mirrors the `profiles` table.
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.tag,
    this.lastSeenAt,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int tag;
  final DateTime? lastSeenAt;

  /// What to show in the UI.
  String get effectiveName => displayName.isNotEmpty ? displayName : username;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: (json['display_name'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      tag: (json['tag'] as num?)?.toInt() ?? 0,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'tag': tag,
        'last_seen_at': lastSeenAt?.toIso8601String(),
      };

  /// Convenience for tests/debug.
  @override
  String toString() => 'Profile($username#$tag)';
}

/// Parses the supabase `User` into a lightweight local user handle.
Profile profileFromAuthUser(User user) {
  final md = user.userMetadata ?? const {};
  return Profile(
    id: user.id,
    username: (md['username'] as String?) ?? (user.email?.split('@').first ?? 'user'),
    displayName: (md['display_name'] as String?) ?? '',
    tag: 0,
  );
}
