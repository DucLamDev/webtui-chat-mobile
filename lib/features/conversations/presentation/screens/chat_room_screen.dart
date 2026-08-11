import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../moderation/presentation/widgets/moderation_actions.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/chat_room_controller.dart';
import '../widgets/collaboration_room_sheet.dart';
import '../widgets/message_media_widgets.dart';
import 'webrtc_call_screen.dart';

final _forwardChannelsProvider = FutureProvider.autoDispose
    .family<List<ConversationSummary>, String>((ref, workspaceId) async {
      final result = await ref
          .watch(conversationRepositoryProvider)
          .listChannels(workspaceId: workspaceId);
      return switch (result) {
        Success<List<ConversationSummary>>(value: final channels) => channels,
        FailureResult<List<ConversationSummary>>(failure: final failure) =>
          throw Exception(failure.message),
      };
    });

enum ChatModerationSafetyStatus { loading, error, ready }

ChatModerationSafetyStatus chatModerationSafetyStatus(
  ModerationState moderationState,
) {
  if (moderationState.isLoadingBlockedUsers) {
    return ChatModerationSafetyStatus.loading;
  }
  if (moderationState.errorMessage != null) {
    return ChatModerationSafetyStatus.error;
  }
  return ChatModerationSafetyStatus.ready;
}

bool shouldOfferMessageReport(ChatMessage message) => !message.isMine;

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    required this.channelId,
    required this.title,
    this.workspaceId,
    this.avatarUrl,
    this.initialMessageId,
    this.conversation,
    this.peerUserId,
    this.participantIds = const [],
    this.embedded = false,
    super.key,
  });

  final String? workspaceId;
  final String channelId;
  final String title;
  final String? avatarUrl;
  final String? initialMessageId;
  final ConversationSummary? conversation;
  final String? peerUserId;
  final List<String> participantIds;
  final bool embedded;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen>
    with WidgetsBindingObserver {
  final _draftController = TextEditingController();
  final _draftFocusNode = FocusNode();
  ChatRoomController? _chatController;
  String? _appliedInitialMessageId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    final controller = _chatController;
    if (controller != null) {
      unawaited(controller.persistDraft());
    }
    WidgetsBinding.instance.removeObserver(this);
    _draftFocusNode.dispose();
    _draftController.dispose();
    super.dispose();
  }

  void _replaceDraftText(String draft) {
    _draftController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _chatController;
    if (controller == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.load());
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      controller.suspendRealtime();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        widget.workspaceId ??
        ref.watch(workspaceControllerProvider).activeWorkspace?.id;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: WebTuiEmptyState(
            title: 'Chưa chọn workspace',
            message: 'Bạn cần chọn workspace trước khi mở hội thoại.',
            icon: Icons.business_rounded,
          ),
        ),
      );
    }

    final moderationProvider = moderationControllerProvider(workspaceId);
    final moderationState = ref.watch(moderationProvider);
    switch (chatModerationSafetyStatus(moderationState)) {
      case ChatModerationSafetyStatus.loading:
        return _moderationSafetyGate(
          const KeyedSubtree(
            key: Key('chat_moderation_loading_gate'),
            child: WebTuiLoadingState(
              message: 'Đang áp dụng cài đặt an toàn...',
            ),
          ),
        );
      case ChatModerationSafetyStatus.error:
        return _moderationSafetyGate(
          KeyedSubtree(
            key: const Key('chat_moderation_error_gate'),
            child: WebTuiErrorState(
              title: 'Chưa thể mở hội thoại an toàn',
              message: moderationState.errorMessage!,
              onRetry: () => unawaited(
                ref.read(moderationProvider.notifier).loadBlockedUsers(),
              ),
            ),
          ),
        );
      case ChatModerationSafetyStatus.ready:
        break;
    }

    final scope = ChatRoomScope(
      workspaceId: workspaceId,
      channelId: widget.channelId,
      title: widget.title,
    );
    final provider = chatRoomControllerProvider(scope);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final serverCapabilities = ref.watch(
      activeServerDiscoveryProvider.select((value) => value?.capabilities),
    );
    final callsEnabled = serverCapabilities?.calls ?? false;
    final filesEnabled = serverCapabilities?.files ?? false;
    final safetyTargetUserId = _safetyTargetUserId(state);
    final interactionBlocked =
        safetyTargetUserId != null &&
        moderationState.isBlocked(safetyTargetUserId);
    _chatController = controller;
    final initialMessageId = widget.initialMessageId?.trim();
    if (initialMessageId != null &&
        initialMessageId.isNotEmpty &&
        _appliedInitialMessageId != initialMessageId) {
      _appliedInitialMessageId = initialMessageId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.highlightMessage(initialMessageId);
      });
    }

    ref.listen<ChatRoomState>(provider, (previous, next) {
      final draftChanged = previous?.draft != next.draft;
      final editingChanged =
          previous?.editingMessage?.id != next.editingMessage?.id;
      if (!draftChanged || _draftController.text == next.draft) {
        return;
      }

      // Avoid writing over active input; doing so clears IME composing text.
      final canApplyExternalDraft =
          !_draftFocusNode.hasFocus || next.draft.isEmpty || editingChanged;
      if (canApplyExternalDraft) {
        _replaceDraftText(next.draft);
      }
    });

    final body = PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) {
        unawaited(controller.persistDraft());
      },
      child: _ChatRoomBody(
        workspaceId: workspaceId,
        state: state,
        draftController: _draftController,
        draftFocusNode: _draftFocusNode,
        onDraftChanged: controller.updateDraft,
        onThreadDraftChanged: controller.updateThreadDraft,
        onPickAttachment: filesEnabled
            ? controller.pickAttachment
            : (_) => _showCapabilityUnavailable(
                context,
                'Máy chủ này không bật tính năng tệp đính kèm.',
              ),
        onStartVoiceRecording: () =>
            unawaited(controller.startVoiceRecording()),
        onStopVoiceRecording: () => unawaited(controller.stopVoiceRecording()),
        onCancelVoiceRecording: () =>
            unawaited(controller.cancelVoiceRecording()),
        onRetryAttachment: controller.retryAttachment,
        onRemoveAttachment: controller.removeAttachment,
        onRetry: controller.load,
        onRetryOutbox: interactionBlocked
            ? () => _showBlockedSharedContentGuidance(context)
            : () => unawaited(controller.retryOutbox()),
        onLoadOlder: controller.loadOlder,
        onClearSearch: controller.clearSearch,
        onSend: (silent) =>
            unawaited(controller.sendCurrentDraft(silent: silent)),
        onSchedule: () => unawaited(
          _scheduleCurrentDraft(context, workspaceId, controller, state),
        ),
        onCreatePoll: () =>
            unawaited(_openPollComposer(context, workspaceId, controller)),
        onSendThread: interactionBlocked
            ? () => _showBlockedSharedContentGuidance(context)
            : controller.sendThreadDraft,
        onReply: controller.startReply,
        onReplyPrivately: (message) => interactionBlocked
            ? _showBlockedSharedContentGuidance(context)
            : unawaited(_replyPrivately(context, workspaceId, message)),
        blockedUserIds: moderationState.blockedUserIds,
        interactionBlocked: interactionBlocked,
        onManageBlockedConversation: safetyTargetUserId == null
            ? null
            : () => showUserSafetyActions(
                context,
                ref,
                workspaceId: workspaceId,
                userId: safetyTargetUserId,
                userLabel: widget.title,
              ),
        onReportMessage: (message) => unawaited(
          reportMessage(
            context,
            ref,
            workspaceId: workspaceId,
            messageId: message.id,
          ),
        ),
        onReportUser: (message) {
          final senderId = message.senderId?.trim();
          if (senderId == null || senderId.isEmpty) return;
          unawaited(
            reportUser(
              context,
              ref,
              workspaceId: workspaceId,
              userId: senderId,
              userLabel: 'người gửi',
            ),
          );
        },
        onToggleBlockUser: (message) {
          final senderId = message.senderId?.trim();
          if (senderId == null || senderId.isEmpty) return;
          unawaited(
            toggleUserBlock(
              context,
              ref,
              workspaceId: workspaceId,
              userId: senderId,
              userLabel: 'người gửi',
            ),
          );
        },
        onConvertToTask: (message) => interactionBlocked
            ? _showBlockedSharedContentGuidance(context)
            : unawaited(_convertMessageToTask(context, workspaceId, message)),
        onEdit: interactionBlocked
            ? (_) => _showBlockedSharedContentGuidance(context)
            : controller.startEdit,
        onDelete: controller.deleteMessage,
        onReact: interactionBlocked
            ? (_, _) => _showBlockedSharedContentGuidance(context)
            : controller.toggleReaction,
        onPin: interactionBlocked
            ? (_) => _showBlockedSharedContentGuidance(context)
            : controller.togglePin,
        onThread: controller.loadThread,
        onForward: interactionBlocked
            ? (_, _) => _showBlockedSharedContentGuidance(context)
            : controller.forwardMessage,
        onClearThread: controller.clearThread,
        onFocusMessage: controller.focusMessage,
        onCancelComposerContext: controller.cancelComposerContext,
        onRetryAudioCall: callsEnabled
            ? interactionBlocked
                  ? () => _showCapabilityUnavailable(
                      context,
                      'Hãy bỏ chặn người dùng trước khi gọi.',
                    )
                  : () => unawaited(
                      _startCallFromCurrentConversation(
                        context,
                        controller,
                        state,
                        CallMode.audio,
                      ),
                    )
            : () => _showCapabilityUnavailable(
                context,
                'Máy chủ này không bật cuộc gọi.',
              ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: WebTuiColors.chatBackground,
        child: Column(
          children: [
            _EmbeddedChatHeader(
              title: widget.title,
              avatarUrl: widget.avatarUrl,
              onDetails: () => _openDetails(context),
              onSafety: safetyTargetUserId == null
                  ? null
                  : () => showUserSafetyActions(
                      context,
                      ref,
                      workspaceId: workspaceId,
                      userId: safetyTargetUserId,
                      userLabel: widget.title,
                    ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: WebTuiColors.chatBackground,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: WebTuiColors.chatHeader,
        foregroundColor: WebTuiColors.textOnPrimary,
        iconTheme: const IconThemeData(color: WebTuiColors.textOnPrimary),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.titleMedium.copyWith(
            color: WebTuiColors.textOnPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tìm tin nhắn',
            onPressed: () =>
                _openSearch(context, controller, state.searchQuery),
            icon: const Icon(CupertinoIcons.search, size: 21),
          ),
          if (callsEnabled) ...[
            IconButton(
              tooltip: 'Gọi thoại',
              onPressed: interactionBlocked
                  ? () => _showCapabilityUnavailable(
                      context,
                      'Hãy bỏ chặn người dùng trước khi gọi.',
                    )
                  : () => unawaited(
                      _startCallFromCurrentConversation(
                        context,
                        controller,
                        state,
                        CallMode.audio,
                      ),
                    ),
              icon: const Icon(CupertinoIcons.phone, size: 21),
            ),
            IconButton(
              tooltip: 'Gọi video',
              onPressed: interactionBlocked
                  ? () => _showCapabilityUnavailable(
                      context,
                      'Hãy bỏ chặn người dùng trước khi gọi.',
                    )
                  : () => unawaited(
                      _startCallFromCurrentConversation(
                        context,
                        controller,
                        state,
                        CallMode.video,
                      ),
                    ),
              icon: const Icon(CupertinoIcons.video_camera, size: 22),
            ),
          ],
          if (safetyTargetUserId != null)
            IconButton(
              tooltip: 'Báo cáo hoặc chặn người dùng',
              onPressed: () => showUserSafetyActions(
                context,
                ref,
                workspaceId: workspaceId,
                userId: safetyTargetUserId,
                userLabel: widget.title,
              ),
              icon: const Icon(Icons.shield_outlined, size: 22),
            ),
          IconButton(
            key: const Key('chat_collaboration_tools_action'),
            tooltip: 'Công cụ làm việc',
            onPressed: interactionBlocked
                ? () => _showBlockedSharedContentGuidance(context)
                : () => showCollaborationRoomSheet(
                    context,
                    workspaceId: workspaceId,
                    channelId: widget.channelId,
                    title: widget.title,
                    conversation: widget.conversation,
                  ),
            icon: const Icon(CupertinoIcons.square_grid_2x2, size: 21),
          ),
          IconButton(
            tooltip: 'Chi tiết kênh',
            onPressed: () => _openDetails(context),
            icon: const Icon(CupertinoIcons.line_horizontal_3, size: 23),
          ),
        ],
      ),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _moderationSafetyGate(Widget child) {
    final body = SafeArea(child: Center(child: child));
    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }

  void _openDetails(BuildContext context) {
    context.push(
      Uri(
        path: '/channels/${widget.channelId}',
        queryParameters: {'title': widget.title},
      ).toString(),
    );
  }

  void _showBlockedSharedContentGuidance(BuildContext context) {
    _showCapabilityUnavailable(
      context,
      'Hãy bỏ chặn người dùng trước khi tạo hoặc thay đổi nội dung dùng chung.',
    );
  }

  String? _safetyTargetUserId(ChatRoomState state) {
    final explicitPeer = widget.peerUserId?.trim();
    if (explicitPeer != null && explicitPeer.isNotEmpty) {
      return explicitPeer;
    }
    final conversation = widget.conversation;
    if (conversation?.kind != ConversationKind.direct) {
      return null;
    }
    return conversation?.directCallTargetUserId(
      currentUserId: state.currentUserId,
    );
  }

  void _showCapabilityUnavailable(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _replyPrivately(
    BuildContext context,
    String workspaceId,
    ChatMessage message,
  ) async {
    final senderId = message.senderId?.trim();
    if (message.isMine || senderId == null || senderId.isEmpty) {
      return;
    }
    try {
      final conversation = await ref
          .read(conversationRemoteDataSourceProvider)
          .createDirectConversation(
            workspaceId: workspaceId,
            participantIds: [senderId],
            sourceChannelId: widget.channelId,
          );
      final draft = 'Trả lời riêng tư:\n> ${_displayMessageBody(message)}\n\n';
      await ref
          .read(saveDraftUseCaseProvider)
          .execute(
            workspaceId: workspaceId,
            channelId: conversation.channelId,
            body: draft,
          );
      if (!context.mounted) return;
      await context.push(
        Uri(
          path: '/conversations/${conversation.channelId}',
          queryParameters: {
            'workspaceId': workspaceId,
            'title': conversation.title,
            if (conversation.peerUserId != null)
              'peerUserId': conversation.peerUserId,
          },
        ).toString(),
        extra: conversation,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _convertMessageToTask(
    BuildContext context,
    String workspaceId,
    ChatMessage message,
  ) async {
    final body = _displayMessageBody(message);
    final title = body.length > 240 ? body.substring(0, 240) : body;
    try {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .createCollaborationTask(
            workspaceId: workspaceId,
            channelId: widget.channelId,
            title: title,
            sourceMessageId: message.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chuyển tin nhắn thành task.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openSearch(
    BuildContext context,
    ChatRoomController controller,
    String initialQuery,
  ) async {
    final textController = TextEditingController(text: initialQuery);
    final query = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: WebTuiColors.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              MediaQuery.viewInsetsOf(context).bottom + WebTuiSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tìm trong tin nhắn',
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.md),
                TextField(
                  controller: textController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                  decoration: InputDecoration(
                    hintText: 'Nhập từ khóa...',
                    prefixIcon: const Icon(CupertinoIcons.search, size: 19),
                    filled: true,
                    fillColor: WebTuiColors.backgroundMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: WebTuiSpacing.md,
                      vertical: WebTuiSpacing.sm,
                    ),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.md),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        controller.clearSearch();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Xóa tìm kiếm'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(textController.text),
                      child: const Text('Tìm'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    textController.dispose();
    final normalized = query?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      await controller.search(normalized);
    }
  }

  Future<void> _startCallFromCurrentConversation(
    BuildContext context,
    ChatRoomController controller,
    ChatRoomState state,
    CallMode mode,
  ) async {
    final targetUserId = _callTargetUserId(state);
    if (targetUserId == null) {
      _showCallUnavailable(context);
      return;
    }
    _draftFocusNode.unfocus();
    final call = await controller.startCall(
      targetUserId: targetUserId,
      mode: mode,
    );
    if (!context.mounted || call == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WebRtcCallScreen(
          workspaceId: call.workspaceId,
          channelId: call.channelId,
          callId: call.id,
          title: widget.title,
          mode: mode,
          onLeave: controller.load,
        ),
      ),
    );
  }

  String? _callTargetUserId(ChatRoomState state) {
    final targetFromConversation = widget.conversation?.directCallTargetUserId(
      currentUserId: state.currentUserId,
    );
    if (targetFromConversation != null) {
      return targetFromConversation;
    }
    final current = state.currentUserId?.trim();
    final routePeerUserId = widget.peerUserId?.trim();
    if (routePeerUserId != null &&
        routePeerUserId.isNotEmpty &&
        routePeerUserId != current) {
      return routePeerUserId;
    }
    final candidates = widget.participantIds
        .map((participantId) => participantId.trim())
        .where((participantId) => participantId.isNotEmpty)
        .toSet();
    if (current == null || current.isEmpty) {
      return candidates.length == 1 ? candidates.first : null;
    }
    for (final candidate in candidates) {
      if (candidate != current) {
        return candidate;
      }
    }
    return null;
  }

  void _showCallUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cuộc gọi hiện chỉ hỗ trợ hội thoại riêng 1-1.'),
      ),
    );
  }

  Future<void> _scheduleCurrentDraft(
    BuildContext context,
    String workspaceId,
    ChatRoomController controller,
    ChatRoomState state,
  ) async {
    final body = state.draft.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập nội dung trước khi hẹn giờ gửi.')),
      );
      return;
    }
    final delay = await showModalBottomSheet<Duration>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.sm,
            WebTuiSpacing.lg,
            WebTuiSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hẹn giờ gửi',
                style: WebTuiTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Sau 15 phút'),
                onTap: () =>
                    Navigator.pop(context, const Duration(minutes: 15)),
              ),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Sau 1 giờ'),
                onTap: () => Navigator.pop(context, const Duration(hours: 1)),
              ),
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Sáng mai'),
                onTap: () {
                  final now = DateTime.now();
                  final tomorrow = DateTime(
                    now.year,
                    now.month,
                    now.day + 1,
                    8,
                  );
                  Navigator.pop(context, tomorrow.difference(now));
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (delay == null) return;
    try {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .scheduleMessage(
            workspaceId: workspaceId,
            channelId: widget.channelId,
            body: body,
            scheduledFor: DateTime.now().add(delay),
          );
      controller.updateDraft('');
      await controller.persistDraft();
      if (context.mounted) {
        _replaceDraftText('');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lên lịch gửi tin nhắn.')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _openPollComposer(
    BuildContext context,
    String workspaceId,
    ChatRoomController controller,
  ) async {
    final poll = await showDialog<_PollDraft>(
      context: context,
      builder: (_) => const _PollComposerDialog(),
    );
    if (poll == null || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(conversationRemoteDataSourceProvider)
          .createPoll(
            workspaceId: workspaceId,
            channelId: widget.channelId,
            question: poll.question,
            options: poll.options,
            multiple: poll.multiple,
            anonymous: poll.anonymous,
          );
      await controller.load();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo bình chọn cho phòng.')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tạo được bình chọn: $error')),
        );
      }
    }
  }
}

