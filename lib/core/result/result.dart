import '../error/failure.dart';

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    return switch (this) {
      Success<T>(:final value) => success(value),
      FailureResult<T>(failure: final reason) => failure(reason),
    };
  }

  T? get valueOrNull {
    return switch (this) {
      Success<T>(:final value) => value,
      FailureResult<T>() => null,
    };
  }

  Failure? get failureOrNull {
    return switch (this) {
      Success<T>() => null,
      FailureResult<T>(failure: final reason) => reason,
    };
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;
}

final class FailureResult<T> extends Result<T> {
  const FailureResult(this.failure);

  final Failure failure;
}
