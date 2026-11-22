import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/ide_files_service.dart';
import '../widgets/ai/ide_new_session_sheet.dart'
    show IdeProjectItem, parseIdeProjects;

final ideFilesServiceProvider = Provider<IdeFilesService>(
  (ref) => IdeFilesService(ref.watch(ideRpcClientProvider)),
);

/// Dự án trong `projects.list` (tải lại khi `invalidate`).
final ideFileProjectsProvider = FutureProvider<List<IdeProjectItem>>((
  ref,
) async {
  // Client mới (đổi phiên / xoá bộ nhớ IDE) thì tải lại từ đầu.
  final data = await ref
      .watch(ideRpcClientProvider)
      .call('projects.list', const {});
  return parseIdeProjects(data);
});

/// Mục đang giữ để dán (sao chép hoặc cắt).
final class IdeFileClip {
  const IdeFileClip({
    required this.path,
    required this.name,
    required this.cut,
    required this.isDir,
  });

  final String path;
  final String name;
  final bool cut;
  final bool isDir;
}

final ideFilesClipboardProvider = StateProvider<IdeFileClip?>((ref) {
  ref.watch(ideRpcClientProvider); // client mới theo mỗi phiên / lần xoá bộ nhớ
  return null;
});

/// Dự án + thư mục đang xem, giữ khi đổi tab.
final class IdeFilesLocation {
  const IdeFilesLocation({required this.root, required this.dir});
  final String root;
  final String dir;
}

final ideFilesLocationProvider = StateProvider<IdeFilesLocation?>((ref) {
  ref.watch(ideRpcClientProvider); // client mới theo mỗi phiên / lần xoá bộ nhớ
  return null;
});

enum IdeFileSort { name, date, size }

final ideFilesSortProvider = StateProvider<IdeFileSort>(
  (_) => IdeFileSort.name,
);
final ideFilesShowHiddenProvider = StateProvider<bool>((_) => false);
