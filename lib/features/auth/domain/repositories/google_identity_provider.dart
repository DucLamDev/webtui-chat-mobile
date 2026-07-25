import '../../../../core/result/result.dart';

abstract interface class GoogleIdentityProvider {
  Future<Result<String>> authenticate();
}
