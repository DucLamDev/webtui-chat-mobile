import 'dart:async';

import '../data/ide_rpc_client.dart';
import '../domain/ide_deploy.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_mergeq.dart';
import '../domain/ide_project_info.dart';

/// Log chờ việc chỉ giữ phần cuối (khớp `ideJobLogLimit` của màn Việc).
const ideWaitJobLogLimit = 200000;

/// Kết quả một việc nền đã dừng.
final class IdeJobOutcome {
  const IdeJobOutcome({
    required this.job,
    required this.status,
    required this.ok,
    this.result,
    this.log = '',
  });

  final String job;
  final String status;

  /// Việc chạy tới cùng và báo xong (không lỗi / không huỷ).
  final bool ok;
  final Object? result;
  final String log;
}

bool ideJobStatusOk(String status) =>
    status == 'done' ||
    status == 'ok' ||
    status == 'success' ||
    status == 'finished';

/// Các thao tác dự án / PR / hàng chờ / triển khai qua [IdeRpcClient].
final class IdeProjectService {
  IdeProjectService(this._rpc);

  final IdeRpcClient _rpc;

  Future<Object?> call(String op, Map<String, Object?> args) =>
      _rpc.call(op, args);

  /// Gọi op trả `{job}` rồi trả mã việc.
  Future<String> startJob(String op, Map<String, Object?> args) async {
    final data = await _rpc.call(op, args);
    final job = data is Map ? data['job'] : null;
    if (job is! String || job.isEmpty) {
      throw const IdeError('ide_error', 'IDE không trả mã việc.');
    }
    return job;
  }

  /// Hỏi `jobs.tail` tới khi xong (chỉ giữ phần cuối [ideWaitJobLogLimit]). [onLog] nhận toàn bộ log tới giờ.
  /// [isCancelled] trả `true` thì thôi chờ (ném [IdeCancelled]).
  Future<IdeJobOutcome> waitJob(
    String job, {
    Duration poll = const Duration(milliseconds: 1000),
    Duration timeout = const Duration(minutes: 20),
    void Function(String log)? onLog,
    bool Function()? isCancelled,
  }) async {
    var from = 0;
    var log = '';
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (isCancelled?.call() ?? false) throw const IdeCancelled();
      Object? data;
      try {
        data = await _rpc.call('jobs.tail', {'job': job, 'from': from});
      } on IdeOffline {
        // Mất mạng thoáng qua: thử lại tới hết hạn.
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(poll);
        continue;
      }
      if (data is Map) {
        final text = data['text'];
        if (text is String && text.isNotEmpty) {
          log += text;
          if (log.length > ideWaitJobLogLimit) {
            log = log.substring(log.length - ideWaitJobLogLimit);
          }
          onLog?.call(log);
        }
        final next = data['next'];
        if (next is num) from = next.toInt();
        final status = data['status'] is String ? data['status'] as String : '';
        if (data['done'] == true) {
          return IdeJobOutcome(
            job: job,
            status: status,
            ok: ideJobStatusOk(status),
            result: data['result'],
            log: log,
          );
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const IdeTimeout('Việc chạy quá lâu, hãy xem ở Việc chạy nền.');
      }
      await Future<void>.delayed(poll);
    }
  }

  Future<IdeProjectInfo> info(String project) async => IdeProjectInfo.parse(
    await _rpc.call('projects.info', {'project': project}),
  );

  Future<IdeGitStatus> gitStatus(String project) async =>
      IdeGitStatus.parse(await _rpc.call('git.status', {'project': project}));

  Future<List<IdeCommit>> gitLog(String project, {int n = 20}) async =>
      parseIdeCommits(await _rpc.call('git.log', {'project': project, 'n': n}));

  Future<String> createPr(
    String project, {
    required String title,
    required String body,
    required bool draft,
  }) => startJob('pr.create', {
    'project': project,
    if (title.trim().isNotEmpty) 'title': title.trim(),
    if (body.trim().isNotEmpty) 'body': body.trim(),
    if (draft) 'draft': true,
  });

  Future<String> merge(String project, int number) =>
      startJob('git.merge', {'project': project, 'number': number});

  Future<IdeMergeView> mergeView(String project) async =>
      IdeMergeView.parse(await _rpc.call('mergeq.view', {'project': project}));

  Future<List<IdeMergeMineGroup>> mergeMine() async =>
      parseIdeMergeMine(await _rpc.call('mergeq.mine', const {}));

  Future<IdeMergeMode> mergeMode(String project) async =>
      IdeMergeMode.parse(await _rpc.call('mergeq.mode', {'project': project}));

  Future<void> setMergeMode(String project, String mode) async {
    await _rpc.call('mergeq.mode', {'project': project, 'mode': mode});
  }

  Future<String> mergeLog(String project, int number) async {
    final d = await _rpc.call('mergeq.log', {
      'project': project,
      'number': number,
    });
    return d is Map && d['text'] is String ? d['text'] as String : '';
  }

  Future<void> withdraw(String project, int number) async {
    await _rpc.call('mergeq.withdraw', {'project': project, 'number': number});
  }

  Future<List<IdeLightItem>> lightList(String project) async =>
      IdeLightItem.parseList(
        await _rpc.call('mergeq.light_list', {'project': project}),
      );

  Future<void> lightClear(String project, {String? code}) async {
    await _rpc.call('mergeq.light_clear', {
      'project': project,
      if (code == null) 'all': true else 'ma': code,
    });
  }

  Future<List<IdeHistoryItem>> history(
    IdeDeployOps ops,
    String project,
    String target,
  ) async => IdeHistoryItem.parseList(
    await _rpc.call(ops.history, {
      'project': project,
      if (!ops.isMy && target.isNotEmpty) 'target': target,
    }),
  );

  Future<IdeToGitCheck> toGitCheck(String project) async => IdeToGitCheck.parse(
    await _rpc.call('to_git.check', {'project': project}),
  );

  Future<IdeMyTarget?> myTarget(String project) async =>
      IdeMyTarget.parse(await _rpc.call('targets.show', {'project': project}));

  Future<List<IdeVpsRequest>> vpsRequests() async =>
      IdeVpsRequest.parseList(await _rpc.call('vps.requests', const {}));
}
