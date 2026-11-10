import '../../../../core/result/result.dart';
import '../entities/workspace_invite.dart';

abstract interface class InviteRepository {
  Future<Result<WorkspaceInvitePreview>> preview(String token);

  Future<Result<InviteAcceptResult>> accept(String token);
}
