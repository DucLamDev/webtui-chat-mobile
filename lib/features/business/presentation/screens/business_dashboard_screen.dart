import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/business_dashboard.dart';
import '../controllers/business_dashboard_controller.dart';

class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = businessDashboardControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    if (state.isLoading && state.data == null) {
      return const WebTuiLoadingState(message: 'Đang tải module nghiệp vụ...');
    }

    final data = state.data;
    if (data == null) {
      return WebTuiErrorState(
        title: 'Không tải được module nghiệp vụ',
        message: state.errorMessage ?? 'Hãy thử lại sau.',
        onRetry: controller.load,
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: WebTuiSpacing.xl),
        children: [
          if (state.errorMessage != null)
            WebTuiErrorState(
              title: 'Có module chưa tải được',
              message: state.errorMessage!,
              onRetry: controller.refresh,
            ),
          if (state.noticeMessage != null)
            _NoticeTile(message: state.noticeMessage!),
          if (data.errors.isNotEmpty) _ModuleErrors(errors: data.errors),
          if (data.adminStats != null) _StatsStrip(stats: data.adminStats!),
          const WebTuiSectionLabel('Phòng ban'),
          _DepartmentsSection(items: data.departments),
          const WebTuiSectionLabel('Bot và AI'),
          _BotsSection(
            data: data,
            testing: state.isTestingFlow,
            onTestFlow: controller.testFlow,
            onPublishFlow: controller.publishFlow,
          ),
          const WebTuiSectionLabel('Ticket'),
          _TicketsSection(
            items: data.tickets,
            onCreate: () =>
                _showCreateTicketDialog(context, controller.createTicket),
            onSetStatus: controller.updateTicketStatus,
          ),
          const WebTuiSectionLabel('Automation'),
          _CronJobsSection(
            items: data.cronJobs,
            onRun: controller.runCronJob,
            onSetStatus: controller.updateCronJobStatus,
          ),
          const WebTuiSectionLabel('Webhook và API'),
          _WebhooksSection(
            items: data.webhooks,
            apiTokens: data.apiTokens,
            onRevokeToken: controller.revokeApiToken,
          ),
          const WebTuiSectionLabel('Admin mobile'),
          _AdminMobileSection(
            health: data.adminHealth,
            auditLogs: data.auditLogs,
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});

  final AdminStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Members', stats.members),
      ('Channels', stats.channels),
      ('Messages', stats.messages),
      ('Files', stats.files),
      ('Bots', stats.bots),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
      ),
      child: SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: metrics.length,
          separatorBuilder: (_, _) => const SizedBox(width: WebTuiSpacing.sm),
          itemBuilder: (context, index) {
            final metric = metrics[index];
            return Container(
              width: 112,
              padding: const EdgeInsets.all(WebTuiSpacing.md),
              decoration: BoxDecoration(
                color: WebTuiColors.surface,
                borderRadius: BorderRadius.circular(WebTuiRadii.md),
                border: Border.all(color: WebTuiColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    metric.$2.toString(),
                    style: WebTuiTypography.titleMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
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

class _DepartmentsSection extends StatelessWidget {
  const _DepartmentsSection({required this.items});

  final List<DepartmentSummary> items;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: items.isEmpty
          ? const [
              WebTuiSettingRow(
                title: 'Chưa có phòng ban',
                subtitle:
                    'Backend trả về danh sách rỗng hoặc bạn chưa có quyền',
                icon: Icons.account_tree_outlined,
              ),
            ]
          : [
              for (final item in items)
                WebTuiSettingRow(
                  title: item.name,
                  subtitle:
                      '${item.memberCount} thành viên, ${item.channelCount} kênh',
                  icon: Icons.account_tree_outlined,
                  trailing: _StatusPill(label: item.leadCount.toString()),
                ),
            ],
    );
  }
}

class _BotsSection extends StatelessWidget {
  const _BotsSection({
    required this.data,
    required this.testing,
    required this.onTestFlow,
    required this.onPublishFlow,
  });

  final BusinessDashboardData data;
  final bool testing;
  final void Function(BotWorkspaceDetail detail, BotFlowSummary flow)
  onTestFlow;
  final void Function(BotWorkspaceDetail detail, BotFlowSummary flow)
  onPublishFlow;

  @override
  Widget build(BuildContext context) {
    final detail = data.botDetail;
    return WebTuiListSurface(
      children: [
        if (data.bots.isEmpty)
          const WebTuiSettingRow(
            title: 'Chưa có bot',
            subtitle: 'Bot catalog sẽ hiện tại đây khi backend có dữ liệu',
            icon: Icons.smart_toy_outlined,
          )
        else
          for (final bot in data.bots)
            WebTuiSettingRow(
              title: bot.name,
              subtitle: bot.description ?? bot.slug,
              icon: Icons.smart_toy_outlined,
              trailing: _StatusPill(label: bot.status),
            ),
        if (detail != null)
          WebTuiSettingRow(
            title: 'AI config',
            subtitle: detail.aiConfig == null
                ? 'Chưa cấu hình provider/model'
                : '${detail.aiConfig!.provider} / ${detail.aiConfig!.model}',
            icon: Icons.memory_rounded,
            trailing: detail.aiConfig?.secretRef == null
                ? null
                : const _StatusPill(label: 'vault'),
          ),
        if (detail != null)
          for (final flow in detail.flows)
            WebTuiSettingRow(
              title: flow.name,
              subtitle: 'Flow ${flow.status}, v${flow.version}',
              icon: Icons.schema_outlined,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Publish',
                    onPressed: flow.status == 'published'
                        ? null
                        : () => onPublishFlow(detail, flow),
                    icon: const Icon(Icons.cloud_done_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Test',
                    onPressed: testing ? null : () => onTestFlow(detail, flow),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  ),
                ],
              ),
            ),
        if (detail != null)
          WebTuiSettingRow(
            title: 'Installations',
            subtitle: '${detail.installations.length} nơi cài đặt',
            icon: Icons.extension_outlined,
          ),
      ],
    );
  }
}

