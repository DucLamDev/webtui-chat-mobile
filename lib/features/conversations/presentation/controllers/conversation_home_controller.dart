import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/channel_use_cases.dart';
import '../../application/use_cases/load_conversation_home_use_case.dart';
import '../../application/use_cases/open_direct_conversation_use_case.dart';
import '../../domain/entities/conversation_summary.dart';

final conversationHomeControllerProvider = StateNotifierProvider.autoDispose
    .family<ConversationHomeController, ConversationHomeState, String>((
      ref,
      workspaceId,
    ) {
      final discovery = ref.watch(activeServerDiscoveryProvider);
      // Automation / kênh bot là chức năng nội bộ VPSTTT: chỉ bật trên chat.vpsttt.com.
      final automationEnabled = discovery?.automationEnabled ?? false;
      return ConversationHomeController(
        workspaceId: workspaceId,
        loadConversationHomeUseCase: ref.watch(
          loadConversationHomeUseCaseProvider,
        ),
        openDirectConversationUseCase: ref.watch(
          openDirectConversationUseCaseProvider,
        ),
        openPrivateChannelSessionUseCase: ref.watch(
          openPrivateChannelSessionUseCaseProvider,
        ),
        automationEnabled: automationEnabled,
      )..load();
    });

/// Bộ lọc hộp thư gộp (tin nhắn riêng + nhóm / kênh). `bot` chỉ hiện khi bật
/// module nội bộ (automation).
enum ConversationListFilter { all, unread, direct, group, favorite, bot }

const _inboxFilterLabels = {
  ConversationListFilter.all: 'Tất cả',
  ConversationListFilter.unread: 'Chưa đọc',
  ConversationListFilter.direct: 'Cá nhân',
  ConversationListFilter.group: 'Nhóm',
  ConversationListFilter.favorite: 'Ghim',
  ConversationListFilter.bot: 'Bot',
};

final class ConversationHomeState {
  const ConversationHomeState({
    required this.workspaceId,
    this.conversations = const [],
    this.channels = const [],
    this.contacts = const [],
    this.workspaceMembers = const [],
    this.presenceByUserId = const {},
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
    this.noticeMessage,
    this.contactsErrorMessage,
    this.membersErrorMessage,
    this.presenceErrorMessage,
    this.messageFilter = ConversationListFilter.all,
    this.contactsTab = 0,
    this.channelTab = 0,
    this.searchQuery = '',
    this.selectedConversation,
    this.automationEnabled = false,
  });

  final String workspaceId;
  final List<ConversationSummary> conversations;
  final List<ConversationSummary> channels;
  final List<ContactSummary> contacts;
  final List<ContactSummary> workspaceMembers;
  final Map<String, ConversationPresence> presenceByUserId;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;
  final String? noticeMessage;
  final String? contactsErrorMessage;
  final String? membersErrorMessage;
  final String? presenceErrorMessage;
  final ConversationListFilter messageFilter;
  final int contactsTab;
  final int channelTab;
  final String searchQuery;
  final ConversationSummary? selectedConversation;

  /// Bật khi server là chat.vpsttt.com (zone nội bộ VPSTTT) và có capability
  /// `automation`. Khi `false`, kênh automation / bot bị ẩn khỏi mọi tab (kể cả
  /// danh sách Tin nhắn) và tab "Automation" không hiển thị.
  final bool automationEnabled;

  /// Số tab của màn Kênh: Tất cả/Công khai/Riêng tư, cộng tab Automation khi bật.
  int get channelTabCount => automationEnabled ? 4 : 3;

  /// Chỉ số tab "Automation" khi được bật (ngược lại trả -1).
  int get automationChannelTab => automationEnabled ? 3 : -1;

  ConversationPresence? presenceForUser(String userId) {
    return presenceByUserId[userId];
  }

  ConversationPresence? presenceForConversation(
    ConversationSummary conversation,
  ) {
    final peerUserId = conversation.peerUserId;
    return peerUserId == null ? null : presenceForUser(peerUserId);
  }

