import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/conversations/application/use_cases/channel_use_cases.dart';
import '../../features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import '../../features/conversations/data/datasources/channel_member_cache_data_source.dart';
import '../../features/conversations/domain/repositories/conversation_local_cache.dart';
import 'foundation_providers.dart';

/// Đọc danh sách hội thoại đã lưu trên máy: chỉ có khi repository hội thoại
/// đang dùng có bộ đệm ([CachingConversationRepository]). Test thay repository
/// bằng bản giả thì `null` (màn chạy như trước, không đụng database).
final conversationListCacheReaderProvider =
    Provider<ConversationListCacheReader?>((ref) {
      final repository = ref.watch(conversationRepositoryProvider);
      return repository is ConversationListCacheReader
          ? repository as ConversationListCacheReader
          : null;
    });

/// Thành viên nhóm lưu trên máy, tách theo máy chủ ([activeInstanceScopeProvider]).
/// Chỉ bật cùng bộ đệm danh sách hội thoại.
final channelMemberCacheProvider = Provider<ChannelMemberCache?>((ref) {
  if (ref.watch(conversationListCacheReaderProvider) == null) return null;
  return ChannelMemberCacheDataSource(
    ref.watch(appDatabaseProvider),
    ref.watch(activeInstanceScopeProvider),
  );
});

final readCachedConversationHomeUseCaseProvider =
    Provider<ReadCachedConversationHomeUseCase?>((ref) {
      final reader = ref.watch(conversationListCacheReaderProvider);
      return reader == null ? null : ReadCachedConversationHomeUseCase(reader);
    });

/// Chi tiết nhóm: hiện thông tin + thành viên đã lưu trước, tải máy chủ thì
/// lưu lại thành viên.
final cachedLoadChannelDetailUseCaseProvider =
    Provider<LoadChannelDetailUseCase>((ref) {
      return LoadChannelDetailUseCase(
        ref.watch(conversationRepositoryProvider),
        memberCache: ref.watch(channelMemberCacheProvider),
        listCache: ref.watch(conversationListCacheReaderProvider),
      );
    });

/// Mời thành viên, thành công thì cập nhật danh sách thành viên đã lưu.
final cachedInviteChannelMemberUseCaseProvider =
    Provider<InviteChannelMemberUseCase>((ref) {
      return InviteChannelMemberUseCase(
        ref.watch(conversationRepositoryProvider),
        memberCache: ref.watch(channelMemberCacheProvider),
      );
    });

/// Duyệt yêu cầu tham gia, thành công thì cập nhật thành viên đã lưu.
final cachedApproveChannelJoinRequestUseCaseProvider =
    Provider<ApproveChannelJoinRequestUseCase>((ref) {
      return ApproveChannelJoinRequestUseCase(
        ref.watch(conversationRepositoryProvider),
        memberCache: ref.watch(channelMemberCacheProvider),
      );
    });
