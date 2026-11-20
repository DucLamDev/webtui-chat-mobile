import '../data/ide_rpc_client.dart';
import '../domain/ide_server_models.dart';
import '../domain/ide_tools_models.dart';
import 'ide_project_service.dart';

/// Kết quả một thao tác máy chủ (đã xong, kể cả việc nền).
final class IdeServerResult {
  const IdeServerResult({
    required this.ok,
    this.message = '',
    this.fingerprint = '',
  });

  final bool ok;
  final String message;
  final String fingerprint;
}

/// `servers.*` (Phụ lục C3). Mật khẩu chỉ đi trong `args` của đúng một lần gọi,
/// không giữ lại trong đối tượng này.
class IdeServersService {
  IdeServersService(this._rpc) : _jobs = IdeProjectService(_rpc);

  final IdeRpcClient _rpc;
  final IdeProjectService _jobs;

  Future<List<IdeServer>> list() async =>
      IdeServer.parseList(await _rpc.call('servers.list', const {}));

  /// Khoá công khai SSH một dòng của chính tài khoản.
  Future<String> pubkey() async => toolStr(
    toolMap(await _rpc.call('servers.key', const {}))['pubkey'],
    max: 2000,
  ).trim();

  Future<IdeServerResult> check(String name, {bool Function()? isCancelled}) =>
      _runJob('servers.check', {'name': name}, isCancelled);

  Future<IdeServerResult> add({
    required String host,
    required String user,
    String? name,
    int? port,
    String? label,
    String? password,
    bool monitor = true,
    bool Function()? isCancelled,
  }) => _runJob('servers.add', {
    if (name != null && name.isNotEmpty) 'name': name,
    'host': host,
    'port': ?port,
    'user': user,
    if (label != null && label.isNotEmpty) 'label': label,
    if (password != null && password.isNotEmpty) 'password': password,
    'monitor': monitor,
  }, isCancelled);

  /// Chỉ đổi nhãn: trả ngay; đổi host / port / user / mật khẩu: việc nền.
  Future<IdeServerResult> edit(
    String name, {
    String? label,
    String? host,
    int? port,
    String? user,
    String? password,
    bool Function()? isCancelled,
  }) => _runJob('servers.edit', {
    'name': name,
    'label': ?label,
    'host': ?host,
    'port': ?port,
    'user': ?user,
    if (password != null && password.isNotEmpty) 'password': password,
  }, isCancelled);

  Future<IdeServerResult> remove(
    String name, {
    bool withProjects = false,
  }) async {
    final m = toolMap(
      await _rpc.call('servers.remove', {
        'name': name,
        if (withProjects) 'with_projects': true,
      }),
    );
    return IdeServerResult(ok: true, message: toolStr(m['message'], max: 300));
  }

  Future<IdeServerResult> _runJob(
    String op,
    Map<String, Object?> args,
    bool Function()? isCancelled,
  ) async {
    final data = await _rpc.call(op, args);
    final m = toolMap(data);
    final job = m['job'];
    if (job is! String || job.isEmpty) {
      return IdeServerResult(
        ok: m['ok'] != false,
        message: toolStr(m['message'], max: 300),
      );
    }
    final out = await _jobs.waitJob(job, isCancelled: isCancelled);
    final r = toolMap(out.result);
    return IdeServerResult(
      ok: out.ok && r['ok'] != false,
      message: toolStr(r['message'], max: 300),
      fingerprint: toolStr(r['fingerprint'], max: 100),
    );
  }
}
