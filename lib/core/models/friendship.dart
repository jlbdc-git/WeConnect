import 'profile.dart';

/// The status of a friendship row between two profiles.
enum FriendshipStatus { pending, accepted, declined }

FriendshipStatus friendshipStatusFromDb(String? s) =>
    FriendshipStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => FriendshipStatus.pending,
    );

/// A row of the `friendships` table.
class Friendship {
  const Friendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendshipStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Friendship.fromJson(Map<String, dynamic> json) {
    return Friendship(
      id: json['id'] as String,
      requesterId: json['requester_id'] as String,
      addresseeId: json['addressee_id'] as String,
      status: friendshipStatusFromDb(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Who is "the other person" from [viewerId]'s perspective.
  String otherUser(String viewerId) =>
      viewerId == requesterId ? addresseeId : requesterId;

  bool involves(String userId) =>
      requesterId == userId || addresseeId == userId;
}

/// A friend or pending-request entry rendered in the friends list.
/// Bundles the friendship row with the *other* user's profile.
class FriendEntry {
  const FriendEntry({required this.friendship, required this.profile});

  final Friendship friendship;
  final Profile profile;

  bool get isAccepted => friendship.status == FriendshipStatus.accepted;
  bool get isPending => friendship.status == FriendshipStatus.pending;

  /// True when [profile] (the other user) is the requester of this row,
  /// i.e. the viewer received this pending request.
  bool get isIncoming => friendship.requesterId == profile.id;

  /// True when the viewer sent this request.
  bool get isOutgoing => !isIncoming;
}
