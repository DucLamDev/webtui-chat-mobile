import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../../workspace/domain/repositories/workspace_session_repository.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_local_cache.dart';
import '../../domain/repositories/conversation_repository.dart';

final class LoadConversationHomeUseCase {
  const LoadConversationHomeUseCase({
    required ConversationRepository conversationRepository,
    required WorkspaceSessionRepository workspaceSessionRepository,
  }) : _conversationRepository = conversationRepository,
       _workspaceSessionRepository = workspaceSessionRepository;

  final ConversationRepository _conversationRepository;
  final WorkspaceSessionRepository _workspaceSessionRepository;

  Future<Result<ConversationHomeData>> execute({String? workspaceId}) async {
    final activeWorkspaceId =
        workspaceId ??
        await _workspaceSessionRepository.readActiveWorkspaceId();
    if (activeWorkspaceId == null || activeWorkspaceId.isEmpty) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Bạn cần chọn workspace trước khi mở hội thoại.',
            'Select a workspace before opening a conversation.',
          ),
          code: 'WORKSPACE_REQUIRED',
        ),
      );
    }

    final directsFuture = _conversationRepository.listDirectConversations(
      workspaceId: activeWorkspaceId,
    );
    final channelsFuture = _conversationRepository.listChannels(
      workspaceId: activeWorkspaceId,
    );
    final contactsFuture = _conversationRepository.listContacts();
    final contactRequestsFuture = _conversationRepository.listContactRequests();
    final membersFuture = _conversationRepository.listWorkspaceMembers(
      workspaceId: activeWorkspaceId,
    );
    final presenceFuture = _conversationRepository.listPresence(
      workspaceId: activeWorkspaceId,
    );

    // All home sections are independent. Fetching them together keeps the
    // first useful content to a single network round trip on mobile.
    final directsResult = await directsFuture;
    if (directsResult case FailureResult<List<ConversationSummary>>()) {
      return FailureResult(directsResult.failure);
    }

    final channelsResult = await channelsFuture;
    if (channelsResult case FailureResult<List<ConversationSummary>>()) {
      return FailureResult(channelsResult.failure);
    }

    final contactsResult = await contactsFuture;
    final contactRequestsResult = await contactRequestsFuture;
    final membersResult = await membersFuture;
    final presenceResult = await presenceFuture;
    // Không còn kết bạn: mọi thành viên trong workspace là bạn bè, nhắn tin được
    // ngay. Danh bạ kết bạn cũ chỉ dùng khi không tải được danh sách thành viên.
    final members = membersResult.valueOrNull ?? const <ContactSummary>[];
    final contacts = members.isNotEmpty
        ? _sortByName(members)
        : _mergeContactRelationships(
            contactsResult.valueOrNull ?? const [],
            contactRequestsResult.valueOrNull ?? const [],
          );

    return Success(
      ConversationHomeData(
        workspaceId: activeWorkspaceId,
        conversations: _sortByUpdated(directsResult.valueOrNull ?? const []),
        channels: _sortByUpdated(channelsResult.valueOrNull ?? const []),
        contacts: contacts,
        workspaceMembers: members,
        presenceByUserId: presenceByUser(
          presenceResult.valueOrNull ?? const [],
        ),
        contactsErrorMessage: members.isNotEmpty
            ? null
            : contactsResult.failureOrNull?.message ??
                  contactRequestsResult.failureOrNull?.message,
        membersErrorMessage:
            membersResult.failureOrNull?.kind == FailureKind.forbidden
            ? tr(
                'Bạn chưa có quyền xem danh sách thành viên workspace.',
                'You don\'t have permission to view workspace members.',
              )
            : membersResult.failureOrNull?.message,
        presenceErrorMessage: presenceResult.failureOrNull?.message,
        // Danh sách hội thoại tự lùi về bản đã lưu khi mất mạng (repository),
        // nên dò mất mạng qua các mục không có bộ đệm gọi cùng lượt.
        isOffline: [
          membersResult.failureOrNull,
          presenceResult.failureOrNull,
          contactsResult.failureOrNull,
        ].any(isOfflineFailure),
      ),
    );
  }
}

/// Lỗi do không tới được máy chủ (mất mạng / hết giờ), khác lỗi quyền / dữ
/// liệu: có bản đã lưu thì vẫn hiện bản đó.
bool isOfflineFailure(Failure? failure) {
  return failure?.kind == FailureKind.network ||
      failure?.kind == FailureKind.timeout;
}

/// Đọc danh sách hội thoại đã lưu trên máy để hiện ngay khi mở app / mở tab
/// (kiểu Zalo / Messenger), trước khi gọi máy chủ. Không gọi mạng.
final class ReadCachedConversationHomeUseCase {
  const ReadCachedConversationHomeUseCase(this._reader);

  final ConversationListCacheReader _reader;

  /// `null` khi chưa lưu gì (để màn hiện trạng thái đang tải như cũ).
  Future<ConversationHomeData?> execute({required String workspaceId}) async {
    final id = workspaceId.trim();
    if (id.isEmpty) return null;
    final results = await Future.wait([
      _readSafely(() => _reader.readCachedDirectConversations(workspaceId: id)),
      _readSafely(() => _reader.readCachedChannels(workspaceId: id)),
    ]);
    final directs = results[0];
    final channels = results[1];
    if (directs == null && channels == null) return null;
    return ConversationHomeData(
      workspaceId: id,
      conversations: _sortByUpdated(directs ?? const []),
      channels: _sortByUpdated(channels ?? const []),
      contacts: const [],
      workspaceMembers: const [],
    );
  }
}

Future<List<ConversationSummary>?> _readSafely(
  Future<List<ConversationSummary>?> Function() read,
) async {
  try {
    return await read();
  } on Object {
    return null;
  }
}

/// Gộp hiện diện theo người (một người nhiều thiết bị): online thắng away, away
/// thắng offline. Dùng chung cho danh sách hội thoại và danh sách thành viên.
Map<String, ConversationPresence> presenceByUser(List<PresenceSummary> items) {
  final result = <String, ConversationPresence>{};
  for (final item in items) {
    final current = result[item.userId];
    if (current == ConversationPresence.online) {
      continue;
    }
    if (item.status == ConversationPresence.online ||
        current == null ||
        (current == ConversationPresence.offline &&
            item.status == ConversationPresence.away)) {
      result[item.userId] = item.status;
    }
  }
  return Map.unmodifiable(result);
}

List<ContactSummary> _mergeContactRelationships(
  List<ContactSummary> contacts,
  List<ContactSummary> requests,
) {
  final byUserId = <String, ContactSummary>{};
  for (final contact in contacts) {
    byUserId[contact.userId] = contact;
  }
  for (final request in requests) {
    final current = byUserId[request.userId];
    if (current == null || current.contactStatus != 'accepted') {
      byUserId[request.userId] = request;
    }
  }
  final merged = byUserId.values.toList(growable: false);
  final priority = {'accepted': 0, 'pending': 1, 'rejected': 2, 'cancelled': 3};
  merged.sort((left, right) {
    final leftPriority = priority[left.contactStatus] ?? 4;
    final rightPriority = priority[right.contactStatus] ?? 4;
    if (leftPriority != rightPriority) {
      return leftPriority.compareTo(rightPriority);
    }
    return left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
  });
  return merged;
}

List<ContactSummary> _sortByName(List<ContactSummary> items) {
  final sorted = [...items];
  sorted.sort((left, right) {
    return left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    );
  });
  return sorted;
}

List<ConversationSummary> _sortByUpdated(List<ConversationSummary> items) {
  final sorted = [...items];
  sorted.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return sorted;
}
