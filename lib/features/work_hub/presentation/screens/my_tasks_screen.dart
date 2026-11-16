import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../controllers/my_task_display.dart';
import '../controllers/work_hub_providers.dart';
import '../widgets/my_task_list_widgets.dart';
import '../widgets/work_common.dart';

/// Danh sách việc giao cho tôi.
///
/// Ba ô đếm Chưa nhận / Đã nhận / Hoàn thành là bộ lọc (cùng màu thẻ Việc của
/// tôi ở tab Công việc). Việc chưa xong chia theo hạn (Quá hạn, Hôm nay, Ngày
/// mai, 7 ngày tới, Sau này, Không có hạn); "Hoàn thành" chỉ liệt kê việc xong
/// trong 7 ngày qua, khớp ô đếm; việc cũ hơn vẫn tìm được bằng ô tìm (tìm trên
/// mọi việc, kết quả chia theo trạng thái).
class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({
    required this.workspaceId,
    this.startWithSearch = false,
    this.now,
    super.key,
  });

  final String workspaceId;
  final bool startWithSearch;

  /// Mốc giờ để tính hạn và "7 ngày qua" (test truyền cố định; mặc định giờ máy).
  final DateTime? now;

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> {
  final _search = TextEditingController();
  late bool _searching = widget.startWithSearch;
  CollaborationTaskStatus _filter = CollaborationTaskStatus.open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(myAssignedTasksProvider(widget.workspaceId));
    ref.invalidate(myTasksOverviewProvider(widget.workspaceId));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myAssignedTasksProvider(widget.workspaceId));
    final query = _search.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        backgroundColor: WebTuiColors.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                key: const Key('my_tasks_search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr(
                    'Tìm việc theo tên...',
                    'Search tasks by name...',
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              )
            : Text(
                tr('Việc của tôi', 'My tasks'),
                style: WebTuiTypography.titleLarge.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: WebTuiColors.textPrimary,
                ),
              ),
        actions: [
          IconButton(
            key: const Key('my_tasks_search_toggle'),
            tooltip: _searching
                ? tr('Đóng tìm kiếm', 'Close search')
                : tr('Tìm việc', 'Search tasks'),
            icon: Icon(_searching ? WebTuiIcons.close : WebTuiIcons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => const MyTasksSkeleton(),
          error: (error, _) => Center(
            child: WorkErrorBox(
              message: workHubErrorText(error),
              onRetry: _refresh,
            ),
          ),
          data: (tasks) => _content(tasks, query),
        ),
      ),
    );
  }

  Widget _content(List<CollaborationTask> tasks, String query) {
    final now = widget.now ?? DateTime.now();
    final counts = countMyTasks(tasks, now);
    final searching = query.isNotEmpty;
    final List<TaskSection> sections;
    if (searching) {
      sections = groupTasksByStatus(
        tasks
            .where((task) => task.title.toLowerCase().contains(query))
            .toList(growable: false),
      );
    } else if (_filter == CollaborationTaskStatus.done) {
      sections = groupDoneTasks(
        tasks.where((task) => isRecentlyDone(task, now)).toList(),
        now,
      );
    } else {
      sections = groupTasksByDue(
        tasks.where((task) => task.taskStatus == _filter).toList(),
        now,
      );
    }

    final Widget body;
    if (sections.isEmpty) {
      body = _empty(tasks.isEmpty, searching);
    } else {
      body = CustomScrollView(
        key: const Key('my_tasks_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final section in sections) ...[
            SliverToBoxAdapter(child: MyTaskSectionHeader(section: section)),
            SliverToBoxAdapter(
              child: MyTaskSectionCard(
                children: [
                  for (final task in section.tasks)
                    MyTaskListTile(
                      key: ValueKey('my_task_${task.id}'),
                      task: task,
                      now: now,
                      onChanged: _refresh,
                    ),
                ],
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      );
    }

    return Column(
      children: [
        if (!searching) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            // Ba ô luôn cao bằng nhau (ô Hoàn thành có thêm dòng "7 ngày qua").
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, (status, label, count, caption)) in [
                    (
                      CollaborationTaskStatus.open,
                      tr('Chưa nhận', 'Unclaimed'),
                      counts.open,
                      null,
                    ),
                    (
                      CollaborationTaskStatus.inProgress,
                      tr('Đã nhận', 'Claimed'),
                      counts.inProgress,
                      null,
                    ),
                    (
                      CollaborationTaskStatus.done,
                      tr('Hoàn thành', 'Done'),
                      counts.done,
                      tr('7 ngày qua', 'Last 7 days'),
                    ),
                  ].indexed) ...[
                    if (index > 0) const SizedBox(width: 10),
                    Expanded(
                      child: MyTaskFilterTile(
                        key: Key('my_tasks_filter_${status.apiValue}'),
                        status: status,
                        label: label,
                        count: count,
                        caption: caption,
                        selected: _filter == status,
                        onTap: () => setState(() => _filter = status),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_filter == CollaborationTaskStatus.done)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(
                    'Việc xong trong 7 ngày qua. Tìm theo tên để xem việc cũ hơn.',
                    'Tasks done in the last 7 days. Search by name to see older ones.',
                  ),
                  key: const Key('my_tasks_done_hint'),
                  style: WebTuiTypography.bodySmall.copyWith(
                    fontSize: 12.5,
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: body,
          ),
        ),
      ],
    );
  }

  Widget _empty(bool noTasksAtAll, bool searching) {
    final (String title, String message, IconData icon) = noTasksAtAll
        ? (
            tr(
              'Chưa có việc nào được giao cho bạn',
              'No tasks assigned to you yet',
            ),
            tr(
              'Việc được giao cho bạn trong các nhóm chat sẽ hiện ở đây.',
              'Tasks assigned to you in group chats will show up here.',
            ),
            WebTuiIcons.tasks,
          )
        : searching
        ? (
            tr(
              'Không thấy việc nào tên "${_search.text.trim()}"',
              'No task named "${_search.text.trim()}"',
            ),
            tr('Thử tìm bằng từ khác.', 'Try another keyword.'),
            WebTuiIcons.search,
          )
        : switch (_filter) {
            CollaborationTaskStatus.inProgress => (
              tr('Bạn chưa nhận việc nào', "You haven't claimed any task"),
              tr(
                'Bấm ô vuông ở việc chưa nhận để nhận việc.',
                'Tap the box next to an unclaimed task to claim it.',
              ),
              WebTuiIcons.tasks,
            ),
            CollaborationTaskStatus.done => (
              tr(
                'Không có việc nào xong trong 7 ngày qua',
                'No tasks done in the last 7 days',
              ),
              tr(
                'Việc bạn hoàn thành sẽ hiện ở đây.',
                'Tasks you complete will show up here.',
              ),
              WebTuiIcons.taskDone,
            ),
            _ => (
              tr('Không còn việc chưa nhận', 'No unclaimed tasks'),
              tr(
                'Việc mới được giao sẽ hiện ở đây.',
                'New tasks assigned to you will show up here.',
              ),
              WebTuiIcons.taskDone,
            ),
          };
    // Cuộn được để kéo xuống làm mới cả khi trống.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const Key('my_tasks_empty'),
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: MyTasksEmptyState(title: title, message: message, icon: icon),
        ),
      ),
    );
  }
}
