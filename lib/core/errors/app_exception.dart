/// Unified application exception type.
///
/// Every repository/service throws [AppException] so the UI can show a
/// single, predictable error surface (code + human message) without
/// depending on supabase/webrtc internals.
class AppException implements Exception {
  const AppException(this.code, {this.message, this.cause});

  /// Stable machine-readable identifier, e.g. 'network', 'auth_invalid_login'.
  final String code;

  /// Human-readable message safe to show in the UI.
  final String? message;

  /// Original error, for logging only — never shown to the user.
  final Object? cause;

  @override
  String toString() => 'AppException($code): ${message ?? cause}';
}

/// Common error factories so mapping logic lives in one place.
class AppErrors {
  const AppErrors._();

  static const network = AppException(
    'network',
    message: 'No connection. Check your internet and try again.',
  );
  static const unknown = AppException(
    'unknown',
    message: 'Something went wrong. Please try again.',
  );

  static AppException from(Object error, {String? context}) {
    if (error is AppException) return error;
    final s = error.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('connection') ||
        s.contains('network')) {
      return network;
    }
    return AppException('unknown', message: context, cause: error);
  }
}
