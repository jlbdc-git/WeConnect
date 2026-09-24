/// A chat message. Mirrors the `messages` table.
class Message {
  const Message({
    required this.id,
    required this.channelId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.editedAt,
  });

  final String id;
  final String channelId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime? editedAt;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      channelId: json['channel_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.parse(json['edited_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel_id': channelId,
        'sender_id': senderId,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
      };
}