class _TicketsSection extends StatelessWidget {
  const _TicketsSection({
    required this.items,
    required this.onCreate,
    required this.onSetStatus,
  });

  final List<TicketSummary> items;
  final VoidCallback onCreate;
  final void Function(TicketSummary ticket, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: [
        WebTuiSettingRow(
          title: 'Tạo ticket',
          subtitle: 'Tạo ticket mới bằng endpoint backend',
          icon: Icons.add_task_outlined,
          onTap: onCreate,
          trailing: const Icon(Icons.add_rounded, color: WebTuiColors.primary),
        ),
        if (items.isEmpty)
          const WebTuiSettingRow(
            title: 'Chưa có ticket',
            subtitle: 'Ticket lifecycle sẽ hiện ở đây',
            icon: Icons.confirmation_number_outlined,
          )
        else
          for (final item in items.take(8))
            WebTuiSettingRow(
              title: item.title,
              subtitle: '${item.priority} - cập nhật ${_date(item.updatedAt)}',
              icon: Icons.confirmation_number_outlined,
              trailing: PopupMenuButton<String>(
                tooltip: 'Đổi trạng thái',
                onSelected: (status) => onSetStatus(item, status),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                  PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                  PopupMenuItem(value: 'closed', child: Text('Closed')),
                ],
                child: _StatusPill(label: item.status),
              ),
            ),
      ],
    );
  }
}

class _CronJobsSection extends StatelessWidget {
  const _CronJobsSection({
    required this.items,
    required this.onRun,
    required this.onSetStatus,
  });

  final List<CronJobSummary> items;
  final ValueChanged<CronJobSummary> onRun;
  final void Function(CronJobSummary cronJob, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: items.isEmpty
          ? const [
              WebTuiSettingRow(
                title: 'Chưa có cronjob',
                subtitle: 'Automation CRUD/run/pause dùng endpoint cronjobs',
                icon: Icons.schedule_outlined,
              ),
            ]
          : [
              for (final item in items)
                WebTuiSettingRow(
                  title: item.name,
                  subtitle: '${item.runner} - ${item.schedule ?? 'manual'}',
                  icon: Icons.schedule_outlined,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Chạy ngay',
                        onPressed: () => onRun(item),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Đổi trạng thái',
                        onSelected: (status) => onSetStatus(item, status),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'active', child: Text('Active')),
                          PopupMenuItem(value: 'paused', child: Text('Paused')),
                          PopupMenuItem(
                            value: 'disabled',
                            child: Text('Disabled'),
                          ),
                        ],
                        child: _StatusPill(label: item.status),
                      ),
                    ],
                  ),
                ),
            ],
    );
  }
}