class _ChatRoomBody extends StatefulWidget {
  const _ChatRoomBody({
    required this.workspaceId,
    required this.state,
    required this.draftController,
    required this.draftFocusNode,
    required this.onDraftChanged,
    required this.onThreadDraftChanged,
    required this.onPickAttachment,
    required this.onStartVoiceRecording,
    required this.onStopVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onRetryAttachment,
    required this.onRemoveAttachment,
    required this.onRetry,
    required this.onRetryOutbox,
    required this.onLoadOlder,
    required this.onClearSearch,
    required this.onSend,
    required this.onSchedule,
    required this.onCreatePoll,
    required this.onSendThread,
    required this.onReply,
    required this.onReplyPrivately,
    required this.blockedUserIds,
    required this.interactionBlocked,
    required this.onManageBlockedConversation,
    required this.onReportMessage,
    required this.onReportUser,
    required this.onToggleBlockUser,
    required this.onConvertToTask,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onPin,
    required this.onThread,
    required this.onForward,
    required this.onClearThread,
    required this.onFocusMessage,
    required this.onCancelComposerContext,
    required this.onRetryAudioCall,
  });

  final String workspaceId;
  final ChatRoomState state;
  final TextEditingController draftController;
  final FocusNode draftFocusNode;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String> onThreadDraftChanged;
  final ValueChanged<MessageAttachmentPickSource> onPickAttachment;
  final VoidCallback onStartVoiceRecording;
  final VoidCallback onStopVoiceRecording;
  final VoidCallback onCancelVoiceRecording;
  final ValueChanged<String> onRetryAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onRetry;
  final VoidCallback onRetryOutbox;
  final VoidCallback onLoadOlder;
  final VoidCallback onClearSearch;
  final ValueChanged<bool> onSend;
  final VoidCallback onSchedule;
  final VoidCallback onCreatePoll;
  final VoidCallback onSendThread;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onReplyPrivately;
  final Set<String> blockedUserIds;
  final bool interactionBlocked;
  final VoidCallback? onManageBlockedConversation;
  final ValueChanged<ChatMessage> onReportMessage;
  final ValueChanged<ChatMessage> onReportUser;
  final ValueChanged<ChatMessage> onToggleBlockUser;
  final ValueChanged<ChatMessage> onConvertToTask;
  final ValueChanged<ChatMessage> onEdit;
  final ValueChanged<ChatMessage> onDelete;
  final void Function(ChatMessage message, String emoji) onReact;
  final ValueChanged<ChatMessage> onPin;
  final ValueChanged<ChatMessage> onThread;
  final void Function(ChatMessage message, String targetChannelId) onForward;
  final VoidCallback onClearThread;
  final ValueChanged<ChatMessage> onFocusMessage;
  final VoidCallback onCancelComposerContext;
  final VoidCallback onRetryAudioCall;

