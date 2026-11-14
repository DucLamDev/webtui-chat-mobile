import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../controllers/work_hub_providers.dart';
import '../widgets/my_tasks_card.dart';
import '../widgets/work_common.dart';

/// Danh sách việc giao cho tôi, lọc theo trạng thái; có ô tìm theo tên.
///
/// "Hoàn thành" chỉ liệt kê việc xong trong 7 ngày qua, khớp ô đếm ở thẻ Việc
/// của tôi; việc cũ hơn vẫn tìm được bằng ô tìm (tìm trên mọi việc).
class MyTasksScreen extends ConsumerStatefulWidget {
  const MyTasksScreen({
    required this.workspaceId,
    this.startWithSearch = false,
    this.now,
    super.key,
  });

  final String workspaceId;
  final bool startWithSearch;

  /// Mốc giờ để tính "7 ngày qua" (test truyền cố định; mặc định giờ máy).
  final DateTime? now;

  @override
  ConsumerState<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends ConsumerState<MyTasksScreen> {
  static const _filters = [
    (CollaborationTaskStatus.open, 'Chưa nhận'),
    (CollaborationTaskStatus.inProgress, 'Đã nhận'),
    (CollaborationTaskStatus.done, 'Hoàn thành'),
  ];

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
      appBar: AppBar(
        title: _searching
            ? TextField(
                key: const Key('my_tasks_search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Tìm việc theo tên...',
                  border: InputBorder.none,
                  filled: false,
                ),
              )
            : const Text('Việc của tôi'),
        actions: [
          IconButton(
            key: const Key('my_tasks_search_toggle'),
            tooltip: _searching ? 'Đóng tìm kiếm' : 'Tìm việc',
            icon: Icon(_searching ? WebTuiIcons.close : WebTuiIcons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (query.isEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    for (final (status, label) in _filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('my_tasks_filter_${status.apiValue}'),
                          label: Text(label),
                          selected: _filter == status,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = status),
                        ),
                      ),
                  ],
                ),
              ),
            if (query.isEmpty && _filter == CollaborationTaskStatus.done)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Việc xong trong 7 ngày qua. Tìm theo tên để xem việc cũ hơn.',
                    key: const Key('my_tasks_done_hint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      WorkSkeleton(height: 52),
                      SizedBox(height: 12),
                      WorkSkeleton(height: 52),
                      SizedBox(height: 12),
                      WorkSkeleton(height: 52),
                    ],
                  ),
                ),
                error: (error, _) => Center(
                  child: WorkErrorBox(
                    message: workHubErrorText(error),
                    onRetry: _refresh,
                  ),
                ),
                data: (tasks) {
                  final now = widget.now ?? DateTime.now();
                  final shown = tasks
                      .where(
                        (task) => query.isNotEmpty
                            ? task.title.toLowerCase().contains(query)
                            : _filter == CollaborationTaskStatus.done
                            ? isRecentlyDone(task, now)
                            : task.taskStatus == _filter,
                      )
                      .toList(growable: false);
                  if (shown.isEmpty) {
                    return WorkEmptyBox(
                      message: tasks.isEmpty
                          ? 'Chưa có việc nào được giao cho bạn'
                          : query.isEmpty
                          ? _filter == CollaborationTaskStatus.done
                                ? 'Không có việc nào xong trong 7 ngày qua'
                                : 'Không có việc nào ở mục này'
                          : 'Không thấy việc nào tên "${_search.text.trim()}"',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView.separated(
                      key: const Key('my_tasks_list'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: WebTuiColors.border.withValues(alpha: 0.7),
                      ),
                      itemBuilder: (context, index) => AssignedTaskRow(
                        task: shown[index],
                        onChanged: _refresh,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