  /// Bộ lọc hiện trên hộp thư theo thứ tự (Bot chỉ khi bật automation).
  List<ConversationListFilter> get inboxFilters => [
    for (final filter in ConversationListFilter.values)
      if (filter != ConversationListFilter.bot || automationEnabled) filter,
  ];

  List<String> get inboxFilterLabels => [
    for (final filter in inboxFilters) _inboxFilterLabels[filter]!,
  ];

  /// Hộp thư gộp: tin nhắn riêng và nhóm / kênh đã tham gia trong một danh
  /// sách, ghim lên đầu, còn lại theo hoạt động gần nhất (tin mới nhất trên
  /// cùng). Kênh bot / automation chỉ hiện ở bộ lọc Bot.
  List<ConversationSummary> get inbox {
    return _buildInbox(
      directs: conversations,
      channels: channels,
      filter: messageFilter,
      query: searchQuery,
      automationEnabled: automationEnabled,
    );
  }

  /// Kênh công khai chưa tham gia (gợi ý ở cuối hộp thư khi xem Tất cả / Nhóm).
  List<ConversationSummary> get joinableChannels {
    if (messageFilter != ConversationListFilter.all &&
        messageFilter != ConversationListFilter.group) {
      return const [];
    }
    final query = searchQuery.trim().toLowerCase();
    return channels
        .where((channel) {
          if (channel.isMember || channel.isAutomation) return false;
          if (channel.privateSessionMode) return false;
          if (channel.channelVisibility != ChannelVisibility.public) {
            return false;
          }
          if (query.isEmpty) return true;
          return channel.title.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<ConversationSummary> get filteredConversations {
    return _filterConversations(
      conversations,
      messageFilter,
      searchQuery,
      automationEnabled: automationEnabled,
    );
  }

  List<ConversationSummary> get filteredChannels {
    final query = searchQuery.trim().toLowerCase();
    return channels
        .where((channel) {
          if (channel.isAutomation) {
            // Kênh automation chỉ xuất hiện khi server bật capability và người
            // dùng đang ở tab "Automation"; ngược lại luôn ẩn.
            if (!automationEnabled || channelTab != automationChannelTab) {
              return false;
            }
          } else {
            // Kênh thường không bao giờ nằm trong tab "Automation".
            if (channelTab == automationChannelTab) {
              return false;
            }
            final matchesTab = switch (channelTab) {
              1 => channel.channelVisibility == ChannelVisibility.public,
              2 => channel.channelVisibility == ChannelVisibility.private,
              _ => true,
            };
            if (!matchesTab) {
              return false;
            }
          }
          if (query.isEmpty) {
            return true;
          }
          return '${channel.title} ${channel.preview}'.toLowerCase().contains(
            query,
          );
        })
        .toList(growable: false);
  }

  List<ContactSummary> get filteredContacts {
    final source = contactsTab == 0 ? contacts : workspaceMembers;
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return source;
    }
    return source
        .where((contact) => contact.searchableText.contains(query))
        .toList(growable: false);
  }

  ConversationHomeState copyWith({
    List<ConversationSummary>? conversations,
    List<ConversationSummary>? channels,
    List<ContactSummary>? contacts,
    List<ContactSummary>? workspaceMembers,
    Map<String, ConversationPresence>? presenceByUserId,
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    String? noticeMessage,
    String? contactsErrorMessage,
    String? membersErrorMessage,
    String? presenceErrorMessage,
    ConversationListFilter? messageFilter,
    int? contactsTab,
    int? channelTab,
    String? searchQuery,
    ConversationSummary? selectedConversation,
    bool clearError = false,
    bool clearNotice = false,
    bool clearSelection = false,
  }) {
    return ConversationHomeState(
      workspaceId: workspaceId,
      conversations: conversations ?? this.conversations,
      channels: channels ?? this.channels,
      contacts: contacts ?? this.contacts,
      workspaceMembers: workspaceMembers ?? this.workspaceMembers,
      presenceByUserId: presenceByUserId ?? this.presenceByUserId,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
      contactsErrorMessage: contactsErrorMessage ?? this.contactsErrorMessage,
      membersErrorMessage: membersErrorMessage ?? this.membersErrorMessage,
      presenceErrorMessage: presenceErrorMessage ?? this.presenceErrorMessage,
      messageFilter: messageFilter ?? this.messageFilter,
      contactsTab: contactsTab ?? this.contactsTab,
      channelTab: channelTab ?? this.channelTab,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedConversation: clearSelection
          ? null
          : selectedConversation ?? this.selectedConversation,
      automationEnabled: automationEnabled,
    );
  }
}

final class ConversationHomeController
    extends StateNotifier<ConversationHomeState> {
  ConversationHomeController({
    required String workspaceId,
    required LoadConversationHomeUseCase loadConversationHomeUseCase,
    required OpenDirectConversationUseCase openDirectConversationUseCase,
    required OpenPrivateChannelSessionUseCase openPrivateChannelSessionUseCase,
    bool automationEnabled = false,
  }) : _loadConversationHomeUseCase = loadConversationHomeUseCase,
       _openDirectConversationUseCase = openDirectConversationUseCase,
       _openPrivateChannelSessionUseCase = openPrivateChannelSessionUseCase,
       super(
         ConversationHomeState(
           workspaceId: workspaceId,
           automationEnabled: automationEnabled,
         ),
       );

  final LoadConversationHomeUseCase _loadConversationHomeUseCase;
  final OpenDirectConversationUseCase _openDirectConversationUseCase;
  final OpenPrivateChannelSessionUseCase _openPrivateChannelSessionUseCase;

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearNotice: true,
    );
    final result = await _loadConversationHomeUseCase.execute(
      workspaceId: state.workspaceId,
    );
    switch (result) {
      case Success<ConversationHomeData>(value: final data):
        state = state.copyWith(
          conversations: data.conversations,
          channels: data.channels,
          contacts: data.contacts,
          workspaceMembers: data.workspaceMembers,
          presenceByUserId: data.presenceByUserId,
          contactsErrorMessage: data.contactsErrorMessage,
          membersErrorMessage: data.membersErrorMessage,
          presenceErrorMessage: data.presenceErrorMessage,
          isLoading: false,
          clearError: true,
        );
      case FailureResult<ConversationHomeData>(failure: final failure):
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    await load();
    state = state.copyWith(isRefreshing: false);
  }

  void setMessageFilter(ConversationListFilter filter) {
    state = state.copyWith(messageFilter: filter);
  }

  void setContactsTab(int index) {
    state = state.copyWith(contactsTab: index.clamp(0, 1).toInt());
  }

  void setChannelTab(int index) {
    state = state.copyWith(
      channelTab: index.clamp(0, state.channelTabCount - 1).toInt(),
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void selectConversation(ConversationSummary conversation) {
    final opened = _withoutUnread(conversation);
    state = state.copyWith(
      conversations: _markOpenedInList(state.conversations, opened),
      channels: _markOpenedInList(state.channels, opened),
      selectedConversation: opened,
    );
  }

  void markConversationOpened(ConversationSummary conversation) {
    if (!conversation.isUnread) {
      return;
    }
    final opened = _withoutUnread(conversation);
    state = state.copyWith(
      conversations: _markOpenedInList(state.conversations, opened),
      channels: _markOpenedInList(state.channels, opened),
    );
  }

  Future<ConversationSummary?> openDirect(ContactSummary contact) async {
    state = state.copyWith(clearError: true, clearNotice: true);
    final result = await _openDirectConversationUseCase.execute(
      workspaceId: state.workspaceId,
      participantIds: [contact.userId],
    );
    switch (result) {
      case Success<ConversationSummary>(value: final conversation):
        state = state.copyWith(
          selectedConversation: conversation,
          noticeMessage: 'Đã mở hội thoại với ${contact.displayName}.',
        );
        await refresh();
        return conversation;
      case FailureResult<ConversationSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
        return null;
    }
  }

  Future<ConversationSummary?> openChannel(ConversationSummary channel) async {
    if (!channel.privateSessionMode) {
      return channel;
    }
    state = state.copyWith(clearError: true, clearNotice: true);
    final result = await _openPrivateChannelSessionUseCase.execute(
      workspaceId: state.workspaceId,
      channelId: channel.channelId,
    );
    switch (result) {
      case Success<ConversationSummary>(value: final conversation):
        state = state.copyWith(
          selectedConversation: conversation,
          noticeMessage: 'Đã mở phiên hỗ trợ riêng tư.',
        );
        await refresh();
        return conversation;
      case FailureResult<ConversationSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
        return null;
    }
  }
}

ConversationSummary _withoutUnread(ConversationSummary conversation) {
  return conversation.copyWith(unreadCount: 0);
}

List<ConversationSummary> _markOpenedInList(
  List<ConversationSummary> items,
  ConversationSummary opened,
) {
  return items
      .map(
        (item) => _sameConversation(item, opened) ? _withoutUnread(item) : item,
      )
      .toList(growable: false);
}

bool _sameConversation(ConversationSummary left, ConversationSummary right) {
  return left.id == right.id || left.channelId == right.channelId;
}

List<ConversationSummary> _filterConversations(
  List<ConversationSummary> source,
  ConversationListFilter filter,
  String query, {
  required bool automationEnabled,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return source
      .where((conversation) {
        if (conversation.isAutomation && !automationEnabled) {
          return false;
        }
        final matchesFilter = switch (filter) {
          ConversationListFilter.all => true,
          ConversationListFilter.unread => conversation.isUnread,
          ConversationListFilter.favorite => conversation.favorite,
          ConversationListFilter.direct => true,
          ConversationListFilter.group => false,
          ConversationListFilter.bot => conversation.isAutomation,
        };
        if (!matchesFilter) {
          return false;
        }
        if (normalizedQuery.isEmpty) {
          return true;
        }
        return '${conversation.title} ${conversation.preview}'
            .toLowerCase()
            .contains(normalizedQuery);
      })
      .toList(growable: false);
}

List<ConversationSummary> _buildInbox({
  required List<ConversationSummary> directs,
  required List<ConversationSummary> channels,
  required ConversationListFilter filter,
  required String query,
  required bool automationEnabled,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final seen = <String>{};
  final items = <ConversationSummary>[];
  void add(ConversationSummary item) {
    if (seen.add(item.channelId)) items.add(item);
  }

  for (final direct in directs) {
    add(direct);
  }
  for (final channel in channels) {
    // Kênh chưa tham gia không nằm trong hộp thư (gợi ý riêng ở cuối).
    if (channel.isMember || channel.privateSessionMode) add(channel);
  }

  final result = items
      .where((item) {
        if (item.isAutomation && !automationEnabled) return false;
        final isGroup = item.kind == ConversationKind.channel;
        final matchesFilter = switch (filter) {
          ConversationListFilter.all => !item.isAutomation,
          ConversationListFilter.unread => item.isUnread,
          ConversationListFilter.direct => !isGroup,
          ConversationListFilter.group => isGroup && !item.isAutomation,
          ConversationListFilter.favorite => item.favorite,
          ConversationListFilter.bot => item.isAutomation,
        };
        if (!matchesFilter) return false;
        if (normalizedQuery.isEmpty) return true;
        return '${item.title} ${item.preview}'.toLowerCase().contains(
          normalizedQuery,
        );
      })
      .toList(growable: false);
  result.sort(_compareInbox);
  return result;
}

/// Ghim trước; sau đó hội thoại có tin mới nhất trước; bằng thời gian thì
/// hội thoại chưa đọc trước, rồi theo tên để thứ tự ổn định.
int _compareInbox(ConversationSummary left, ConversationSummary right) {
  if (left.favorite != right.favorite) return left.favorite ? -1 : 1;
  final byTime = right.updatedAt.compareTo(left.updatedAt);
  if (byTime != 0) return byTime;
  if (left.isUnread != right.isUnread) return left.isUnread ? -1 : 1;
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
