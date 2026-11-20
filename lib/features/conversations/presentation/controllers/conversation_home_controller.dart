import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../application/channel_last_message_preview.dart';
import '../../application/use_cases/channel_use_cases.dart';
import '../../application/use_cases/load_conversation_home_use_case.dart';
import '../../application/use_cases/open_direct_conversation_use_case.dart';
import '../../domain/entities/business_channel_catalog.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_list_prefs.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/inbox_channel_rules.dart';
import '../../domain/repositories/conversation_list_prefs_repository.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../models/conversation_privacy_projection.dart';

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
        // Cùng kết nối nền với cuộc gọi đến (màn chính đã nối sẵn).
        realtime: ref.watch(incomingCallRealtimeRepositoryProvider),
        currentUserId: () => ref.read(profileControllerProvider).profile?.id,
        listPrefs: ref.watch(conversationListPrefsRepositoryProvider),
      )..load();
    });

/// Bộ lọc hộp thư gộp (tin nhắn riêng + nhóm / kênh). `bot` chỉ hiện khi bật
/// module nội bộ (automation).
enum ConversationListFilter { all, unread, direct, group, favorite, bot }

/// Bộ lọc hiện trên hộp thư: Tất cả, Nhóm, Cá nhân, Nghiệp vụ (chỉ khi bật
/// automation), Chưa đọc. Ghim chỉ là thứ tự (ghim lên đầu Tất cả), không còn tab.
const _inboxFilterOrder = [
  ConversationListFilter.all,
  ConversationListFilter.group,
  ConversationListFilter.direct,
  ConversationListFilter.bot,
  ConversationListFilter.unread,
];

