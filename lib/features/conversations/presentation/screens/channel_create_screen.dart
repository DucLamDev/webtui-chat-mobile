import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/conversation_summary.dart';
import '../controllers/channel_create_controller.dart';

class ChannelCreateScreen extends ConsumerStatefulWidget {
  const ChannelCreateScreen({super.key});

  @override
  ConsumerState<ChannelCreateScreen> createState() =>
      _ChannelCreateScreenState();
}

class _ChannelCreateScreenState extends ConsumerState<ChannelCreateScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = ref
        .watch(workspaceControllerProvider)
        .activeWorkspace
        ?.id;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: WebTuiEmptyState(
            title: 'Chưa chọn workspace',
            message: 'Bạn cần chọn workspace trước khi tạo kênh.',
            icon: Icons.business_rounded,
          ),
        ),
      );
    }

    final provider = channelCreateControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        toolbarHeight: 54,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
        ),
        titleSpacing: 0,
        title: const Text('Tạo kênh'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          children: [
            if (state.errorMessage != null)
              WebTuiErrorState(
                title: 'Không tạo được kênh',
                message: state.errorMessage!,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: WebTuiColors.primarySoft,
                borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                border: Border.all(
                  color: WebTuiColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WebTuiAvatar(
                      label: 'Kênh',
                      icon: Icons.tag_rounded,
                      size: 46,
                      color: WebTuiColors.surface,
                    ),
                    const SizedBox(width: WebTuiSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tạo không gian trao đổi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: WebTuiSpacing.xs),
                          Text(
                            'Đặt tên rõ ràng để thành viên tìm và tham gia đúng kênh.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodySmall.copyWith(
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
            const SizedBox(height: WebTuiSpacing.lg),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Tên kênh',
                hintText: 'Ví dụ: Kế toán',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              onChanged: (value) {
                if (_slugController.text.trim().isEmpty) {
                  _slugController.text = _suggestSlug(value);
                }
              },
            ),
            const SizedBox(height: WebTuiSpacing.md),
            TextField(
              controller: _slugController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Slug',
                hintText: 'vi-du-ke-toan',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                hintText: 'Kênh trao đổi nội bộ của workspace',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            WebTuiSegmentedTabs(
              tabs: const ['Công khai', 'Riêng tư'],
              selectedIndex: state.visibility == ChannelVisibility.public
                  ? 0
                  : 1,
              onChanged: (index) {
                controller.setVisibility(
                  index == 0
                      ? ChannelVisibility.public
                      : ChannelVisibility.private,
                );
              },
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
            onPressed: state.isSubmitting
                ? null
                : () => _submit(context, controller),
            icon: state.isSubmitting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text('Tạo kênh'),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    ChannelCreateController controller,
  ) async {
    final channel = await controller.submit(
      name: _nameController.text,
      slug: _slugController.text,
      description: _descriptionController.text,
    );
    if (channel != null && context.mounted) {
      context.replace(
        Uri(
          path: '/channels/${channel.channelId}',
          queryParameters: {'title': channel.title},
        ).toString(),
      );
    }
  }
}

String _suggestSlug(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
      .replaceAll('đ', 'd')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return normalized;
}
