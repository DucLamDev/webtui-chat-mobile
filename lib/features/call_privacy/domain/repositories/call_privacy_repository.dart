import '../../../../core/result/result.dart';
import '../entities/call_privacy.dart';

abstract interface class CallPrivacyRepository {
  Future<Result<WhoCanCallMe>> load({required String workspaceId});

  Future<Result<WhoCanCallMe>> update({
    required String workspaceId,
    required WhoCanCallMe value,
  });
}
