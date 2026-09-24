/// Application constants shared across features.
class AppConstants {
  AppConstants._();

  /// Maximum simultaneous voice users per channel (server-enforced).
  static const int maxVoiceUsers = 20;

  /// Messages per page when loading channel history.
  static const int messagesPageSize = 50;

  /// Characters per username segment.
  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 32;
}
