/// A tiny logger that respects release-mode silencing and never logs
/// sensitive values. Wire to `dart:developer` log in the future if needed.
class AppLog {
  AppLog._();

  static void d(String message) {
    assert(() {
      // ignore: avoid_print
      print('[D] $message');
      return true;
    }());
  }

  static void w(String message) {
    assert(() {
      // ignore: avoid_print
      print('[W] $message');
      return true;
    }());
  }

  static void e(String message, [Object? error, StackTrace? stack]) {
    // Errors are logged in release too, but never include secrets.
    // ignore: avoid_print
    print('[E] $message error=$error');
    if (stack != null) {
      // ignore: avoid_print
      print('[E] $stack');
    }
  }
}
