import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';

void main() {
  test('Success exposes value and maps through when', () {
    const result = Success<int>(42);

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, 42);
    expect(result.when(success: (value) => value + 1, failure: (_) => 0), 43);
  });

  test('FailureResult exposes failure', () {
    const failure = Failure(
      kind: FailureKind.unauthorized,
      message: 'Phiên đăng nhập đã hết hạn.',
    );
    const result = FailureResult<int>(failure);

    expect(result.isFailure, isTrue);
    expect(result.failureOrNull, same(failure));
    expect(result.failureOrNull?.requiresLogin, isTrue);
  });
}
