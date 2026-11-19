import '../data/ide_rpc_client.dart';
import '../domain/ide_demo_models.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_monitor_models.dart';
import '../domain/ide_tools_models.dart';

/// Các `op` Skill / AI Agent / Web & DB / Giám sát (Phụ lục C1). Thao tác ★ do
/// [IdeRpcClient] tự xử lý `need_step`.
class IdeToolsService {
  IdeToolsService(this._rpc);

  final IdeRpcClient _rpc;

  // --- skill
  Future<IdeToolCatalog> skills(String project) async =>
      IdeToolCatalog.parseSkills(
        await _rpc.call('skills.list', {'project': project}),
      );

  /// App gọi khi mở màn; lỗi bỏ qua. Trả `true` nếu có gì vừa được cài / cập
  /// nhật (cần tải lại danh sách).
  Future<bool> ensureSkills(String project) async {
    try {
      final m = toolMap(await _rpc.call('skills.ensure', {'project': project}));
      return toolStrings(m['installed']).isNotEmpty ||
          toolStrings(m['updated']).isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// [op] = `install` | `update` | `remove`.
  Future<void> skillAction(
    String op,
    String project,
    String name, {
    bool force = false,
  }) => _rpc.call('skills.$op', {
    'project': project,
    'name': name,
    if (force && op != 'remove') 'force': true,
  });

  // --- agent / lệnh mẫu
  Future<IdeToolCatalog> agentCatalog(String project) async =>
      IdeToolCatalog.parseAgents(
        await _rpc.call('skills.agent_list', {'project': project}),
      );

  /// [op] = `install` | `update` | `remove`.
  Future<void> agentAction(
    String op,
    String project,
    String name,
    String kind, {
    bool force = false,
  }) => _rpc.call('skills.agent_$op', {
    'project': project,
    'name': name,
    'kind': kind,
    if (force && op != 'remove') 'force': true,
  });

  // --- agents.*
  Future<IdeAgentsOverview> agentsSession(String project, int days) async =>
      IdeAgentsOverview.parse(
        await _rpc.call('agents.session', {'project': project, 'days': days}),
      );

  Future<List<IdeSchedAgent>> agentsStatus(String project) async =>
      IdeSchedAgent.parseStatus(
        await _rpc.call('agents.status', {'project': project, 'limit': 15}),
        project,
      );

  // --- demo
  Future<IdeDemoStatus> demoStatus(String project) async =>
      IdeDemoStatus.parse(await _rpc.call('demo.status', {'project': project}));

  /// `demo.enable` / `demo.set`; trả mã việc nền.
  Future<String> demoApply(
    String op,
    String project, {
    String? server,
    String? root,
    bool? public,
    String? branch,
  }) async => _jobId(
    await _rpc.call(op, {
      'project': project,
      if (server != null && server.isNotEmpty) 'server': server,
      'root': ?root,
      'public': ?public,
      if (branch != null && branch.isNotEmpty) 'branch': branch,
    }),
  );

  /// `demo.update` / `demo.sync`; trả mã việc nền.
  Future<String> demoJob(String op, String project) async =>
      _jobId(await _rpc.call(op, {'project': project}));

  /// `demo.disable` / `demo.db_create` / `demo.db_drop`; trả lời nhắn.
  Future<String> demoSimple(String op, String project) async => toolStr(
    toolMap(await _rpc.call(op, {'project': project}))['message'],
    max: 300,
  );

  /// Mật khẩu chỉ nằm trong giá trị trả về, không lưu ở đâu.
  Future<IdeDbSecret> demoDbShow(String project) async =>
      IdeDbSecret.parse(await _rpc.call('demo.db_show', {'project': project}));

  Future<String> demoLog(String project) async => toolStr(
    toolMap(await _rpc.call('demo.log', {'project': project}))['text'],
    max: 20000,
  );

  // --- giám sát
  Future<List<IdeMonItem>> monitorList(String project) async =>
      IdeMonItem.parseList(
        await _rpc.call('monitor.list', {'project': project}),
      );

  Future<IdeMonInfo> monitorInfo(String project, String key) async =>
      IdeMonInfo.parse(
        await _rpc.call('monitor.info', {'project': project, 'key': key}),
      );

  Future<IdeMonLive> monitorLive(String project, String key) async =>
      IdeMonLive.parse(
        await _rpc.call('monitor.live', {'project': project, 'key': key}),
      );

  Future<IdeMonHistory> monitorHistory(
    String project,
    String key,
    String range,
  ) async => IdeMonHistory.parse(
    await _rpc.call('monitor.history', {
      'project': project,
      'key': key,
      'range': range,
    }),
  );

  static String _jobId(Object? data) {
    final job = data is Map ? data['job'] : null;
    if (job is! String || job.isEmpty) {
      throw const IdeError('ide_error', 'IDE không trả mã việc.');
    }
    return job;
  }
}