Map<ConversationListFilter, String> get _inboxFilterLabels => {
  ConversationListFilter.all: tr('Tất cả', 'All'),
  ConversationListFilter.unread: tr('Chưa đọc', 'Unread'),
  ConversationListFilter.direct: tr('Cá nhân', 'Direct'),
  ConversationListFilter.group: tr('Nhóm', 'Groups'),
  ConversationListFilter.favorite: tr('Ghim', 'Pinned'),
  ConversationListFilter.bot: tr('Nghiệp vụ', 'Business'),
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
    this.listPrefs = ConversationListPrefs.empty,
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

  /// Ghim / chưa đọc / ẩn lưu trên máy, áp lên hộp thư (xem
  /// [ConversationListPrefs]).
  final ConversationListPrefs listPrefs;

  /// Bản hội thoại sau khi áp ghim / chưa đọc của máy (cho menu ấn giữ).
  ConversationSummary withListPrefs(ConversationSummary item) =>
      listPrefs.apply(item);

  bool isHiddenOnDevice(ConversationSummary item) => listPrefs.isHidden(item);

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

  /// Bộ lọc hiện trên hộp thư theo thứ tự (Nghiệp vụ chỉ khi bật automation).
  List<ConversationListFilter> get inboxFilters => [
    for (final filter in _inboxFilterOrder)
      if (filter != ConversationListFilter.bot || automationEnabled) filter,
  ];

  /// Nhãn tab kèm số hội thoại chưa đọc trong tab đó (vd. "Chưa đọc 3").
  List<String> get inboxFilterLabels {
    final unread = _buildInbox(
      directs: conversations,
      channels: channels,
      filter: ConversationListFilter.unread,
      query: '',
      automationEnabled: automationEnabled,
      prefs: listPrefs,
    );
    final counts = <ConversationListFilter, int>{};
    void bump(ConversationListFilter filter) {
      counts[filter] = (counts[filter] ?? 0) + 1;
    }

    for (final item in unread) {
      bump(ConversationListFilter.unread);
      if (_isPersonalChat(item)) {
        bump(ConversationListFilter.direct);
      } else if (_isGroupChat(item)) {
        bump(ConversationListFilter.group);
      }
    }
    for (final item in quickChannels) {
      if (item.isUnread) bump(ConversationListFilter.bot);
    }
    return [
      for (final filter in inboxFilters)
        switch (counts[filter]) {
          null => _inboxFilterLabels[filter]!,
          final count => '${_inboxFilterLabels[filter]} $count',
        },
    ];
  }

  /// Số tin chưa đọc cho số đỏ trên tab Tin nhắn ở thanh dưới.
  ///
  /// Đếm trên mọi hội thoại của hộp thư, KHÔNG theo chip lọc hay ô tìm của màn
  /// Tin nhắn (đổi chip / gõ tìm không làm số nhảy); gồm kênh nghiệp vụ khi
  /// bật. Bỏ hội thoại tắt tiếng và chat 1-1 với người đã chặn: dòng chat của
  /// họ cũng không hiện số chưa đọc.
  int unreadBadgeCount({Set<String> blockedUserIds = const {}}) {
    final unread = _buildInbox(
      directs: conversations,
      channels: channels,
      filter: ConversationListFilter.unread,
      query: '',
      automationEnabled: automationEnabled,
      prefs: listPrefs,
    );
    var total = 0;
    for (final item in unread) {
      if (item.muted || item.membershipStatus == MembershipStatus.muted) {
        continue;
      }
      if (blockedDirectPeerUserId(item, blockedUserIds) != null) continue;
      total += item.unreadCount;
    }
    return total;
  }

  /// Kênh nghiệp vụ (bot đơn hàng, gia hạn...) cho tab Nghiệp vụ, theo thứ tự cố định của
  /// [businessChannelCatalog] (Đơn hàng, Gia hạn, Kế toán...) để mỗi kênh luôn ở cùng một chỗ; tin chưa
  /// đọc hiện bằng huy hiệu số. Gồm cả kênh chưa tham gia (bấm để mở phiên
  /// riêng / tham gia).
  List<ConversationSummary> get quickChannels {
    if (!automationEnabled) return const [];
    final byChannel = <String, ConversationSummary>{};
    for (final item in [...channels, ...conversations]) {
      if (!item.isAutomation || isHiddenSystemChannel(item)) continue;
      final existing = byChannel[item.channelId];
      // Cùng kênh có trong cả hai danh sách: giữ bản mới hơn / còn chưa đọc.
      if (existing == null ||
          item.updatedAt.isAfter(existing.updatedAt) ||
          item.unreadCount > existing.unreadCount) {
        byChannel[item.channelId] = item;
      }
    }
    // Chỉ "chưa đọc" của máy có tác dụng ở đây; thứ tự kênh nghiệp vụ cố định.
    return byChannel.values.map(listPrefs.apply).toList()
      ..sort(compareBusinessChannels);
  }

  /// Hộp thư gộp: tin nhắn riêng và nhóm / kênh đã tham gia trong một danh
  /// sách (kênh thường chỉ khi là kênh nội bộ mặc định hoặc đã có tin, xem
  /// [shouldShowChannelInInbox]), ghim lên đầu, còn lại theo hoạt động gần nhất (tin mới nhất trên
  /// cùng). Kênh nghiệp vụ nằm ở tab Nghiệp vụ; ở Tất cả chỉ hiện khi
  /// đang tìm kiếm.
  List<ConversationSummary> get inbox {
    if (messageFilter == ConversationListFilter.bot) {
      final query = searchQuery.trim().toLowerCase();
      return [
        for (final item in quickChannels)
          if (query.isEmpty || _matchesQuery(item, query)) item,
      ];
    }
    return _buildInbox(
      directs: conversations,
      channels: channels,
      filter: messageFilter,
      query: searchQuery,
      automationEnabled: automationEnabled,
      // Kênh đang mở (màn rộng) không biến mất khỏi danh sách dù chưa có tin.
      openChannelId: selectedConversation?.channelId,
      prefs: listPrefs,
    );
  }

  /// Danh bạ > Kênh, phần "Đã tham gia": kênh / nhóm mình là thành viên (cả
  /// kênh chưa có tin), xếp theo tên; lọc theo ô tìm (tên kênh). Không gồm
  /// kênh bot nghiệp vụ (ở tab Nghiệp vụ), chat bot thông báo và kênh hệ
  /// thống bị ẩn.
  List<ConversationSummary> get joinedChannels {
    final query = searchQuery.trim().toLowerCase();
    final result = channels
        .where((channel) {
          if (!channel.isMember || !_isGroupChat(channel)) return false;
          if (isHiddenSystemChannel(channel)) return false;
          return _matchesChannelName(channel, query);
        })
        .toList(growable: false);
    result.sort(_compareChannelName);
    return result;
  }

  /// Danh bạ > Kênh, phần "Có thể tham gia": kênh công khai chưa tham gia (bấm
  /// để xem và xin / tham gia), xếp theo tên; lọc theo ô tìm (tên kênh).
  List<ConversationSummary> get joinableChannels {
    final query = searchQuery.trim().toLowerCase();
    final result = channels
        .where((channel) {
          if (channel.isMember || channel.isAutomation) return false;
          if (isHiddenSystemChannel(channel)) return false;
          if (channel.privateSessionMode) return false;
          if (channel.channelVisibility != ChannelVisibility.public) {
            return false;
          }
          return _matchesChannelName(channel, query);
        })
        .toList(growable: false);
    result.sort(_compareChannelName);
    return result;
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
          if (isHiddenSystemChannel(channel)) return false;
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
    ConversationListPrefs? listPrefs,
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
      listPrefs: listPrefs ?? this.listPrefs,
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
    ConversationRealtimeRepository? realtime,
    String? Function()? currentUserId,
    ConversationListPrefsRepository? listPrefs,
  }) : _loadConversationHomeUseCase = loadConversationHomeUseCase,
       _openDirectConversationUseCase = openDirectConversationUseCase,
       _openPrivateChannelSessionUseCase = openPrivateChannelSessionUseCase,
       _realtime = realtime,
       _currentUserId = currentUserId,
       _listPrefsRepository = listPrefs,
       super(
         ConversationHomeState(
           workspaceId: workspaceId,
           automationEnabled: automationEnabled,
         ),
       );

  final LoadConversationHomeUseCase _loadConversationHomeUseCase;
  final OpenDirectConversationUseCase _openDirectConversationUseCase;
  final OpenPrivateChannelSessionUseCase _openPrivateChannelSessionUseCase;
  final ConversationRealtimeRepository? _realtime;
  final String? Function()? _currentUserId;
  final ConversationListPrefsRepository? _listPrefsRepository;
  // Tài khoản đã đọc tuỳ chọn danh sách (đổi tài khoản thì đọc lại).
  String? _listPrefsUserId;
  StreamSubscription<ConversationRealtimeEvent>? _realtimeSubscription;
  Set<String> _watchedChannelIds = const <String>{};
  // Mã tin realtime đã xử lý (bỏ tin tới trùng), giữ tối đa 200 mã gần nhất.
  final Set<String> _seenMessageIds = <String>{};
  // Tin đã cộng vào số chưa đọc (mã tin → kênh): tin đó bị thu hồi / hết hạn
  // thì trừ lại. Xoá khi tải lại từ máy chủ (số máy chủ là chuẩn).
  final Map<String, String> _unreadMessageIds = <String, String>{};
  // Màn rộng (máy tính bảng): danh sách và phòng chat đang chọn hiện cùng lúc.
  // Trên điện thoại [ConversationHomeState.selectedConversation] có thể còn
  // giữ hội thoại cũ sau khi rời phòng nên không dùng để biết "đang mở".
  bool _splitView = false;

  /// Màn danh sách báo bố cục hiện tại (không đổi state, không vẽ lại).
  void reportSplitView(bool wide) {
    _splitView = wide;
  }

  @override
  void dispose() {
    unawaited(_realtimeSubscription?.cancel());
    if (_watchedChannelIds.isNotEmpty) {
      _realtime?.watchChannels(
        workspaceId: state.workspaceId,
        channelIds: const <String>[],
      );
    }
    super.dispose();
  }

  /// Nghe tin mới của mọi hội thoại trong danh sách (kể cả phòng chưa mở) để
  /// số chưa đọc / tin cuối cập nhật ngay; trước đây chỉ cập nhật khi quay về
  /// app hoặc rời phòng chat. Cập nhật tại chỗ từ tin vừa đến, không gọi máy
  /// chủ: nhóm đông người nhắn liên tục không làm mọi máy cùng tải lại.
  void _watchListRealtime() {
    final realtime = _realtime;
    if (realtime == null || !mounted) return;
    final ids = {
      for (final item in [...state.conversations, ...state.channels])
        if (item.channelId.trim().isNotEmpty &&
            (item.kind != ConversationKind.channel || item.isMember))
          item.channelId.trim(),
    };
    if (_realtimeSubscription != null &&
        ids.length == _watchedChannelIds.length &&
        ids.containsAll(_watchedChannelIds)) {
      return;
    }
    final events = realtime.watchChannels(
      workspaceId: state.workspaceId,
      channelIds: ids,
    );
    // Kết nối nền chưa mở cho workspace này: thử lại ở lần tải sau.
    if (events == null) return;
    _watchedChannelIds = ids;
    final previous = _realtimeSubscription;
    late final StreamSubscription<ConversationRealtimeEvent> subscription;
    subscription = events.listen(
      (event) {
        if (!mounted || !_watchedChannelIds.contains(event.channelId.trim())) {
          return;
        }
        switch (event.type) {
          case ConversationRealtimeEventType.messageCreated:
            _applyRealtimeMessage(event);
          case ConversationRealtimeEventType.messageDeleted:
            _applyRealtimeMessageRemoved(event);
          default:
            break;
        }
      },
      // Kết nối đóng hẳn (đăng xuất / đổi workspace): lần tải sau theo dõi lại.
      onDone: () {
        if (identical(_realtimeSubscription, subscription)) {
          _realtimeSubscription = null;
          _watchedChannelIds = const <String>{};
        }
      },
    );
    _realtimeSubscription = subscription;
    // Nghe luồng mới rồi mới huỷ luồng cũ: không có lúc không ai nghe.
    unawaited(previous?.cancel());
  }

  /// Tin mới tới hội thoại trong danh sách: đưa lên đầu, cập nhật giờ / tin
  /// cuối (chat 1-1) và cộng 1 chưa đọc nếu chắc chắn không phải tin của mình
  /// và hội thoại đó không đang mở cạnh danh sách (máy tính bảng). Máy chủ đếm
  /// tối đa [_unreadCountCap] nên ở đây cũng dừng ở đó.
  void _applyRealtimeMessage(ConversationRealtimeEvent event) {
    final message = event.message;
    final channelId = event.channelId.trim();
    if (message == null || channelId.isEmpty || message.isDeleted) return;
    final messageId = message.id.trim();
    if (messageId.isNotEmpty) {
      if (!_seenMessageIds.add(messageId)) return;
      if (_seenMessageIds.length > 200) {
        _seenMessageIds.remove(_seenMessageIds.first);
      }
    }
    final me = _currentUserId?.call()?.trim();
    // Chưa biết mình là ai (hồ sơ chưa tải xong): không cộng, tránh tính tin
    // mình gửi từ máy khác; lần tải sau lấy số đúng từ máy chủ.
    final countable =
        !message.isMine &&
        me != null &&
        me.isNotEmpty &&
        message.senderId?.trim() != me;
    final selected = state.selectedConversation;
    final isOpen =
        _splitView &&
        selected != null &&
        selected.channelId.trim() == channelId;
    final addUnread = countable && !isOpen;
    final at = message.createdAt;

    ConversationSummary update(ConversationSummary item) {
      final newer = at.isAfter(item.updatedAt);
      return item.copyWith(
        unreadCount: addUnread
            ? (item.unreadCount + 1).clamp(0, _unreadCountCap).toInt()
            : null,
        updatedAt: newer ? at : null,
        lastMessageAt: newer ? at : null,
        preview: newer ? _realtimePreviewFor(item, message, me) : null,
      );
    }

    final changed = _updateConversation(channelId, update, resort: true);
    if (changed && addUnread && messageId.isNotEmpty) {
      _unreadMessageIds[messageId] = channelId;
      if (_unreadMessageIds.length > 200) {
        _unreadMessageIds.remove(_unreadMessageIds.keys.first);
      }
    }
  }

  /// Dòng xem trước sau tin mới. Chat 1-1 / bot thông báo: nội dung tin. Nhóm:
  /// "Tên: nội dung" như máy chủ trả khi tải danh sách; tên tra trong thành
  /// viên tổ chức / danh bạ đã tải, chưa biết tên thì chỉ nội dung (lần tải
  /// danh sách sau máy chủ trả đủ tên).
  String? _realtimePreviewFor(
    ConversationSummary item,
    ChatMessage message,
    String? me,
  ) {
    if (item.kind != ConversationKind.channel || item.noticeBot) {
      return _realtimePreview(message);
    }
    final senderId = message.senderId?.trim() ?? '';
    return groupLastMessagePreview(
      kind: message.kind,
      body: message.body,
      senderId: senderId,
      senderName: _memberName(senderId),
      currentUserId: me,
      isMine: message.isMine,
      secret: message.isSecret,
      hasAttachments: message.attachments.isNotEmpty,
    );
  }

  String? _memberName(String userId) {
    if (userId.isEmpty) return null;
    for (final people in [state.workspaceMembers, state.contacts]) {
      for (final person in people) {
        if (person.userId.trim() != userId) continue;
        final name = person.displayName.trim();
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  /// Tin vừa được cộng chưa đọc bị thu hồi / hết hạn: trừ lại (máy chủ không
  /// đếm tin đã xoá).
  void _applyRealtimeMessageRemoved(ConversationRealtimeEvent event) {
    final messageId = (event.messageId ?? event.message?.id ?? '').trim();
    if (messageId.isEmpty) return;
    final channelId = _unreadMessageIds.remove(messageId);
    if (channelId == null) return;
    _updateConversation(
      channelId,
      (item) => item.copyWith(
        unreadCount: (item.unreadCount - 1).clamp(0, _unreadCountCap).toInt(),
      ),
    );
  }

  bool _updateConversation(
    String channelId,
    ConversationSummary Function(ConversationSummary item) update, {
    bool resort = false,
  }) {
    List<ConversationSummary>? apply(List<ConversationSummary> items) {
      var hit = false;
      final next = [
        for (final item in items)
          if (item.channelId.trim() == channelId)
            () {
              hit = true;
              return update(item);
            }()
          else
            item,
      ];
      if (!hit) return null;
      if (resort) {
        next.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      }
      return List.unmodifiable(next);
    }

    final conversations = apply(state.conversations);
    final channels = apply(state.channels);
    if (conversations == null && channels == null) return false;
    state = state.copyWith(conversations: conversations, channels: channels);
    return true;
  }

  void _forgetUnreadMessages(String channelId) {
    _unreadMessageIds.removeWhere((_, value) => value == channelId.trim());
  }

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearNotice: true,
    );
    await _loadListPrefs();
    if (!mounted) return;
    final result = await _loadConversationHomeUseCase.execute(
      workspaceId: state.workspaceId,
    );
    if (!mounted) return;
    switch (result) {
      case Success<ConversationHomeData>(value: final data):
        _applyData(data);
      case FailureResult<ConversationHomeData>(failure: final failure):
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
    }
  }

  /// Cập nhật danh sách ngầm (khi quay về từ phòng chat): không hiện vòng tải;
  /// lỗi mạng thì giữ nguyên danh sách đang có. Trả `false` khi tải lỗi.
  Future<bool> syncSilently() async {
    if (state.isLoading) return true;
    await _loadListPrefs();
    if (!mounted) return false;
    final result = await _loadConversationHomeUseCase.execute(
      workspaceId: state.workspaceId,
    );
    if (!mounted) return false;
    if (result case Success<ConversationHomeData>(value: final data)) {
      _applyData(data);
      return true;
    }
    return false;
  }

  void _applyData(ConversationHomeData data) {
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
    _unreadMessageIds.clear();
    _watchListRealtime();
  }

  /// Bỏ một nhóm khỏi danh sách ngay (đã rời / đã bị xoá), không chờ tải lại;
  /// đang chọn nhóm đó (máy tính bảng) thì bỏ chọn.
  void removeChannel(String channelId) {
    final id = channelId.trim();
    if (id.isEmpty) return;
    bool matches(ConversationSummary item) =>
        item.channelId == id || item.id == id;
    final selected = state.selectedConversation;
    state = state.copyWith(
      conversations: state.conversations
          .where((item) => !matches(item))
          .toList(growable: false),
      channels: state.channels
          .where((item) => !matches(item))
          .toList(growable: false),
      clearSelection: selected != null && matches(selected),
    );
    _forgetUnreadMessages(id);
    // Rời phòng realtime của nhóm ngay (đã rời / bị xoá): không nhận tiếp tin.
    _watchListRealtime();
  }

  Future<void> _loadListPrefs() async {
    final repository = _listPrefsRepository;
    final userId = _currentUserId?.call()?.trim();
    if (repository == null || userId == null || userId.isEmpty) return;
    if (_listPrefsUserId == userId) return;
    try {
      final prefs = await repository.read(
        userId: userId,
        workspaceId: state.workspaceId,
      );
      if (!mounted) return;
      _listPrefsUserId = userId;
      state = state.copyWith(listPrefs: prefs);
    } on Object catch (error) {
      // Đọc lỗi: danh sách vẫn chạy, chỉ thiếu ghim / ẩn của máy.
      debugPrint('Không đọc được ghim / ẩn trên máy: $error');
    }
  }

  void _setListPrefs(ConversationListPrefs next) {
    state = state.copyWith(listPrefs: next);
    final repository = _listPrefsRepository;
    final userId = _currentUserId?.call()?.trim();
    if (repository == null || userId == null || userId.isEmpty) return;
    _listPrefsUserId = userId;
    unawaited(
      repository
          .save(userId: userId, workspaceId: state.workspaceId, prefs: next)
          .catchError((Object error) {
            debugPrint('Không lưu được ghim / ẩn trên máy: $error');
          }),
    );
  }

  void _clearMarkedUnread(String channelId) {
    if (!state.listPrefs.markedUnread.contains(channelId)) return;
    _setListPrefs(state.listPrefs.withMarkedUnread(channelId, false));
  }

  /// Ghim / bỏ ghim hội thoại trên máy này.
  void setPinned(ConversationSummary conversation, bool pinned) {
    _setListPrefs(state.listPrefs.withPinned(conversation.channelId, pinned));
  }

  /// Đánh dấu chưa đọc (chấm / số 1 tới khi mở lại) hoặc đã đọc trên máy này.
  /// Đánh dấu đã đọc chỉ cập nhật danh sách; người gọi (menu ấn giữ) phải báo
  /// máy chủ trước, nếu không lần đồng bộ sau số chưa đọc sẽ hiện lại.
  void setMarkedUnread(ConversationSummary conversation, bool unread) {
    final id = conversation.channelId;
    _setListPrefs(state.listPrefs.withMarkedUnread(id, unread));
    if (!unread && conversation.unreadCount > 0) {
      _forgetUnreadMessages(id);
      final read = _withoutUnread(conversation);
      state = state.copyWith(
        conversations: _markOpenedInList(state.conversations, read),
        channels: _markOpenedInList(state.channels, read),
      );
    }
  }

  /// Ẩn trò chuyện khỏi danh sách (tin mới thì hiện lại) hoặc bỏ ẩn.
  void setHidden(ConversationSummary conversation, bool hidden) {
    _setListPrefs(
      state.listPrefs.withHidden(
        conversation.channelId,
        hidden ? ConversationListPrefs.activityOf(conversation) : null,
      ),
    );
  }

  /// Gỡ chat 1-1 khỏi danh sách trên máy này (tin trên máy chủ vẫn còn; có
  /// tin mới thì hiện lại): bỏ ghim, bỏ chưa đọc.
  void removeFromList(ConversationSummary conversation) {
    _setListPrefs(
      state.listPrefs.removed(
        conversation.channelId,
        ConversationListPrefs.activityOf(conversation),
      ),
    );
    final selected = state.selectedConversation;
    if (selected != null && _sameConversation(selected, conversation)) {
      state = state.copyWith(clearSelection: true);
    }
  }

  /// Cập nhật tắt tiếng của một hội thoại ngay trên danh sách sau khi máy chủ
  /// đã lưu (không chờ tải lại).
  void setMutedLocally(String channelId, bool muted) {
    List<ConversationSummary> update(List<ConversationSummary> items) => [
      for (final item in items)
        item.channelId == channelId ? item.copyWith(muted: muted) : item,
    ];
    state = state.copyWith(
      conversations: update(state.conversations),
      channels: update(state.channels),
    );
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    await load();
    state = state.copyWith(isRefreshing: false);
  }

  /// Hiện diện mới từ `workspacePresenceProvider` (tải lại mỗi 30 giây): cập
  /// nhật chấm trực tuyến của danh sách mà không tải lại cả danh sách.
  void applyPresence(Map<String, ConversationPresence> presence) {
    if (mapEquals(presence, state.presenceByUserId)) return;
    state = state.copyWith(presenceByUserId: presence);
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
    _clearMarkedUnread(conversation.channelId);
    _forgetUnreadMessages(conversation.channelId);
    final opened = _withoutUnread(conversation);
    state = state.copyWith(
      conversations: _markOpenedInList(state.conversations, opened),
      channels: _markOpenedInList(state.channels, opened),
      selectedConversation: opened,
    );
  }

  void markConversationOpened(ConversationSummary conversation) {
    _clearMarkedUnread(conversation.channelId);
    if (!conversation.isUnread) {
      return;
    }
    _forgetUnreadMessages(conversation.channelId);
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
          noticeMessage: tr(
            'Đã mở hội thoại với ${contact.displayName}.',
            'Opened chat with ${contact.displayName}.',
          ),
        );
        // Mở phòng ngay; danh sách cập nhật ngầm phía sau.
        unawaited(syncSilently());
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
          noticeMessage: tr(
            'Đã mở phiên hỗ trợ riêng tư.',
            'Private support chat opened.',
          ),
        );
        // Mở phòng ngay; danh sách cập nhật ngầm phía sau.
        unawaited(syncSilently());
        return conversation;
      case FailureResult<ConversationSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
        return null;
    }
  }
}

