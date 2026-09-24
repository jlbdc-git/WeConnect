import '../errors/app_exception.dart';

/// A minimal Result type for explicit, exhaustive error handling without
/// pulling in fp-style packages. Keeps repository/service APIs honest.
sealed class Result<T> {
  const Result();

  factory Result.ok(T value) = Ok<T>;
  factory Result.err(AppException error) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Returns the value if ok, otherwise null.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// Returns the value, or throws the [AppException].
  T get orThrow => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final error) => throw error,
      };

  /// Pattern-matches without exceptions.
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppException error) err,
  }) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final error) => err(error),
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.error);
  final AppException error;
}
