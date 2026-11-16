import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/workspace_invite.dart';
import '../../domain/repositories/invite_repository.dart';

Failure get _invalidToken => Failure(
  kind: FailureKind.validation,
  message: tr(
    'Đường dẫn lời mời không hợp lệ.',
    'The invitation link is not valid.',
  ),
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
      return FailureResult(_invalidToken);
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
            message: tr(
              'Lời mời thuộc máy chủ $inviteDomain, khác máy chủ bạn đang '
                  'đăng nhập. Hãy đăng nhập đúng máy chủ rồi mở lại lời mời.',
              'This invitation belongs to server $inviteDomain, which is not the '
                  'server you are signed in to. Sign in to the right server and open the invitation again.',
            ),
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
      return Future.value(FailureResult(_invalidToken));
    }
    return _repository.accept(token.trim());
  }
}

String inviteFailureMessage(Failure failure) {
  if (failure.hasCode(InviteErrorCode.notFound)) {
    return tr(
      'Không tìm thấy lời mời. Đường dẫn có thể đã bị sai.',
      'Invitation not found. The link may be wrong.',
    );
  }
  if (failure.hasCode(InviteErrorCode.expired)) {
    return tr(
      'Lời mời đã hết hạn. Hãy xin quản trị viên gửi lời mời mới.',
      'The invitation has expired. Ask an administrator to send a new one.',
    );
  }
  if (failure.hasCode(InviteErrorCode.revoked)) {
    return tr('Lời mời đã bị thu hồi.', 'The invitation was revoked.');
  }
  if (failure.hasCode(InviteErrorCode.usedUp)) {
    return tr(
      'Lời mời đã hết lượt sử dụng.',
      'The invitation has no uses left.',
    );
  }
  if (failure.hasCode(InviteErrorCode.emailMismatch)) {
    return tr(
      'Lời mời này dành cho một email khác. Hãy đăng nhập bằng đúng email '
          'được mời.',
      'This invitation is for a different email. Sign in with the invited email.',
    );
  }
  return failure.message;
}

/// Câu giải thích khi lời mời không còn dùng được theo `status`.
String inviteStatusMessage(String status) {
  return switch (status) {
    'expired' => tr(
      'Lời mời đã hết hạn. Hãy xin quản trị viên gửi lời mời mới.',
      'The invitation has expired. Ask an administrator to send a new one.',
    ),
    'revoked' => tr('Lời mời đã bị thu hồi.', 'The invitation was revoked.'),
    'used_up' => tr(
      'Lời mời đã hết lượt sử dụng.',
      'The invitation has no uses left.',
    ),
    _ => tr(
      'Lời mời không còn hiệu lực.',
      'This invitation is no longer valid.',
    ),
  };
}

String _hostOf(String domain) {
  final index = domain.indexOf(':');
  return index < 0 ? domain : domain.substring(0, index);
}
