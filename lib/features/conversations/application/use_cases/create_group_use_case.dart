import 'dart:math';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_repository.dart';

/// Độ dài tối đa của tên nhóm.
const groupNameMaxLength = 80;

const _slugBaseMaxLength = 40;
const _slugSuffixLength = 5;
const _slugAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

const _vietnameseFolding = <String, String>{
  'àáạảãâầấậẩẫăằắặẳẵ': 'a',
  'èéẹẻẽêềếệểễ': 'e',
  'ìíịỉĩ': 'i',
  'òóọỏõôồốộổỗơờớợởỡ': 'o',
  'ùúụủũưừứựửữ': 'u',
  'ỳýỵỷỹ': 'y',
  'đ': 'd',
};

/// Sinh slug cho nhóm từ tên: bỏ dấu tiếng Việt (kể cả đ), chữ thường, khoảng
/// trắng thành gạch nối, bỏ ký tự lạ, cắt độ dài, thêm hậu tố ngẫu nhiên ngắn
/// để không trùng. Luôn khớp `^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$` (tên rỗng hoặc
/// toàn ký tự lạ dùng gốc `nhom`).
String suggestGroupSlug(String name, {Random? random}) {
  var folded = name.toLowerCase();
  _vietnameseFolding.forEach((chars, plain) {
    folded = folded.replaceAll(RegExp('[$chars]'), plain);
  });
  var base = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.length > _slugBaseMaxLength) {
    base = base.substring(0, _slugBaseMaxLength).replaceAll(RegExp(r'-+$'), '');
  }
  if (base.isEmpty) base = 'nhom';
  final rng = random ?? Random.secure();
  final suffix = List.generate(
    _slugSuffixLength,
    (_) => _slugAlphabet[rng.nextInt(_slugAlphabet.length)],
  ).join();
  return '$base-$suffix';
}

final class CreateGroupResult {
  const CreateGroupResult({
    required this.channel,
    this.failedMemberIds = const [],
  });

  final ConversationSummary channel;

  /// Người không thêm được (nhóm vẫn được tạo).
  final List<String> failedMemberIds;
}

/// Tạo nhóm: kênh riêng tư (slug tự sinh) rồi thêm từng thành viên. Thêm lỗi
/// một phần thì nhóm vẫn được tạo và trả danh sách người không thêm được.
final class CreateGroupUseCase {
  CreateGroupUseCase(this._repository, {Random? random}) : _random = random;

  final ConversationRepository _repository;
  final Random? _random;

  Future<Result<CreateGroupResult>> execute({
    required String workspaceId,
    required String name,
    String description = '',
    List<String> memberIds = const [],
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Vui lòng nhập tên nhóm.',
          code: 'GROUP_NAME_REQUIRED',
        ),
      );
    }
    if (trimmedName.length > groupNameMaxLength) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Tên nhóm tối đa $groupNameMaxLength ký tự.',
          code: 'GROUP_NAME_TOO_LONG',
        ),
      );
    }
    final created = await _repository.createChannel(
      workspaceId: workspaceId,
      slug: suggestGroupSlug(trimmedName, random: _random),
      name: trimmedName,
      description: description.trim(),
      visibility: ChannelVisibility.private,
    );
    if (created case FailureResult<ConversationSummary>(
      failure: final failure,
    )) {
      return FailureResult(failure);
    }
    final channel = created.valueOrNull!;
    final failed = <String>[];
    for (final userId in memberIds.toSet()) {
      final added = await _repository.addMember(
        workspaceId: workspaceId,
        channelId: channel.channelId,
        userId: userId,
      );
      if (added is FailureResult<ChannelMember>) failed.add(userId);
    }
    return Success(
      CreateGroupResult(channel: channel, failedMemberIds: failed),
    );
  }
}
