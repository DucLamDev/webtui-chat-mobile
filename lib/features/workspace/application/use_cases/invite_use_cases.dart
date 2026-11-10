import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/workspace_invite.dart';
import '../../domain/repositories/invite_repository.dart';

const _invalidToken = Failure(
  kind: FailureKind.validation,
  message: 'Đường dẫn lời mời không hợp lệ.',
  code: 'INVITE_TOKEN_INVALID',
);

final class PreviewInviteUseCase {
  const PreviewInviteUseCase(
    this._repository, {
    required String? Function() loadServerHost,
  }) : _loadServerHost = loadServerHost;

  final InviteRepository _repository;
  final String? Function() _loadServerHost;

  /// Lời mời của máy chủ khác máy chủ đang đăng nhập bị chặn (không nhận).
  Future<Result<WorkspaceInvitePreview>> execute(String token) async {
    if (!isValidInviteToken(token)) {
      return const FailureResult(_invalidToken);
    }
    final result = await _repository.preview(token.trim());
    if (result case Success<WorkspaceInvitePreview>(:final value)) {
      final inviteDomain = value.domain?.trim().toLowerCase();
      final serverHost = _loadServerHost()?.trim().toLowerCase();
      if (inviteDomain != null &&
          inviteDomain.isNotEmpty &&
          serverHost != null &&
          _hostOf(inviteDomain) != serverHost) {
        return FailureResult(
          Failure(
            kind: FailureKind.validation,
            message:
                'Lời mời thuộc máy chủ $inviteDomain, khác máy chủ bạn đang '
                'đăng nhập. Hãy đăng nhập đúng máy chủ rồi mở lại lời mời.',
            code: 'INVITE_SERVER_MISMATCH',
          ),
        );
      }
    }
    return result;
  }
}

final class AcceptInviteUseCase {
  const AcceptInviteUseCase(this._repository);

  final InviteRepository _repository;

  Future<Result<InviteAcceptResult>> execute(String token) {
    if (!isValidInviteToken(token)) {
      return Future.value(const FailureResult(_invalidToken));
    }
    return _repository.accept(token.trim());
  }
}

String inviteFailureMessage(Failure failure) {
  if (failure.hasCode(InviteErrorCode.notFound)) {
    return 'Không tìm thấy lời mời. Đường dẫn có thể đã bị sai.';
  }
  if (failure.hasCode(InviteErrorCode.expired)) {
    return 'Lời mời đã hết hạn. Hãy xin quản trị viên gửi lời mời mới.';
  }
  if (failure.hasCode(InviteErrorCode.revoked)) {
    return 'Lời mời đã bị thu hồi.';
  }
  if (failure.hasCode(InviteErrorCode.usedUp)) {
    return 'Lời mời đã hết lượt sử dụng.';
  }
  if (failure.hasCode(InviteErrorCode.emailMismatch)) {
    return 'Lời mời này dành cho một email khác. Hãy đăng nhập bằng đúng email '
        'được mời.';
  }
  return failure.message;
}

/// Câu giải thích khi lời mời không còn dùng được theo `status`.
String inviteStatusMessage(String status) {
  return switch (status) {
    'expired' => 'Lời mời đã hết hạn. Hãy xin quản trị viên gửi lời mời mới.',
    'revoked' => 'Lời mời đã bị thu hồi.',
    'used_up' => 'Lời mời đã hết lượt sử dụng.',
    _ => 'Lời mời không còn hiệu lực.',
  };
}

String _hostOf(String domain) {
  final index = domain.indexOf(':');
  return index < 0 ? domain : domain.substring(0, index);
}
