import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../domain/ide_project.dart';

/// Danh sách dự án (`projects.list`); `invalidate` để tải lại.
final ideProjectsProvider = FutureProvider.autoDispose<List<IdeProject>>((
  ref,
) async {
  final data = await ref
      .read(ideRpcClientProvider)
      .call('projects.list', const {});
  return parseIdeProjectList(data);
});

/// Tên dự án người dùng đã chọn ở đầu tab Dự án / Thêm (`null` = chưa chọn).
final ideSelectedProjectNameProvider = StateProvider<String?>((_) => null);

/// Dự án đang chọn; chưa chọn hoặc dự án không còn thì lấy dự án đầu tiên.
final ideCurrentProjectProvider = Provider.autoDispose<AsyncValue<IdeProject?>>(
  (ref) {
    final selected = ref.watch(ideSelectedProjectNameProvider);
    return ref.watch(ideProjectsProvider).whenData((list) {
      for (final p in list) {
        if (p.name == selected) return p;
      }
      return list.isEmpty ? null : list.first;
    });
  },
);
