import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/workspace_invite.dart';
import '../../domain/repositories/invite_repository.dart';
import '../datasources/invite_remote_data_source.dart';

final class InviteRepositoryImpl implements InviteRepository {
  const InviteRepositoryImpl(this._remote);

  final InviteRemoteDataSource _remote;

  @override
  Future<Result<WorkspaceInvitePreview>> preview(String token) {
    return guardResult(() => _remote.preview(token));
  }

  @override
  Future<Result<InviteAcceptResult>> accept(String token) {
    return guardResult(() => _remote.accept(token));
  }
}