  @override
  State<_ChatRoomBody> createState() => _ChatRoomBodyState();
}

class _ChatRoomBodyState extends State<_ChatRoomBody> {
  final _scrollController = ScrollController();
  final _messageKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _scheduleScrollToBottom(jump: true);
  }

  @override
  void didUpdateWidget(covariant _ChatRoomBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loadedOlder =
        oldWidget.state.isLoadingOlder && !widget.state.isLoadingOlder;
    if (!loadedOlder &&
        (oldWidget.state.messages.length != widget.state.messages.length ||
            (oldWidget.state.isLoading && !widget.state.isLoading))) {
      final highlightedMessageId = widget.state.highlightedMessageId;
      if (highlightedMessageId != null) {
        _scheduleScrollToMessage(highlightedMessageId);
      } else {
        _scheduleScrollToBottom(jump: oldWidget.state.isLoading);
      }
    }
    if (oldWidget.state.highlightedMessageId !=
        widget.state.highlightedMessageId) {
      final messageId = widget.state.highlightedMessageId;
      if (messageId != null) {
        _scheduleScrollToMessage(messageId);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final visiblePinnedMessages = widget.state.pinnedMessages
        .where((message) => !_isBlockedMessage(message))
        .toList(growable: false);
    final threadRoot = widget.state.threadRootMessage;
    return Column(
      children: [
        if (widget.state.searchQuery.isNotEmpty)
          _MessageSearchPanel(
            state: widget.state,
            blockedUserIds: widget.blockedUserIds,
            onClear: widget.onClearSearch,
            onOpenResult: widget.onFocusMessage,
          ),
        if (visiblePinnedMessages.isNotEmpty)
          _PinnedMessagesBar(
            messages: visiblePinnedMessages,
            onOpen: widget.onFocusMessage,
          ),
        if (threadRoot != null && !_isBlockedMessage(threadRoot))
          _ThreadPanel(
            rootMessage: threadRoot,
            messages: widget.state.threadMessages
                .where((message) => !_isBlockedMessage(message))
                .toList(growable: false),
            draft: widget.state.threadDraft,
            sending: widget.state.isSendingThread,
            onDraftChanged: widget.onThreadDraftChanged,
            onSend: widget.onSendThread,
            onClose: widget.onClearThread,
          ),
        if (widget.state.errorMessage != null)
          _InlineError(
            message: widget.state.errorMessage!,
            onRetry: widget.onRetry,
          ),
        Expanded(
          child: ColoredBox(
            color: WebTuiColors.chatBackground,
            child: widget.state.isLoading
                ? const WebTuiLoadingState(message: 'Đang tải tin nhắn...')
                : widget.state.messages.isEmpty
                ? const _ChatEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(900),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      WebTuiSpacing.md,
                      WebTuiSpacing.md,
                      WebTuiSpacing.md,
                      WebTuiSpacing.xl,
                    ),
                    itemCount:
                        widget.state.messages.length +
                        (widget.state.hasMore || widget.state.isLoadingOlder
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      final hasOlderHeader =
                          widget.state.hasMore || widget.state.isLoadingOlder;
                      if (hasOlderHeader && index == 0) {
                        return _LoadOlderTile(
                          loading: widget.state.isLoadingOlder,
                          onPressed: widget.onLoadOlder,
                        );
                      }
                      final messageIndex = hasOlderHeader ? index - 1 : index;
                      final message = widget.state.messages[messageIndex];
                      final previous = messageIndex == 0
                          ? null
                          : widget.state.messages[messageIndex - 1];
                      final showDay =
                          previous == null ||
                          !_sameDay(previous.createdAt, message.createdAt);
                      final sameSender =
                          previous != null &&
                          previous.senderId == message.senderId &&
                          !showDay;
                      final senderId = message.senderId?.trim();
                      final senderBlocked =
                          !message.isMine &&
                          senderId != null &&
                          widget.blockedUserIds.contains(senderId);
                      return Container(
                        key: _messageKey(message.id),
                        padding: EdgeInsets.only(
                          top: sameSender ? WebTuiSpacing.xs : WebTuiSpacing.md,
                        ),
                        child: AnimatedContainer(
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          decoration: BoxDecoration(
                            color:
                                widget.state.highlightedMessageId == message.id
                                ? WebTuiColors.accentAmber.withValues(
                                    alpha: 0.16,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                          ),
                          child: Column(
                            children: [
                              if (showDay) _DayDivider(date: message.createdAt),
                              if (showDay)
                                const SizedBox(height: WebTuiSpacing.md),
                              if (message.isSystem)
                                _isMissedCallMessage(message)
                                    ? _MissedCallCard(
                                        outgoing: false,
                                        title: _missedCallTitle(message),
                                        timeLabel: _timeLabel(
                                          message.createdAt,
                                        ),
                                        onRetry: widget.onRetryAudioCall,
                                      )
                                    : _SystemMessage(text: message.body)
                              else if (senderBlocked)
                                _BlockedMessagePlaceholder(
                                  onManage: () =>
                                      widget.onToggleBlockUser(message),
                                )
                              else
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: () => _showMessageActions(
                                    context,
                                    workspaceId: widget.workspaceId,
                                    currentChannelId:
                                        widget.state.scope.channelId,
                                    message: message,
                                    onReply: widget.onReply,
                                    onReplyPrivately: widget.onReplyPrivately,
                                    isSenderBlocked: senderBlocked,
                                    sharedContentBlocked:
                                        widget.interactionBlocked,
                                    onReportMessage: widget.onReportMessage,
                                    onReportUser: widget.onReportUser,
                                    onToggleBlockUser: widget.onToggleBlockUser,
                                    onConvertToTask: widget.onConvertToTask,
                                    onEdit: widget.onEdit,
                                    onDelete: widget.onDelete,
                                    onReact: widget.onReact,
                                    onPin: widget.onPin,
                                    onThread: widget.onThread,
                                    onForward: widget.onForward,
                                  ),
                                  child: Semantics(
                                    container: true,
                                    excludeSemantics: true,
                                    label: _messageSemanticLabel(
                                      message,
                                      _displayMessageBody(message),
                                      _messageTimeLabel(message),
                                    ),
                                    child: _MessageRow(
                                      message: message,
                                      title: widget.state.scope.title,
                                      showAvatar:
                                          !message.isMine && !sameSender,
                                      outgoing: message.isMine,
                                      text: _displayMessageBody(message),
                                      timeLabel: _messageTimeLabel(message),
                                      reactions: _reactionLabels(
                                        message.reactions,
                                      ),
                                      onReact: (emoji) =>
                                          widget.onReact(message, emoji),
                                      onRetryAudioCall: widget.onRetryAudioCall,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (widget.state.hasTypingUsers) const _TypingIndicator(),
        if (widget.state.hasOutboxItems)
          _OutboxStatusBar(state: widget.state, onRetry: widget.onRetryOutbox),
        if (widget.interactionBlocked)
          _BlockedConversationComposer(
            onManage: widget.onManageBlockedConversation,
          )
        else
          _Composer(
            controller: widget.draftController,
            focusNode: widget.draftFocusNode,
            sending: widget.state.isSending,
            canSend: widget.state.canSend,
            isRecordingVoice: widget.state.isRecordingVoice,
            voiceRecordingStartedAt: widget.state.voiceRecordingStartedAt,
            attachments: widget.state.pendingAttachments,
            replyToMessage: widget.state.replyToMessage,
            editingMessage: widget.state.editingMessage,
            onChanged: widget.onDraftChanged,
            onPickAttachment: widget.onPickAttachment,
            onStartVoiceRecording: widget.onStartVoiceRecording,
            onStopVoiceRecording: widget.onStopVoiceRecording,
            onCancelVoiceRecording: widget.onCancelVoiceRecording,
            onRetryAttachment: widget.onRetryAttachment,
            onRemoveAttachment: widget.onRemoveAttachment,
            onSend: widget.onSend,
            onSchedule: widget.onSchedule,
            onCreatePoll: widget.onCreatePoll,
            onCancelContext: widget.onCancelComposerContext,
          ),
      ],
    );
  }

  void _scheduleScrollToBottom({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      final disableAnimations = MediaQuery.of(context).disableAnimations;
      if (jump || disableAnimations) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _scheduleScrollToMessage(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final context = _messageKeys[messageId]?.currentContext;
      if (context == null) {
        return;
      }
      final disableAnimations = MediaQuery.of(context).disableAnimations;
      Scrollable.ensureVisible(
        context,
        duration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  GlobalKey _messageKey(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  bool _isBlockedMessage(ChatMessage message) {
    final senderId = message.senderId?.trim();
    return !message.isMine &&
        senderId != null &&
        widget.blockedUserIds.contains(senderId);
  }
}

class _MessageSearchPanel extends StatelessWidget {
  const _MessageSearchPanel({
    required this.state,
    required this.blockedUserIds,
    required this.onClear,
    required this.onOpenResult,
  });

  final ChatRoomState state;
  final Set<String> blockedUserIds;
  final VoidCallback onClear;
  final ValueChanged<ChatMessage> onOpenResult;

  @override
  Widget build(BuildContext context) {
    final visibleResults = state.searchResults
        .where((message) {
          final senderId = message.senderId?.trim();
          return message.isMine ||
              senderId == null ||
              !blockedUserIds.contains(senderId);
        })
        .toList(growable: false);
    return ColoredBox(
      color: WebTuiColors.chatBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: WebTuiColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.sm,
              WebTuiSpacing.xs,
              WebTuiSpacing.xs,
              WebTuiSpacing.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.search,
                      size: 16,
                      color: WebTuiColors.textMuted,
                    ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    Expanded(
                      child: Text(
                        state.isSearching
                            ? 'Đang tìm...'
                            : '${visibleResults.length} kết quả cho "${state.searchQuery}"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.labelSmall.copyWith(
                          color: WebTuiColors.textSecondary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng tìm kiếm',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                if (visibleResults.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: visibleResults.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: WebTuiSpacing.xs),
                      itemBuilder: (context, index) {
                        final message = visibleResults[index];
                        return ActionChip(
                          avatar: const Icon(Icons.center_focus_strong_rounded),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              _displayMessageBody(message),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onPressed: () => onOpenResult(message),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedMessagesBar extends StatelessWidget {
  const _PinnedMessagesBar({required this.messages, required this.onOpen});

  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage> onOpen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.chatBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(width: WebTuiSpacing.xs),
            itemBuilder: (context, index) {
              final message = messages[index];
              return ActionChip(
                avatar: const Icon(Icons.push_pin_rounded),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: Text(
                    _displayMessageBody(message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: () => onOpen(message),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OutboxStatusBar extends StatelessWidget {
  const _OutboxStatusBar({required this.state, required this.onRetry});

  final ChatRoomState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = state.failedOutboxCount;
    final sending = state.sendingOutboxCount;
    final total = state.outboxItems.length;
    final color = failed > 0 ? WebTuiColors.accentAmber : WebTuiColors.primary;
    final text = failed > 0
        ? '$failed tin đang chờ gửi lại'
        : sending > 0
        ? '$sending tin đang gửi lại'
        : '$total tin đang nằm trong hàng chờ';
    return Material(
      color: WebTuiColors.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.6)),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.md,
          vertical: WebTuiSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_outlined, size: 18, color: color),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: sending > 0 ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Gửi lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadOlderTile extends StatelessWidget {
  const _LoadOlderTile({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
        child: TextButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.history_rounded),
          label: Text(loading ? 'Đang tải...' : 'Tải tin cũ hơn'),
        ),
      ),
    );
  }
}

class _ThreadPanel extends StatelessWidget {
  const _ThreadPanel({
    required this.rootMessage,
    required this.messages,
    required this.draft,
    required this.sending,
    required this.onDraftChanged,
    required this.onSend,
    required this.onClose,
  });

  final ChatMessage rootMessage;
  final List<ChatMessage> messages;
  final String draft;
  final bool sending;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final replies = messages
        .where((message) => message.id != rootMessage.id)
        .toList(growable: false);
    final visible = replies.length > 3
        ? replies.sublist(replies.length - 3)
        : replies;
    final canSend = draft.trim().isNotEmpty && !sending;
    return Material(
      color: WebTuiColors.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: WebTuiColors.border.withValues(alpha: 0.7),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.sm,
          WebTuiSpacing.sm,
          WebTuiSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.forum_outlined,
                  size: 18,
                  color: WebTuiColors.primary,
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Text(
                    'Thread (${replies.length})',
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng thread',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 14,
                    color: WebTuiColors.primary,
                  ),
                  const SizedBox(width: WebTuiSpacing.xs),
                  Expanded(
                    child: Text(
                      _displayMessageBody(rootMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final message in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
                child: Text(
                  message.isDeleted ? 'Tin nhắn đã được thu hồi' : message.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: WebTuiSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('${rootMessage.id}:${draft.isEmpty}'),
                    initialValue: draft,
                    enabled: !sending,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.newline,
                    onChanged: onDraftChanged,
                    decoration: InputDecoration(
                      hintText: 'Trả lời trong thread...',
                      isDense: true,
                      filled: true,
                      fillColor: WebTuiColors.backgroundMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: WebTuiSpacing.md,
                        vertical: WebTuiSpacing.sm,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                SizedBox.square(
                  dimension: 38,
                  child: IconButton.filled(
                    tooltip: 'Gửi vào thread',
                    onPressed: canSend ? onSend : null,
                    icon: sending
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WebTuiColors.textOnPrimary,
                            ),
                          )
                        : const Icon(CupertinoIcons.paperplane_fill, size: 18),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.chatBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.xs,
          WebTuiSpacing.lg,
          WebTuiSpacing.sm,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Có người đang nhập...',
            style: WebTuiTypography.labelSmall.copyWith(
              color: WebTuiColors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.canSend,
    required this.isRecordingVoice,
    required this.voiceRecordingStartedAt,
    required this.attachments,
    required this.onChanged,
    required this.onPickAttachment,
    required this.onStartVoiceRecording,
    required this.onStopVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onRetryAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onSchedule,
    required this.onCreatePoll,
    required this.onCancelContext,
    this.replyToMessage,
    this.editingMessage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool canSend;
  final bool isRecordingVoice;
  final DateTime? voiceRecordingStartedAt;
  final List<MessageAttachmentUploadItem> attachments;
  final ChatMessage? replyToMessage;
  final ChatMessage? editingMessage;
  final ValueChanged<String> onChanged;
  final ValueChanged<MessageAttachmentPickSource> onPickAttachment;
  final VoidCallback onStartVoiceRecording;
  final VoidCallback onStopVoiceRecording;
  final VoidCallback onCancelVoiceRecording;
  final ValueChanged<String> onRetryAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final ValueChanged<bool> onSend;
  final VoidCallback onSchedule;
  final VoidCallback onCreatePoll;
  final VoidCallback onCancelContext;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _showEmojiTray = false;
  bool _silent = false;
  Timer? _voiceTicker;
  Duration _voiceElapsed = Duration.zero;

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isRecordingVoice && widget.isRecordingVoice) {
      _startVoiceTicker();
    } else if (oldWidget.isRecordingVoice && !widget.isRecordingVoice) {
      _stopVoiceTicker();
    }
  }

  @override
  void dispose() {
    _voiceTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          border: Border(
            top: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.75)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.md,
            WebTuiSpacing.sm,
            WebTuiSpacing.md,
            WebTuiSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyToMessage != null ||
                  widget.editingMessage != null)
                _ComposerContextBanner(
                  label: widget.editingMessage != null
                      ? 'Đang sửa tin nhắn'
                      : 'Đang trả lời',
                  preview:
                      (widget.editingMessage ?? widget.replyToMessage)?.body ??
                      '',
                  onCancel: widget.onCancelContext,
                ),
              if (widget.attachments.isNotEmpty)
                _AttachmentQueuePreview(
                  attachments: widget.attachments,
                  onRetry: widget.onRetryAttachment,
                  onRemove: widget.onRemoveAttachment,
                ),
              if (_showEmojiTray) ...[
                _EmojiTray(onSelected: _insertEmoji),
                const SizedBox(height: WebTuiSpacing.sm),
              ],
              if (_silent)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
                    child: InputChip(
                      avatar: const Icon(
                        Icons.notifications_off_outlined,
                        size: 16,
                      ),
                      label: const Text('Gửi không thông báo'),
                      onDeleted: () => setState(() => _silent = false),
                    ),
                  ),
                ),
              if (widget.isRecordingVoice) ...[
                _VoiceRecordingBar(
                  elapsed: _voiceElapsed,
                  onCancel: widget.onCancelVoiceRecording,
                  onStop: widget.onStopVoiceRecording,
                ),
                const SizedBox(height: WebTuiSpacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Thêm biểu tượng cảm xúc',
                    onPressed: widget.sending ? null : _toggleEmojiTray,
                    color: WebTuiColors.primary,
                    icon: const Icon(CupertinoIcons.smiley),
                  ),
                  IconButton(
                    tooltip: 'Đính kèm',
                    onPressed: widget.sending ? null : _showAttachmentSheet,
                    color: WebTuiColors.primary,
                    icon: const Icon(CupertinoIcons.plus_circle),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Tùy chọn gửi',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (value) {
                      if (value == 'silent') {
                        setState(() => _silent = !_silent);
                      } else if (value == 'schedule') {
                        widget.onSchedule();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'silent',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.notifications_off_outlined),
                          title: Text(
                            _silent
                                ? 'Bật lại thông báo'
                                : 'Gửi không thông báo',
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'schedule',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.schedule_send_outlined),
                          title: Text('Hẹn giờ gửi'),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 42,
                        maxHeight: 120,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: WebTuiColors.backgroundMuted,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: WebTuiColors.border.withValues(alpha: 0.7),
                          ),
                        ),
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          onChanged: widget.onChanged,
                          onTap: _focusInput,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          keyboardType: TextInputType.multiline,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'Nhập tin nhắn...',
                            hintStyle: WebTuiTypography.bodyMedium.copyWith(
                              color: WebTuiColors.textMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: WebTuiSpacing.md,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  SizedBox.square(
                    dimension: 48,
                    child: IconButton.filled(
                      tooltip: widget.canSend ? 'Gửi' : 'Ghi âm',
                      onPressed: widget.sending || widget.isRecordingVoice
                          ? null
                          : widget.canSend
                          ? _send
                          : _startVoiceRecording,
                      icon: widget.sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: WebTuiColors.textOnPrimary,
                              ),
                            )
                          : Icon(
                              widget.canSend
                                  ? CupertinoIcons.paperplane_fill
                                  : CupertinoIcons.mic_fill,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAttachmentSheet() async {
    setState(() => _showEmojiTray = false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: WebTuiColors.surface,
      builder: (context) {
        final media = MediaQuery.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.78),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                WebTuiSpacing.xs,
                WebTuiSpacing.lg,
                WebTuiSpacing.lg + media.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PermissionRationaleTile(),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.camera,
                    title: 'Chụp ảnh',
                    subtitle: 'Mở camera và gửi ảnh vào cuộc trò chuyện',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPickAttachment(
                        MessageAttachmentPickSource.camera,
                      );
                    },
                  ),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.photo,
                    title: 'Thư viện ảnh',
                    subtitle: 'Chọn ảnh sẵn có trong máy',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPickAttachment(
                        MessageAttachmentPickSource.gallery,
                      );
                    },
                  ),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.video_camera_solid,
                    title: 'Video',
                    subtitle: 'Video lớn sẽ được tải tiếp tục theo từng phần',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPickAttachment(
                        MessageAttachmentPickSource.video,
                      );
                    },
                  ),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.mic,
                    title: 'Ghi âm voice',
                    subtitle:
                        'Thu âm một đoạn thoại rồi gửi vào cuộc trò chuyện',
                    onTap: () {
                      Navigator.of(context).pop();
                      _startVoiceRecording();
                    },
                  ),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.smiley,
                    title: 'Biểu tượng cảm xúc',
                    subtitle: 'Mở bảng emoji để chèn vào tin nhắn',
                    onTap: () {
                      Navigator.of(context).pop();
                      _toggleEmojiTray();
                    },
                  ),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.doc,
                    title: 'Tệp',
                    subtitle: 'Gửi PDF, Office, ZIP, âm thanh hoặc video',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPickAttachment(MessageAttachmentPickSource.file);
                    },
                  ),
                  _AttachmentSourceTile(
                    icon: CupertinoIcons.chart_bar_alt_fill,
                    title: 'Tạo bình chọn',
                    subtitle: 'Lấy ý kiến của các thành viên trong phòng',
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onCreatePoll();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggleEmojiTray() {
    setState(() => _showEmojiTray = !_showEmojiTray);
    widget.focusNode.requestFocus();
  }

  void _focusInput() {
    if (_showEmojiTray) {
      setState(() => _showEmojiTray = false);
    }
    widget.focusNode.requestFocus();
  }

  void _send() {
    setState(() => _showEmojiTray = false);
    widget.onSend(_silent);
    if (_silent) setState(() => _silent = false);
    widget.focusNode.requestFocus();
  }

  void _startVoiceRecording() {
    setState(() => _showEmojiTray = false);
    widget.focusNode.unfocus();
    widget.onStartVoiceRecording();
  }

  void _startVoiceTicker() {
    _voiceTicker?.cancel();
    _updateVoiceElapsed();
    _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateVoiceElapsed();
      }
    });
  }

  void _stopVoiceTicker() {
    _voiceTicker?.cancel();
    _voiceTicker = null;
    if (mounted) {
      setState(() => _voiceElapsed = Duration.zero);
    }
  }

  void _updateVoiceElapsed() {
    final startedAt = widget.voiceRecordingStartedAt;
    if (startedAt == null) {
      return;
    }
    setState(() => _voiceElapsed = DateTime.now().difference(startedAt));
  }

  void _insertEmoji(String emoji) {
    final selection = widget.controller.selection;
    final start = selection.isValid
        ? selection.start
        : widget.controller.text.length;
    final end = selection.isValid
        ? selection.end
        : widget.controller.text.length;
    final controller = widget.controller;
    final onChanged = widget.onChanged;
    if (emoji.isNotEmpty) {
      final updated = controller.text.replaceRange(start, end, emoji);
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: start + emoji.length),
      );
      onChanged(updated);
      widget.focusNode.requestFocus();
      return;
    }
    final updated = controller.text.replaceRange(start, end, '🙂');
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + 2),
    );
    onChanged(updated);
  }
}

class _PermissionRationaleTile extends StatelessWidget {
  const _PermissionRationaleTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.sm,
        0,
        WebTuiSpacing.sm,
        WebTuiSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.primarySoft,
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.lock_shield,
                size: 20,
                color: WebTuiColors.primary,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Text(
                  'Ứng dụng chỉ dùng camera/ảnh để gửi file vào cuộc trò chuyện. Có thể cấp lại quyền trong Settings nếu đã từ chối.',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentSourceTile extends StatelessWidget {
  const _AttachmentSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: enabled
            ? WebTuiColors.primarySoft
            : WebTuiColors.backgroundMuted,
        child: Icon(
          icon,
          color: enabled ? WebTuiColors.primary : WebTuiColors.textMuted,
        ),
      ),
      title: Text(
        title,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: enabled ? WebTuiColors.textPrimary : WebTuiColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: WebTuiTypography.bodySmall.copyWith(
          color: WebTuiColors.textSecondary,
        ),
      ),
    );
  }
}

class _VoiceRecordingBar extends StatelessWidget {
  const _VoiceRecordingBar({
    required this.elapsed,
    required this.onCancel,
    required this.onStop,
  });

  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        border: Border.all(color: WebTuiColors.danger.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.sm,
          vertical: WebTuiSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.mic_fill,
              size: 18,
              color: WebTuiColors.danger,
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                'Đang ghi âm ${_formatVoiceDuration(elapsed)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Hủy ghi âm',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
            FilledButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Dừng'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentQueuePreview extends StatelessWidget {
  const _AttachmentQueuePreview({
    required this.attachments,
    required this.onRetry,
    required this.onRemove,
  });

  final List<MessageAttachmentUploadItem> attachments;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: WebTuiSpacing.sm),
          itemBuilder: (context, index) {
            final item = attachments[index];
            final name = item.uploadedFile?.name ?? item.picked?.fileName ?? '';
            final size = item.uploadedFile?.byteSize ?? item.picked?.byteSize;
            final failed = item.status == MessageAttachmentUploadStatus.failed;
            final uploading =
                item.status == MessageAttachmentUploadStatus.uploading;
            return Container(
              width: 220,
              padding: const EdgeInsets.all(WebTuiSpacing.sm),
              decoration: BoxDecoration(
                color: WebTuiColors.backgroundMuted,
                borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                border: Border.all(
                  color: failed
                      ? WebTuiColors.danger.withValues(alpha: 0.45)
                      : WebTuiColors.border,
                ),
              ),
              child: Row(
                children: [
                  _PendingAttachmentPreview(item: item, failed: failed),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Attachment' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            if (size != null) _formatBytes(size),
                            _attachmentUploadLabel(item.status),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: failed
                                ? WebTuiColors.danger
                                : WebTuiColors.textMuted,
                          ),
                        ),
                        if (uploading)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: LinearProgressIndicator(
                              value: item.progress <= 0 ? null : item.progress,
                              minHeight: 3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (failed)
                    IconButton(
                      tooltip: 'Thử lại',
                      onPressed: () => onRetry(item.clientAttachmentId),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    )
                  else
                    IconButton(
                      tooltip: 'Gỡ',
                      onPressed: () => onRemove(item.clientAttachmentId),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({required this.item, required this.failed});

  final MessageAttachmentUploadItem item;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final picked = item.picked;
    if (picked?.kind == MessageAttachmentKind.image &&
        picked!.path.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: Image.file(
          File(picked.path),
          width: 54,
          height: 54,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return SizedBox.square(
      dimension: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: failed
              ? WebTuiColors.danger.withValues(alpha: 0.1)
              : WebTuiColors.primarySoft,
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
        ),
        child: Icon(
          _attachmentUploadIcon(item),
          color: failed ? WebTuiColors.danger : WebTuiColors.primary,
        ),
      ),
    );
  }
}

class _EmojiTray extends StatelessWidget {
  const _EmojiTray({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _emojis = [
    '\u{1F600}',
    '\u{1F602}',
    '\u{1F60D}',
    '\u{1F44D}',
    '\u{2764}\u{FE0F}',
    '\u{1F64F}',
    '\u{1F389}',
    '\u{1F525}',
    '\u{1F44F}',
    '\u{1F914}',
    '\u{1F622}',
    '\u{1F60E}',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        itemCount: _emojis.length,
        separatorBuilder: (_, _) => const SizedBox(width: WebTuiSpacing.xs),
        itemBuilder: (context, index) {
          final emoji = _emojis[index];
          return Material(
            color: WebTuiColors.surfaceElevated,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelected(emoji),
              child: SizedBox.square(
                dimension: 38,
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ComposerContextBanner extends StatelessWidget {
  const _ComposerContextBanner({
    required this.label,
    required this.preview,
    required this.onCancel,
  });

  final String label;
  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.primarySoft,
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.md,
            vertical: WebTuiSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.reply_rounded,
                size: 18,
                color: WebTuiColors.primary,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hủy',
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _createMessageReminder(
  BuildContext context, {
  required String workspaceId,
  required String channelId,
  required ChatMessage message,
}) async {
  try {
    await ProviderScope.containerOf(context)
        .read(conversationRemoteDataSourceProvider)
        .createMessageReminder(
          workspaceId: workspaceId,
          channelId: channelId,
          messageId: message.id,
          remindAt: DateTime.now().add(const Duration(hours: 1)),
          note: _displayMessageBody(message),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sẽ nhắc lại tin nhắn sau 1 giờ.')),
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

Future<void> _showMessageActions(
  BuildContext context, {
  required String workspaceId,
  required String currentChannelId,
  required ChatMessage message,
  required ValueChanged<ChatMessage> onReply,
  required ValueChanged<ChatMessage> onReplyPrivately,
  required bool isSenderBlocked,
  required bool sharedContentBlocked,
  required ValueChanged<ChatMessage> onReportMessage,
  required ValueChanged<ChatMessage> onReportUser,
  required ValueChanged<ChatMessage> onToggleBlockUser,
  required ValueChanged<ChatMessage> onConvertToTask,
  required ValueChanged<ChatMessage> onEdit,
  required ValueChanged<ChatMessage> onDelete,
  required void Function(ChatMessage message, String emoji) onReact,
  required ValueChanged<ChatMessage> onPin,
  required ValueChanged<ChatMessage> onThread,
  required void Function(ChatMessage message, String targetChannelId) onForward,
}) {
  if (message.isDeleted) {
    return Future.value();
  }
  final hostContext = context;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: WebTuiColors.surface,
    builder: (sheetContext) {
      return _MessageQuickActions(
        hostContext: hostContext,
        workspaceId: workspaceId,
        currentChannelId: currentChannelId,
        message: message,
        onReply: onReply,
        onReplyPrivately: onReplyPrivately,
        isSenderBlocked: isSenderBlocked,
        sharedContentBlocked: sharedContentBlocked,
        onReportMessage: onReportMessage,
        onReportUser: onReportUser,
        onToggleBlockUser: onToggleBlockUser,
        onConvertToTask: onConvertToTask,
        onEdit: onEdit,
        onDelete: onDelete,
        onReact: onReact,
        onPin: onPin,
        onThread: onThread,
        onForward: onForward,
      );
    },
  );
}

class _MessageQuickActions extends StatelessWidget {
  const _MessageQuickActions({
    required this.hostContext,
    required this.workspaceId,
    required this.currentChannelId,
    required this.message,
    required this.onReply,
    required this.onReplyPrivately,
    required this.isSenderBlocked,
    required this.sharedContentBlocked,
    required this.onReportMessage,
    required this.onReportUser,
    required this.onToggleBlockUser,
    required this.onConvertToTask,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onPin,
    required this.onThread,
    required this.onForward,
  });

  final BuildContext hostContext;
  final String workspaceId;
  final String currentChannelId;
  final ChatMessage message;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onReplyPrivately;
  final bool isSenderBlocked;
  final bool sharedContentBlocked;
  final ValueChanged<ChatMessage> onReportMessage;
  final ValueChanged<ChatMessage> onReportUser;
  final ValueChanged<ChatMessage> onToggleBlockUser;
  final ValueChanged<ChatMessage> onConvertToTask;
  final ValueChanged<ChatMessage> onEdit;
  final ValueChanged<ChatMessage> onDelete;
  final void Function(ChatMessage message, String emoji) onReact;
  final ValueChanged<ChatMessage> onPin;
  final ValueChanged<ChatMessage> onThread;
  final void Function(ChatMessage message, String targetChannelId) onForward;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.xs,
          WebTuiSpacing.lg,
          WebTuiSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thao tác tin nhắn',
              style: WebTuiTypography.titleMedium.copyWith(
                color: WebTuiColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              _displayMessageBody(message),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.sm,
              children: [
                _SheetActionButton(
                  label: 'Trả lời',
                  icon: Icons.reply_rounded,
                  onPressed: () => _closeThen(context, () => onReply(message)),
                ),
                if (!sharedContentBlocked &&
                    !message.isMine &&
                    message.senderId?.isNotEmpty == true)
                  _SheetActionButton(
                    label: 'Trả lời riêng',
                    icon: Icons.lock_person_outlined,
                    onPressed: () =>
                        _closeThen(context, () => onReplyPrivately(message)),
                  ),
                if (shouldOfferMessageReport(message))
                  _SheetActionButton(
                    label: 'Báo cáo tin nhắn',
                    icon: Icons.flag_outlined,
                    danger: true,
                    onPressed: () =>
                        _closeThen(context, () => onReportMessage(message)),
                  ),
                if (!message.isMine &&
                    message.senderId?.isNotEmpty == true) ...[
                  _SheetActionButton(
                    label: 'Báo cáo người gửi',
                    icon: Icons.person_off_outlined,
                    danger: true,
                    onPressed: () =>
                        _closeThen(context, () => onReportUser(message)),
                  ),
                  _SheetActionButton(
                    label: isSenderBlocked ? 'Bỏ chặn' : 'Chặn người dùng',
                    icon: isSenderBlocked
                        ? Icons.person_add_alt_1
                        : Icons.block_rounded,
                    danger: !isSenderBlocked,
                    onPressed: () =>
                        _closeThen(context, () => onToggleBlockUser(message)),
                  ),
                ],
                if (!sharedContentBlocked)
                  _SheetActionButton(
                    label: 'Tạo task',
                    icon: Icons.task_alt_rounded,
                    onPressed: () =>
                        _closeThen(context, () => onConvertToTask(message)),
                  ),
                _SheetActionButton(
                  label: 'Nhắc sau 1 giờ',
                  icon: Icons.alarm_add_outlined,
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(
                      _createMessageReminder(
                        hostContext,
                        workspaceId: workspaceId,
                        channelId: currentChannelId,
                        message: message,
                      ),
                    );
                  },
                ),
                if (!sharedContentBlocked) ...[
                  _SheetActionButton(
                    label: 'Reaction',
                    icon: Icons.thumb_up_alt_outlined,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showReactionPicker(hostContext);
                    },
                  ),
                  _SheetActionButton(
                    label: message.isPinned ? 'Bỏ ghim' : 'Ghim',
                    icon: message.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    onPressed: () => _closeThen(context, () => onPin(message)),
                  ),
                ],
                _SheetActionButton(
                  label: 'Thread',
                  icon: Icons.forum_outlined,
                  onPressed: () => _closeThen(context, () => onThread(message)),
                ),
                if (!sharedContentBlocked)
                  _SheetActionButton(
                    label: 'Chuyển tiếp',
                    icon: Icons.shortcut_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showForwardDialog(hostContext);
                    },
                  ),
                if (message.isMine) ...[
                  if (!sharedContentBlocked)
                    _SheetActionButton(
                      label: 'Sửa',
                      icon: Icons.edit_rounded,
                      onPressed: () =>
                          _closeThen(context, () => onEdit(message)),
                    ),
                  _SheetActionButton(
                    label: 'Thu hồi',
                    icon: Icons.delete_outline_rounded,
                    danger: true,
                    onPressed: () =>
                        _closeThen(context, () => onDelete(message)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Future<void> _showReactionPicker(BuildContext context) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: WebTuiColors.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              WebTuiSpacing.lg,
            ),
            child: _ReactionPicker(
              selectedEmojis: message.reactions
                  .where((reaction) => reaction.reactedByMe)
                  .map((reaction) => reaction.emoji)
                  .toSet(),
              onSelected: (emoji) => Navigator.of(context).pop(emoji),
            ),
          ),
        );
      },
    );
    if (emoji != null && emoji.trim().isNotEmpty) {
      onReact(message, emoji);
    }
  }

  Future<void> _showForwardDialog(BuildContext context) async {
    final targetChannelId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: WebTuiColors.surface,
      builder: (context) {
        return _ForwardChannelPicker(
          workspaceId: workspaceId,
          currentChannelId: currentChannelId,
        );
      },
    );
    final normalized = targetChannelId?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      onForward(message, normalized);
    }
  }
}

class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({
    required this.selectedEmojis,
    required this.onSelected,
  });

  final Set<String> selectedEmojis;
  final ValueChanged<String> onSelected;

  static const _emojis = [
    '\u{1F44D}',
    '\u{2764}\u{FE0F}',
    '\u{1F602}',
    '\u{1F525}',
    '\u{1F389}',
    '\u{1F44F}',
    '\u{1F60D}',
    '\u{1F914}',
    '\u{1F622}',
    '\u{1F64F}',
    '\u{1F4AF}',
    '\u{1F680}',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chọn reaction',
          style: WebTuiTypography.titleMedium.copyWith(
            color: WebTuiColors.textPrimary,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: WebTuiSpacing.sm,
            crossAxisSpacing: WebTuiSpacing.sm,
          ),
          itemCount: _emojis.length,
          itemBuilder: (context, index) {
            final emoji = _emojis[index];
            final selected = selectedEmojis.contains(emoji);
            return Material(
              color: selected ? WebTuiColors.primarySoft : WebTuiColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WebTuiRadii.md),
                side: BorderSide(
                  color: selected ? WebTuiColors.primary : WebTuiColors.border,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(WebTuiRadii.md),
                onTap: () => onSelected(emoji),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ForwardChannelPicker extends ConsumerWidget {
  const _ForwardChannelPicker({
    required this.workspaceId,
    required this.currentChannelId,
  });

  final String workspaceId;
  final String currentChannelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncChannels = ref.watch(_forwardChannelsProvider(workspaceId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.sm,
          WebTuiSpacing.lg,
          WebTuiSpacing.lg,
        ),
        child: asyncChannels.when(
          loading: () => const SizedBox(
            height: 180,
            child: WebTuiLoadingState(message: 'Đang tải kênh...'),
          ),
          error: (_, _) => SizedBox(
            height: 180,
            child: WebTuiErrorState(
              title: 'Không tải được kênh',
              message: 'Thử mở lại bảng chuyển tiếp sau vài giây.',
              onRetry: () =>
                  ref.invalidate(_forwardChannelsProvider(workspaceId)),
            ),
          ),
          data: (channels) {
            final targets = channels
                .where(
                  (channel) =>
                      channel.channelId != currentChannelId &&
                      channel.isMember &&
                      !channel.privateSessionMode,
                )
                .toList(growable: false);
            if (targets.isEmpty) {
              return const SizedBox(
                height: 180,
                child: WebTuiEmptyState(
                  title: 'Chưa có kênh để chuyển tiếp',
                  message: 'Bạn cần là thành viên của kênh khác trước.',
                  icon: Icons.shortcut_rounded,
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chuyển tiếp đến',
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: targets.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: WebTuiSpacing.xs),
                    itemBuilder: (context, index) {
                      final channel = targets[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(WebTuiRadii.md),
                        ),
                        leading: WebTuiAvatar(
                          label: channel.avatarLabel ?? channel.title,
                          imageUrl: channel.avatarUrl,
                          size: 34,
                        ),
                        title: Text(
                          channel.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          channel.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () =>
                            Navigator.of(context).pop(channel.channelId),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? WebTuiColors.danger : WebTuiColors.textPrimary;
    return Material(
      color: danger
          ? WebTuiColors.danger.withValues(alpha: 0.08)
          : WebTuiColors.backgroundMuted,
      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.md,
            vertical: WebTuiSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: WebTuiSpacing.xs),
              Text(
                label,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.title,
    required this.showAvatar,
    required this.outgoing,
    required this.text,
    required this.timeLabel,
    required this.reactions,
    required this.onReact,
    required this.onRetryAudioCall,
  });

  final ChatMessage message;
  final String title;
  final bool showAvatar;
  final bool outgoing;
  final String text;
  final String timeLabel;
  final List<String> reactions;
  final ValueChanged<String> onReact;
  final VoidCallback onRetryAudioCall;

  @override
  Widget build(BuildContext context) {
    final showBody = text.trim().isNotEmpty || message.isDeleted;
    if (_isMissedCallMessage(message)) {
      return _MissedCallCard(
        outgoing: outgoing,
        title: _missedCallTitle(message),
        timeLabel: timeLabel,
        onRetry: onRetryAudioCall,
      );
    }
    final poll = _pollDefinition(message);
    if (poll != null) {
      final card = _PollMessageCard(
        message: message,
        poll: poll,
        onVote: (reaction) {
          final selected = message.reactions
              .where((item) => item.reactedByMe)
              .toList(growable: false);
          if (!poll.multiple &&
              !selected.any((item) => item.emoji == reaction)) {
            for (final previous in selected) {
              if (poll.options.any(
                (option) => option.reaction == previous.emoji,
              )) {
                onReact(previous.emoji);
              }
            }
          }
          onReact(reaction);
        },
      );
      if (outgoing) {
        return Align(alignment: Alignment.centerRight, child: card);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox.square(
            dimension: 30,
            child: showAvatar
                ? WebTuiAvatar(label: title, size: 30)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Flexible(child: card),
        ],
      );
    }
    if (outgoing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showBody)
            WebTuiMessageBubble(
              text: text,
              textSpan: message.isDeleted
                  ? null
                  : _messageTextSpan(message, true),
              timeLabel: timeLabel,
              outgoing: true,
              statusLabel: _deliveryStatusLabel(message),
              reactions: reactions,
            ),
          if (message.attachments.isNotEmpty)
            _MessageAttachmentList(
              attachments: message.attachments,
              outgoing: true,
            ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox.square(
          dimension: 30,
          child: showAvatar
              ? WebTuiAvatar(label: title, size: 30)
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: WebTuiSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBody)
                WebTuiMessageBubble(
                  text: text,
                  textSpan: message.isDeleted
                      ? null
                      : _messageTextSpan(message, false),
                  timeLabel: timeLabel,
                  reactions: reactions,
                ),
              if (message.attachments.isNotEmpty)
                _MessageAttachmentList(
                  attachments: message.attachments,
                  outgoing: false,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _deliveryStatusLabel(ChatMessage message) {
  return switch (message.deliveryStatus) {
    'queued' => 'Đang chờ gửi',
    'sending' => 'Đang gửi',
    'failed' => 'Chưa gửi được',
    _ => 'Đã gửi',
  };
}

final class _PollDraft {
  const _PollDraft({
    required this.question,
    required this.options,
    required this.multiple,
    required this.anonymous,
  });

  final String question;
  final List<String> options;
  final bool multiple;
  final bool anonymous;
}

class _PollComposerDialog extends StatefulWidget {
  const _PollComposerDialog();

  @override
  State<_PollComposerDialog> createState() => _PollComposerDialogState();
}

class _PollComposerDialogState extends State<_PollComposerDialog> {
  final _questionController = TextEditingController();
  final _optionControllers = [TextEditingController(), TextEditingController()];
  bool _multiple = false;
  bool _anonymous = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);
    final canSubmit =
        _questionController.text.trim().isNotEmpty && options.length >= 2;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.poll_outlined, color: WebTuiColors.primary),
          SizedBox(width: WebTuiSpacing.sm),
          Text('Tạo bình chọn'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _questionController,
                autofocus: true,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Câu hỏi',
                  hintText: 'Ví dụ: Chọn lịch họp tuần này?',
                ),
              ),
              const SizedBox(height: WebTuiSpacing.sm),
              for (var index = 0; index < _optionControllers.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                  child: TextField(
                    controller: _optionControllers[index],
                    maxLength: 200,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: 'Lựa chọn ${index + 1}',
                      suffixIcon: _optionControllers.length > 2
                          ? IconButton(
                              tooltip: 'Xóa lựa chọn',
                              onPressed: () {
                                final removed = _optionControllers.removeAt(
                                  index,
                                );
                                removed.dispose();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                  ),
                ),
              if (_optionControllers.length < 10)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _optionControllers.add(TextEditingController()),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Thêm lựa chọn'),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cho phép chọn nhiều đáp án'),
                value: _multiple,
                onChanged: (value) => setState(() => _multiple = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ẩn danh người bình chọn'),
                value: _anonymous,
                onChanged: (value) => setState(() => _anonymous = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(
                  _PollDraft(
                    question: _questionController.text.trim(),
                    options: options,
                    multiple: _multiple,
                    anonymous: _anonymous,
                  ),
                )
              : null,
          child: const Text('Tạo bình chọn'),
        ),
      ],
    );
  }
}

final class _PollDefinition {
  const _PollDefinition({
    required this.question,
    required this.options,
    required this.multiple,
    this.anonymous = false,
    this.closesAt,
  });

  final String question;
  final List<_PollOption> options;
  final bool multiple;
  final bool anonymous;
  final DateTime? closesAt;
}

final class _PollOption {
  const _PollOption({
    required this.id,
    required this.label,
    required this.reaction,
  });

  final String id;
  final String label;
  final String reaction;
}

class _PollMessageCard extends StatelessWidget {
  const _PollMessageCard({
    required this.message,
    required this.poll,
    required this.onVote,
  });

  final ChatMessage message;
  final _PollDefinition poll;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final reactionByEmoji = {
      for (final reaction in message.reactions) reaction.emoji: reaction,
    };
    final totalVotes = poll.options.fold<int>(
      0,
      (total, option) => total + (reactionByEmoji[option.reaction]?.count ?? 0),
    );
    final closed =
        poll.closesAt != null &&
        !poll.closesAt!.isAfter(DateTime.now().toUtc());

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330, minWidth: 250),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: message.isMine
              ? WebTuiColors.messageOutgoing
              : WebTuiColors.surface,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          border: Border.all(
            color: message.isMine
                ? WebTuiColors.messageOutgoingBorder
                : WebTuiColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: WebTuiColors.textPrimary.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: WebTuiColors.primarySoft,
                      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.poll_outlined,
                        color: WebTuiColors.primary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BÌNH CHỌN',
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: WebTuiColors.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          poll.question,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WebTuiSpacing.md),
              ...poll.options.map((option) {
                final reaction = reactionByEmoji[option.reaction];
                final count = reaction?.count ?? 0;
                final percentage = totalVotes == 0
                    ? 0
                    : ((count / totalVotes) * 100).round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(WebTuiRadii.md),
                      onTap: closed ? null : () => onVote(option.reaction),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: WebTuiColors.background,
                          borderRadius: BorderRadius.circular(WebTuiRadii.md),
                          border: Border.all(
                            color: reaction?.reactedByMe == true
                                ? WebTuiColors.primary
                                : WebTuiColors.border,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: percentage / 100,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: WebTuiColors.primarySoft,
                                    borderRadius: BorderRadius.circular(
                                      WebTuiRadii.md,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: WebTuiSpacing.sm,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    option.reaction,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(width: WebTuiSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      style: WebTuiTypography.bodySmall
                                          .copyWith(
                                            color: WebTuiColors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '$count · $percentage%',
                                    style: WebTuiTypography.labelSmall.copyWith(
                                      color: WebTuiColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              Wrap(
                spacing: WebTuiSpacing.sm,
                runSpacing: WebTuiSpacing.xs,
                children: [
                  Text(
                    '$totalVotes lượt chọn',
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                  Text(
                    poll.multiple ? 'Chọn nhiều đáp án' : 'Chọn một đáp án',
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                  if (poll.anonymous)
                    Text(
                      'Ẩn danh',
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textSecondary,
                      ),
                    ),
                  if (closed)
                    Text(
                      'Đã đóng',
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.danger,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

_PollDefinition? _pollDefinition(ChatMessage message) {
  if (!message.isPoll) {
    return null;
  }
  final rawPoll = message.metadata['poll'];
  if (rawPoll is! Map) {
    return null;
  }
  final poll = Map<String, Object?>.from(rawPoll);
  final rawOptions = poll['options'];
  if (rawOptions is! List) {
    return null;
  }
  final options = rawOptions
      .whereType<Map>()
      .map((rawOption) {
        final option = Map<String, Object?>.from(rawOption);
        final id = option['id']?.toString().trim() ?? '';
        final label = option['label']?.toString().trim() ?? '';
        final reaction = option['reaction']?.toString().trim() ?? '';
        if (id.isEmpty || label.isEmpty || reaction.isEmpty) {
          return null;
        }
        return _PollOption(id: id, label: label, reaction: reaction);
      })
      .whereType<_PollOption>()
      .toList(growable: false);
  if (options.length < 2) {
    return null;
  }
  final closesAtValue = poll['closes_at']?.toString();
  return _PollDefinition(
    question: poll['question']?.toString().trim().isNotEmpty == true
        ? poll['question']!.toString().trim()
        : message.body,
    options: options,
    multiple: poll['multiple'] == true,
    anonymous: poll['anonymous'] == true,
    closesAt: closesAtValue == null
        ? null
        : DateTime.tryParse(closesAtValue)?.toUtc(),
  );
}

class _MissedCallCard extends StatelessWidget {
  const _MissedCallCard({
    required this.outgoing,
    required this.title,
    required this.timeLabel,
    required this.onRetry,
  });

  final bool outgoing;
  final String title;
  final String timeLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final background = outgoing
        ? WebTuiColors.messageOutgoing
        : WebTuiColors.messageIncoming;
    final borderColor = outgoing
        ? WebTuiColors.messageOutgoingBorder
        : WebTuiColors.border;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 148, maxWidth: 174),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: WebTuiColors.textPrimary.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodySmall.copyWith(
                              color: WebTuiColors.danger,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phone_missed_rounded,
                                size: 18,
                                color: WebTuiColors.danger,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'Cuộc gọi thoại',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.bodySmall.copyWith(
                                    color: WebTuiColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: borderColor),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onRetry,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Center(
                            child: Text(
                              'Gọi lại',
                              style: WebTuiTypography.bodySmall.copyWith(
                                color: WebTuiColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              timeLabel,
              style: WebTuiTypography.labelSmall.copyWith(
                color: WebTuiColors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAttachmentList extends StatelessWidget {
  const _MessageAttachmentList({
    required this.attachments,
    required this.outgoing,
  });

  final List<MessageAttachment> attachments;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final displayedAttachments = boundedMessageAttachments(attachments);
    final networkScope = WebTuiAvatarNetworkScope.maybeOf(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final singleImageMaxWidth = (viewportWidth * 0.66).clamp(188, 258);
    final singleImageMaxHeight = (viewportWidth * 0.72).clamp(188, 286);
    final imageGridMaxWidth = (viewportWidth * 0.62).clamp(188, 230);
    final imageTileSize = ((imageGridMaxWidth - 4) / 2).clamp(92, 112);
    final images = boundedEagerImageAttachments(displayedAttachments);
    final overflowImages = displayedAttachments
        .where((attachment) => attachment.isImage)
        .skip(images.length);
    final otherAttachments = <MessageAttachment>[
      ...displayedAttachments.where((attachment) => !attachment.isImage),
      ...overflowImages,
    ];
    final hiddenAttachmentCount =
        attachments.length - displayedAttachments.length;
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
      child: Column(
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (images.length == 1)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: MessageImageAttachmentView(
                attachment: images.first,
                apiBaseUri: networkScope?.apiBaseUri,
                fit: BoxFit.contain,
                maxHeight: singleImageMaxHeight.toDouble(),
                maxWidth: singleImageMaxWidth.toDouble(),
                onPressed: () => openMessageImageGallery(
                  context,
                  attachments: images,
                  initialIndex: 0,
                  apiBaseUri: networkScope?.apiBaseUri,
                ),
              ),
            ),
          if (images.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: imageGridMaxWidth.toDouble(),
                ),
                child: Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (var index = 0; index < images.length; index++)
                      MessageImageAttachmentView(
                        attachment: images[index],
                        apiBaseUri: networkScope?.apiBaseUri,
                        height: imageTileSize.toDouble(),
                        maxHeight: imageTileSize.toDouble(),
                        maxWidth: imageTileSize.toDouble(),
                        onPressed: () => openMessageImageGallery(
                          context,
                          attachments: images,
                          initialIndex: index,
                          apiBaseUri: networkScope?.apiBaseUri,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          for (final attachment in otherAttachments)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: attachment.isImage
                  ? MessageFileAttachmentView(
                      attachment: attachment,
                      outgoing: outgoing,
                      apiBaseUri: networkScope?.apiBaseUri,
                    )
                  : attachment.isAudio
                  ? MessageVoiceAttachmentView(
                      attachment: attachment,
                      apiBaseUri: networkScope?.apiBaseUri,
                    )
                  : attachment.isVideo
                  ? MessageVideoAttachmentView(
                      attachment: attachment,
                      apiBaseUri: networkScope?.apiBaseUri,
                    )
                  : MessageFileAttachmentView(
                      attachment: attachment,
                      outgoing: outgoing,
                      apiBaseUri: networkScope?.apiBaseUri,
                    ),
            ),
          if (hiddenAttachmentCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                'Còn $hiddenAttachmentCount tệp chưa hiển thị',
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const int maxRenderedAttachmentsPerMessage = 20;
const int maxEagerImagePreviewsPerMessage = 4;

List<MessageAttachment> boundedMessageAttachments(
  List<MessageAttachment> attachments,
) {
  if (attachments.length <= maxRenderedAttachmentsPerMessage) {
    return attachments;
  }
  return attachments
      .take(maxRenderedAttachmentsPerMessage)
      .toList(growable: false);
}

List<MessageAttachment> boundedEagerImageAttachments(
  List<MessageAttachment> attachments,
) {
  return attachments
      .where((attachment) => attachment.isImage)
      .take(maxEagerImagePreviewsPerMessage)
      .toList(growable: false);
}

class _EmbeddedChatHeader extends StatelessWidget {
  const _EmbeddedChatHeader({
    required this.title,
    required this.onDetails,
    this.avatarUrl,
    this.onSafety,
  });

  final String title;
  final VoidCallback onDetails;
  final String? avatarUrl;
  final VoidCallback? onSafety;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.surface,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
          child: Row(
            children: [
              WebTuiAvatar(label: title, imageUrl: avatarUrl, size: 36),
              const SizedBox(width: WebTuiSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.titleMedium,
                    ),
                    Text(
                      'Đang hoạt động',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.accentGreen,
                      ),
                    ),
                  ],
                ),
              ),
              if (onSafety != null)
                IconButton(
                  tooltip: 'Báo cáo hoặc chặn người dùng',
                  onPressed: onSafety,
                  icon: const Icon(Icons.shield_outlined),
                ),
              IconButton(
                tooltip: 'Chi tiết kênh',
                onPressed: onDetails,
                icon: const Icon(CupertinoIcons.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedMessagePlaceholder extends StatelessWidget {
  const _BlockedMessagePlaceholder({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Tin nhắn từ người dùng đã chặn đang được ẩn',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          border: Border.all(color: WebTuiColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.md,
            vertical: WebTuiSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.visibility_off_outlined,
                size: 18,
                color: WebTuiColors.textMuted,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              const Expanded(
                child: Text('Tin nhắn từ người dùng đã chặn đã được ẩn.'),
              ),
              TextButton(onPressed: onManage, child: const Text('Quản lý')),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedConversationComposer extends StatelessWidget {
  const _BlockedConversationComposer({this.onManage});

  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
          ),
          child: Row(
            children: [
              const Icon(Icons.block_rounded, color: WebTuiColors.textMuted),
              const SizedBox(width: WebTuiSpacing.sm),
              const Expanded(
                child: Text(
                  'Bạn đã chặn người dùng này. Bỏ chặn để nhắn tin hoặc gọi.',
                ),
              ),
              TextButton(onPressed: onManage, child: const Text('Quản lý')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: WebTuiColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: WebTuiColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              'Bắt đầu cuộc trò chuyện',
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleMedium.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              'Tin nhắn đầu tiên của bạn sẽ xuất hiện tại đây.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(WebTuiRadii.sm),
          border: Border.all(color: WebTuiColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.sm,
            vertical: WebTuiSpacing.xs,
          ),
          child: Text(
            _dateLabel(date),
            style: WebTuiTypography.labelSmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.xxl),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.danger.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.lg,
          vertical: WebTuiSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: WebTuiColors.danger,
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _messageTimeLabel(ChatMessage message) {
  return switch (message.deliveryStatus) {
    'failed' => 'Chưa gửi',
    'queued' || 'sending' => 'Đang gửi',
    _ => _timeLabel(message.createdAt),
  };
}

bool _sameDay(DateTime left, DateTime right) {
  final a = left.toLocal();
  final b = right.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateLabel(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (_sameDay(local, now)) {
    return 'Hôm nay';
  }
  if (_sameDay(local, now.subtract(const Duration(days: 1)))) {
    return 'Hôm qua';
  }
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _displayMessageBody(ChatMessage message) {
  if (message.isDeleted) {
    return 'Tin nhắn đã được thu hồi';
  }
  if (_isMissedCallMessage(message)) {
    return '';
  }
  if (_isGeneratedAttachmentBody(message.body, message.attachments)) {
    return '';
  }
  return message.body;
}

bool _isMissedCallMessage(ChatMessage message) {
  if (message.isDeleted || message.attachments.isNotEmpty) {
    return false;
  }
  final normalized = _removeVietnameseDiacritics(
    _compactMessageText(message.body),
  );
  return normalized == 'cuoc goi nho' ||
      normalized == 'ban bi nho' ||
      normalized == 'missed call' ||
      normalized.contains('ban bi nho') ||
      (normalized.contains('cuoc goi') && normalized.contains('nho'));
}

String _missedCallTitle(ChatMessage message) {
  final normalized = _removeVietnameseDiacritics(
    _compactMessageText(message.body),
  );
  if (normalized.contains('ban bi nho')) {
    return 'Bạn bị nhỡ';
  }
  return 'Cuộc gọi nhỡ';
}

bool _isGeneratedAttachmentBody(
  String body,
  List<MessageAttachment> attachments,
) {
  if (attachments.isEmpty) {
    return false;
  }
  final normalized = _compactMessageText(body);
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized == 'đã gửi tệp đính kèm' ||
      _sameTextWithoutVietnameseDiacritics(normalized, 'đã gửi tệp đính kèm')) {
    return true;
  }

  final hasOnlyImages = attachments.every((attachment) => attachment.isImage);
  final hasOnlyAudio = attachments.every((attachment) => attachment.isAudio);
  if (hasOnlyImages &&
      _matchesGeneratedAttachmentText(normalized, noun: 'ảnh')) {
    return true;
  }
  if (hasOnlyAudio &&
      _matchesGeneratedAttachmentText(normalized, noun: 'tin nhắn thoại')) {
    return true;
  }
  if (attachments.length == 1) {
    final fileName = _compactMessageText(attachments.first.file.name);
    return normalized == 'đã gửi file $fileName' ||
        _sameTextWithoutVietnameseDiacritics(
          normalized,
          'đã gửi file $fileName',
        ) ||
        (hasOnlyImages && normalized == fileName);
  }
  return normalized == 'đã gửi ${attachments.length} file' ||
      _sameTextWithoutVietnameseDiacritics(
        normalized,
        'đã gửi ${attachments.length} file',
      );
}

String _compactMessageText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool _matchesGeneratedAttachmentText(String value, {required String noun}) {
  final normalized = _removeVietnameseDiacritics(value);
  final sent = _removeVietnameseDiacritics('đã gửi');
  final normalizedNoun = _removeVietnameseDiacritics(noun);
  return RegExp(
    '^${RegExp.escape(sent)}(?: \\d+)? ${RegExp.escape(normalizedNoun)}\$',
  ).hasMatch(normalized);
}

bool _sameTextWithoutVietnameseDiacritics(String left, String right) {
  return _removeVietnameseDiacritics(left) ==
      _removeVietnameseDiacritics(right);
}

String _removeVietnameseDiacritics(String value) {
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
    'e': 'èéẹẻẽêềếệểễ',
    'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
    'i': 'ìíịỉĩ',
    'I': 'ÌÍỊỈĨ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
    'u': 'ùúụủũưừứựửữ',
    'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
    'y': 'ỳýỵỷỹ',
    'Y': 'ỲÝỴỶỸ',
    'd': 'đ',
    'D': 'Đ',
  };
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    var replacement = char;
    for (final entry in groups.entries) {
      if (entry.value.contains(char)) {
        replacement = entry.key;
        break;
      }
    }
    buffer.write(replacement);
  }
  return buffer.toString();
}

String _messageSemanticLabel(
  ChatMessage message,
  String text,
  String timeLabel,
) {
  final sender = message.isMine ? 'Bạn' : 'Người gửi';
  final body = text.trim().isEmpty
      ? '${message.attachments.length} tệp đính kèm'
      : text.trim();
  return '$sender, $timeLabel, $body';
}

IconData _attachmentUploadIcon(MessageAttachmentUploadItem item) {
  final kind = item.picked?.kind ?? item.attachment?.kind;
  return _messageAttachmentIcon(kind ?? MessageAttachmentKind.file);
}

IconData _messageAttachmentIcon(MessageAttachmentKind kind) {
  return switch (kind) {
    MessageAttachmentKind.image => CupertinoIcons.photo,
    MessageAttachmentKind.video => CupertinoIcons.videocam,
    MessageAttachmentKind.audio => CupertinoIcons.mic,
    MessageAttachmentKind.file => CupertinoIcons.doc,
  };
}

String _attachmentUploadLabel(MessageAttachmentUploadStatus status) {
  return switch (status) {
    MessageAttachmentUploadStatus.queued => 'Đang chờ',
    MessageAttachmentUploadStatus.picking => 'Đang chọn',
    MessageAttachmentUploadStatus.uploading => 'Đang tải lên',
    MessageAttachmentUploadStatus.uploaded => 'Sẵn sàng gửi',
    MessageAttachmentUploadStatus.attached => 'Đã gắn',
    MessageAttachmentUploadStatus.failed => 'Lỗi tải lên',
    MessageAttachmentUploadStatus.canceled => 'Đã hủy',
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
}

String _formatVoiceDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

InlineSpan _messageTextSpan(ChatMessage message, bool outgoing) {
  final baseStyle = WebTuiTypography.bodyMedium.copyWith(
    color: WebTuiColors.textPrimary,
    fontWeight: FontWeight.w500,
    height: 1.38,
  );
  final accentColor = WebTuiColors.primary;
  final codeBackground = outgoing
      ? WebTuiColors.primary.withValues(alpha: 0.10)
      : WebTuiColors.backgroundMuted;
  final pattern = RegExp(
    r'<@([A-Za-z0-9_-]+)>|(@[A-Za-z0-9_.-]+)|\*\*([^*]+)\*\*|`([^`]+)`',
  );
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in pattern.allMatches(message.body)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: message.body.substring(cursor, match.start)));
    }
    final mentionId = match.group(1);
    final bareMention = match.group(2);
    final bold = match.group(3);
    final code = match.group(4);
    if (mentionId != null) {
      spans.add(
        TextSpan(
          text: _mentionLabel(mentionId),
          style: baseStyle.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    } else if (bareMention != null) {
      spans.add(
        TextSpan(
          text: bareMention,
          style: baseStyle.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    } else if (bold != null) {
      spans.add(
        TextSpan(
          text: bold,
          style: baseStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
    } else if (code != null) {
      spans.add(
        TextSpan(
          text: code,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            background: Paint()..color = codeBackground,
          ),
        ),
      );
    }
    cursor = match.end;
  }

  if (cursor < message.body.length) {
    spans.add(TextSpan(text: message.body.substring(cursor)));
  }
  return TextSpan(style: baseStyle, children: spans);
}

String _mentionLabel(String value) {
  final normalized = value.trim();
  if (normalized.length <= 12) {
    return '@$normalized';
  }
  return '@${normalized.substring(0, 8)}';
}

List<String> _reactionLabels(List<MessageReactionSummary> reactions) {
  return reactions
      .where((reaction) => reaction.emoji.trim().isNotEmpty)
      .map(
        (reaction) => reaction.count > 1
            ? '${reaction.emoji} ${reaction.count}'
            : reaction.emoji,
      )
      .toList(growable: false);
}
