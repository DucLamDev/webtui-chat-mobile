import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/use_cases/create_group_use_case.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/channel_create_controller.dart';
import '../controllers/conversation_home_controller.dart';

/// Màn "Tạo nhóm" (đường dẫn cũ `/channels/new`): tên nhóm, mô tả tuỳ chọn và
/// chọn thành viên. Nhóm luôn riêng tư, slug tự sinh từ tên.
class ChannelCreateScreen extends ConsumerWidget {
  const ChannelCreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref
        .watch(workspaceControllerProvider)
        .activeWorkspace
        ?.id;
    if (workspaceId == null || workspaceId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tạo nhóm')),
        body: const SafeArea(
          child: WebTuiEmptyState(
            title: 'Chưa chọn workspace',
            message: 'Bạn cần chọn workspace trước khi tạo nhóm.',
            icon: WebTuiIcons.group,
          ),
        ),
      );
    }
    final currentUserId = ref.watch(
      profileControllerProvider.select((value) => value.profile?.id),
    );
    return GroupCreateView(
      workspaceId: workspaceId,
      currentUserId: currentUserId,
    );
  }
}

/// Nội dung màn tạo nhóm (đã biết workspace và người dùng hiện tại).
class GroupCreateView extends ConsumerStatefulWidget {
  const GroupCreateView({
    required this.workspaceId,
    required this.currentUserId,
    super.key,
  });

  final String workspaceId;
  final String? currentUserId;

  @override
  ConsumerState<GroupCreateView> createState() => _GroupCreateViewState();
}

class _GroupCreateViewState extends ConsumerState<GroupCreateView> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.workspaceId;
    final provider = channelCreateControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final home = ref.watch(conversationHomeControllerProvider(workspaceId));
    final candidates = groupMemberCandidates(
      contacts: home.contacts,
      workspaceMembers: home.workspaceMembers,
      currentUserId: widget.currentUserId,
    );
    final byId = {for (final person in candidates) person.userId: person};
    final selected = [
      for (final id in state.selectedUserIds)
        if (byId[id] != null) byId[id]!,
    ];
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? candidates
        : candidates
              .where((person) => person.searchableText.contains(query))
              .toList(growable: false);
    final canSubmit =
        _nameController.text.trim().isNotEmpty && !state.isSubmitting;

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        toolbarHeight: 54,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
        ),
        titleSpacing: 0,
        title: const Text('Tạo nhóm'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          children: [
            if (state.errorMessage != null) ...[
              WebTuiErrorState(
                title: 'Không tạo được nhóm',
                message: state.errorMessage!,
              ),
              const SizedBox(height: WebTuiSpacing.md),
            ],
            WebTuiDialogTextField(
              key: const Key('group-name-field'),
              controller: _nameController,
              label: 'Tên nhóm',
              hint: 'Ví dụ: Kế hoạch tháng 12',
              maxLength: groupNameMaxLength,
              textInputAction: TextInputAction.next,
              prefixIcon: WebTuiIcons.group,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            WebTuiDialogTextField(
              key: const Key('group-description-field'),
              controller: _descriptionController,
              label: 'Mô tả (tuỳ chọn)',
              hint: 'Nhóm này dùng để làm gì?',
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: WebTuiSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Thành viên',
                    style: WebTuiTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'Đã chọn ${selected.length}',
                  key: const Key('group-selected-count'),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: WebTuiSpacing.sm),
              Wrap(
                spacing: WebTuiSpacing.sm,
                runSpacing: WebTuiSpacing.sm,
                children: [
                  for (final person in selected)
                    _SelectedChip(
                      person: person,
                      onRemove: state.isSubmitting
                          ? null
                          : () => controller.toggleMember(person.userId),
                    ),
                ],
              ),
            ],
            const SizedBox(height: WebTuiSpacing.md),
            WebTuiDialogTextField(
              key: const Key('group-member-search'),
              controller: _searchController,
              hint: 'Tìm bạn bè, thành viên',
              prefixIcon: WebTuiIcons.search,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            if (home.isLoading && candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(WebTuiSpacing.xl),
                child: WebTuiLoadingState(message: 'Đang tải danh sách...'),
              )
            else if (visible.isEmpty)
              WebTuiEmptyState(
                title: candidates.isEmpty
                    ? 'Chưa có ai để thêm'
                    : 'Không tìm thấy',
                message: candidates.isEmpty
                    ? 'Bạn vẫn có thể tạo nhóm trước rồi thêm người sau.'
                    : 'Thử tìm bằng tên khác.',
                icon: WebTuiIcons.group,
              )
            else
              for (final person in visible)
                _PersonTile(
                  person: person,
                  selected: state.selectedUserIds.contains(person.userId),
                  onTap: state.isSubmitting
                      ? null
                      : () => controller.toggleMember(person.userId),
                ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.sm,
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
          ),
          child: FilledButton.icon(
            key: const Key('group-create-button'),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? WebTuiColors.textMuted
                    : WebTuiColors.textOnPrimary,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? WebTuiColors.backgroundMuted
                    : WebTuiColors.primary,
              ),
            ),
            onPressed: canSubmit ? () => _submit(context, controller) : null,
            icon: state.isSubmitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(WebTuiIcons.newGroup),
            label: const Text('Tạo nhóm'),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    ChannelCreateController controller,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final outcome = await controller.submit(
      name: _nameController.text,
      description: _descriptionController.text,
    );
    if (outcome == null || !mounted) return;
    final channel = outcome.channel;
    if (outcome.failedCount > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Không thêm được ${outcome.failedCount} người')),
      );
    }
    router.replace(
      Uri(
        path: '/conversations/${channel.channelId}',
        queryParameters: {
          'workspaceId': channel.workspaceId,
          'title': channel.title,
        },
      ).toString(),
      extra: channel,
    );
  }
}