/// Dòng phụ chat 1-1 từ tin realtime; `null` = giữ dòng cũ.
String? _realtimePreview(ChatMessage message) {
  if (message.isSecret) return tr('Tin nhắn bí mật', 'Secret message');
  if (message.body.trim().isNotEmpty) return message.body;
  if (message.attachments.isNotEmpty) {
    return tr('Đã gửi tệp đính kèm', 'Sent an attachment');
  }
  return null;
}

/// Máy chủ đếm tin chưa đọc tối đa tới số này (`UnreadCountCap`).
const int _unreadCountCap = 100;

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
        if (isHiddenSystemChannel(conversation)) return false;
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
  String? openChannelId,
  ConversationListPrefs prefs = ConversationListPrefs.empty,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  // Kênh chưa tham gia không vào hộp thư (ở Danh bạ > Kênh); kênh thường đã
  // tham gia chỉ vào khi là kênh nội bộ mặc định hoặc đã có tin. Ghim / chưa
  // đọc của máy áp trước khi gộp để thứ tự (ghim lên đầu) đúng.
  final items = mergeInboxConversations(
    directs: prefs.isEmpty ? directs : directs.map(prefs.apply).toList(),
    channels: prefs.isEmpty ? channels : channels.map(prefs.apply).toList(),
    openChannelId: openChannelId,
  );

  final result = items
      .where((item) {
        if (item.isAutomation && !automationEnabled) return false;
        if (isHiddenSystemChannel(item)) return false;
        // Ẩn trên máy: chỉ hiện khi tìm (như Zalo tìm lại trò chuyện ẩn).
        if (normalizedQuery.isEmpty && prefs.isHidden(item)) return false;
        final matchesFilter = switch (filter) {
          ConversationListFilter.all =>
            !item.isAutomation || normalizedQuery.isNotEmpty,
          ConversationListFilter.unread => item.isUnread,
          ConversationListFilter.direct => _isPersonalChat(item),
          ConversationListFilter.group => _isGroupChat(item),
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
  return result;
}

/// Chat 1-1 với người: không gồm chat bot thông báo, kênh, nhóm.
/// Nhóm / kênh thường (không phải kênh nghiệp vụ, không phải chat bot thông
/// báo: máy chủ trả chat bot dưới dạng kênh nhưng nó không phải nhóm).
bool _isGroupChat(ConversationSummary item) {
  return item.kind == ConversationKind.channel &&
      !item.isAutomation &&
      !item.noticeBot;
}

bool _isPersonalChat(ConversationSummary item) =>
    item.kind == ConversationKind.direct &&
    !item.noticeBot &&
    !item.isAutomation;

bool _matchesQuery(ConversationSummary item, String normalizedQuery) {
  return '${item.title} ${item.preview}'.toLowerCase().contains(
    normalizedQuery,
  );
}

bool _matchesChannelName(ConversationSummary channel, String normalizedQuery) {
  return normalizedQuery.isEmpty ||
      channel.title.toLowerCase().contains(normalizedQuery);
}

int _compareChannelName(ConversationSummary left, ConversationSummary right) {
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
