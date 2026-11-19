import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/ide_project_service.dart';
import '../../domain/ide_project.dart';
import '../../domain/ide_project_info.dart';
import 'ide_controllers.dart';

final ideProjectServiceProvider = Provider<IdeProjectService>(
  (ref) => IdeProjectService(ref.watch(ideRpcClientProvider)),
);

/// Thông tin đầu tab: `projects.info` bắt buộc; `git.status` / `git.log` có
/// thì hiện, lỗi riêng chúng không chặn cả tab.
final class IdeProjectOverview {
  const IdeProjectOverview({
    required this.info,
    this.status,
    this.log = const [],
  });

  final IdeProjectInfo info;
  final IdeGitStatus? status;
  final List<IdeCommit> log;
}

final ideProjectOverviewProvider = FutureProvider.autoDispose
    .family<IdeProjectOverview, IdeProject>((ref, project) async {
      final svc = ref.read(ideProjectServiceProvider);
      final ready = ref.read(ideLinkStatusProvider).valueOrNull?.ready;
      bool has(String op) => ready == null || ready.hasOp(op);
      final info = await svc.info(project.name);
      IdeGitStatus? status;
      var log = const <IdeCommit>[];
      if (project.kind != IdeProjectKind.local || project.isGit) {
        if (has('git.status')) {
          status = await svc
              .gitStatus(project.name)
              .catchError((_) => const IdeGitStatus());
        }
        if (has('git.log')) {
          log = await svc
              .gitLog(project.name, n: 10)
              .catchError((_) => const <IdeCommit>[]);
        }
      }
      return IdeProjectOverview(info: info, status: status, log: log);
    });

/// Đồng hồ của các màn Dự án (test thay để thử hạn 15 phút).
final ideProjectNowProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Nhịp hỏi `jobs.tail` của các màn Dự án (test đổi cho ngắn).
final ideProjectPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 1000),
);