class _WebhooksSection extends StatelessWidget {
  const _WebhooksSection({
    required this.items,
    required this.apiTokens,
    required this.onRevokeToken,
  });

  final List<WebhookSummary> items;
  final List<ApiTokenSummary> apiTokens;
  final ValueChanged<ApiTokenSummary> onRevokeToken;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: [
        if (items.isEmpty)
          const WebTuiSettingRow(
            title: 'Chưa có webhook',
            subtitle: 'Secret chỉ hiện một lần khi tạo trên backend',
            icon: Icons.webhook_outlined,
          )
        else
          for (final item in items)
            WebTuiSettingRow(
              title: item.name,
              subtitle: item.targetUrl ?? item.channelId ?? item.kind,
              icon: Icons.webhook_outlined,
              trailing: _StatusPill(label: item.kind),
            ),
        if (apiTokens.isEmpty)
          const WebTuiSettingRow(
            title: 'Chưa có API token',
            subtitle: 'Token secret không được lưu cache trong mobile',
            icon: Icons.key_outlined,
          )
        else
          for (final token in apiTokens)
            WebTuiSettingRow(
              title: token.name,
              subtitle: token.scopes.isEmpty
                  ? token.status
                  : '${token.status} - ${token.scopes.take(2).join(', ')}',
              icon: Icons.key_outlined,
              trailing: IconButton(
                tooltip: 'Thu hồi token',
                onPressed: () => onRevokeToken(token),
                icon: const Icon(Icons.block_rounded, size: 18),
              ),
            ),
      ],
    );
  }
}

class _AdminMobileSection extends StatelessWidget {
  const _AdminMobileSection({required this.health, required this.auditLogs});

  final AdminHealthSummary? health;
  final List<AuditLogSummary> auditLogs;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: [
        WebTuiSettingRow(
          title: 'Workspace admin',
          subtitle: 'Thành viên, role, kênh, bot và automation cơ bản',
          icon: Icons.admin_panel_settings_outlined,
          trailing: health == null
              ? null
              : _StatusPill(label: health!.isReady ? 'ready' : health!.status),
        ),
        WebTuiSettingRow(
          title: 'System health',
          subtitle: health == null
              ? 'Cần quyền admin.view'
              : health!.checks.entries
                    .take(2)
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join(', '),
          icon: Icons.health_and_safety_outlined,
        ),
        if (auditLogs.isEmpty)
          const WebTuiSettingRow(
            title: 'Chưa có audit log',
            subtitle: 'Cần quyền audit.view để xem thay đổi gần nhất',
            icon: Icons.manage_search_outlined,
          )
        else
          for (final log in auditLogs.take(5))
            WebTuiSettingRow(
              title: log.action,
              subtitle: '${log.entityType} - ${_date(log.createdAt)}',
              icon: Icons.manage_search_outlined,
              trailing: const Icon(
                Icons.history_rounded,
                color: WebTuiColors.textMuted,
              ),
            ),
        const WebTuiSettingRow(
          title: 'Admin panel web',
          subtitle: 'Mở trên browser khi cần thao tác nặng',
          icon: Icons.open_in_browser_rounded,
        ),
      ],
    );
  }
}

Future<void> _showCreateTicketDialog(
  BuildContext context,
  Future<void> Function(CreateTicketDraft draft) onCreate,
) async {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  var priority = 'normal';
  try {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tạo ticket'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Tiêu đề',
                        hintText: 'Nhập vấn đề cần xử lý',
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.md),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả',
                        hintText: 'Bổ sung ngữ cảnh nếu có',
                      ),
                    ),
                    const SizedBox(height: WebTuiSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: 'Ưu tiên'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(
                          value: 'normal',
                          child: Text('Normal'),
                        ),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(
                          value: 'urgent',
                          child: Text('Urgent'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => priority = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop();
                    onCreate(
                      CreateTicketDraft(
                        title: title,
                        description: descriptionController.text,
                        priority: priority,
                      ),
                    );
                  },
                  child: const Text('Tạo'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    titleController.dispose();
    descriptionController.dispose();
  }
}

class _ModuleErrors extends StatelessWidget {
  const _ModuleErrors({required this.errors});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.accentAmber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          border: Border.all(
            color: WebTuiColors.accentAmber.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: Text(
            errors.entries
                .map((entry) => '${entry.key}: ${entry.value}')
                .join('\n'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.primarySoft,
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          child: Text(
            message,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.labelSmall.copyWith(
            color: WebTuiColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}