/// Người có thể thêm vào nhóm: bạn bè trước, rồi thành viên workspace; bỏ
/// trùng, bỏ chính mình và người đang chờ kết bạn.
List<ContactSummary> groupMemberCandidates({
  required List<ContactSummary> contacts,
  required List<ContactSummary> workspaceMembers,
  required String? currentUserId,
}) {
  final me = currentUserId?.trim();
  final seen = <String>{};
  final result = <ContactSummary>[];
  for (final person in [...contacts, ...workspaceMembers]) {
    final id = person.userId.trim();
    if (id.isEmpty || id == me) continue;
    if (person.hasContactRelationship && !person.canOpenDirectConversation) {
      continue;
    }
    if (seen.add(id)) result.add(person);
  }
  return result;
}

String _personName(ContactSummary person) {
  final name = person.displayName.trim();
  return name.isNotEmpty ? name : person.username;
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.selected,
    required this.onTap,
  });

  final ContactSummary person;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = person.title?.trim().isNotEmpty == true
        ? person.title!.trim()
        : person.username;
    return Semantics(
      selected: selected,
      child: InkWell(
        key: Key('group-member-${person.userId}'),
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WebTuiSpacing.xs,
              vertical: WebTuiSpacing.xs,
            ),
            child: Row(
              children: [
                WebTuiAvatar(
                  label: _personName(person),
                  imageUrl: person.avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: WebTuiSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _personName(person),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: WebTuiColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected ? WebTuiIcons.selected : WebTuiIcons.unselected,
                  size: 24,
                  color: selected
                      ? WebTuiColors.primary
                      : WebTuiColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.person, required this.onRemove});

  final ContactSummary person;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Bỏ chọn ${_personName(person)}',
      child: InkWell(
        key: Key('group-chip-${person.userId}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onRemove,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40, maxWidth: 220),
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          decoration: BoxDecoration(
            color: WebTuiColors.primarySoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WebTuiAvatar(
                label: _personName(person),
                imageUrl: person.avatarUrl,
                size: 32,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Flexible(
                child: Text(
                  _personName(person),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.xs),
              const Icon(
                WebTuiIcons.close,
                size: 16,
                color: WebTuiColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
