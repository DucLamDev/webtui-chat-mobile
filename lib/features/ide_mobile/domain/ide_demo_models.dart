/// Mô hình Web & DB (`demo.*`, Phụ lục C1).
library;

import 'ide_tools_models.dart';

final _safeUrl = RegExp(r'^https://[a-z0-9][a-z0-9.-]*[a-z0-9](/.*)?$');

/// Chỉ nhận địa chỉ https đúng mẫu hợp đồng; còn lại coi như không có.
String? ideSafeUrl(Object? v) {
  if (v is! String || v.length > 500 || !_safeUrl.hasMatch(v)) return null;
  return v;
}

final class IdeDemoStatus {
  const IdeDemoStatus({
    this.my = false,
    this.canManage = false,
    this.installed = const {},
    this.phpVersion = '',
    this.domain = '',
    this.pmaUrl,
    this.mode = '',
    this.enabled = false,
    this.exists = false,
    this.server = '',
    this.public = false,
    this.root = '',
    this.branch = '',
    this.sha = '',
    this.updatedAt,
    this.url,
    this.hasDb = false,
    this.dbName = '',
    this.syncError = '',
    this.eligible = true,
    this.why = '',
    this.allowPublic = true,
    this.limitMax,
    this.limitUsed,
  });

  final bool my;
  final bool canManage;
  final Map<String, bool> installed;
  final String phpVersion;
  final String domain;
  final String? pmaUrl;
  final String mode;
  final bool enabled;
  final bool exists;
  final String server;
  final bool public;
  final String root;
  final String branch;
  final String sha;
  final DateTime? updatedAt;
  final String? url;
  final bool hasDb;
  final String dbName;
  final String syncError;
  final bool eligible;
  final String why;
  final bool allowPublic;
  final int? limitMax;
  final int? limitUsed;

  /// `demo.update` chỉ có ở dự án công ty chế độ GitHub.
  bool get canUpdate => !my && mode == 'github';

  factory IdeDemoStatus.parse(Object? data) {
    final m = toolMap(data);
    final my = toolBool(m['my']);
    final d = toolMap(m['demo']);
    final inst = toolMap(m['installed']);
    final limits = toolMap(m['limits']);
    final syncedAt = my ? d['synced_at'] : d['updated_at'];
    return IdeDemoStatus(
      my: my,
      canManage: my ? m['can_manage'] != false : toolBool(m['can_manage']),
      installed: {for (final e in inst.entries) e.key: e.value == true},
      phpVersion: toolStr(m['php_version'], max: 20),
      domain: toolStr(m['domain'], max: 253),
      pmaUrl: ideSafeUrl(m['pma_url']),
      mode: toolStr(m['mode'], max: 20),
      enabled: toolBool(d['enabled']),
      exists: toolBool(d['exists']),
      server: toolStr(d['server'], max: 20),
      public: toolBool(d['public']),
      root: toolStr(d['root'], max: 600),
      branch: toolStr(d['branch_used'] ?? d['branch'], max: 100),
      sha: toolStr(d['sha'], max: 40),
      updatedAt: toolTime(syncedAt),
      url: ideSafeUrl(d['url']),
      hasDb: toolBool(d['db']),
      dbName: toolStr(d['db_name'], max: 100),
      syncError: toolStr(d['sync_error'], max: 300),
      eligible: m['eligible'] != false,
      why: toolStr(m['why'], max: 300),
      allowPublic: m['allow_public'] != false,
      limitMax: limits['max'] == null ? null : toolInt(limits['max']),
      limitUsed: limits['used'] == null ? null : toolInt(limits['used']),
    );
  }
}

/// Thông tin kết nối DB của `demo.db_show`. Mật khẩu KHÔNG nằm trong mô hình
/// này mà đi riêng trong [IdeDbSecret], chỉ sống trong hộp thoại tạm.
final class IdeDbInfo {
  const IdeDbInfo({
    this.host = '',
    this.port = '',
    this.database = '',
    this.username = '',
  });

  final String host;
  final String port;
  final String database;
  final String username;
}

final class IdeDbSecret {
  IdeDbSecret(this.info, this.password);

  final IdeDbInfo info;
  final String password;

  factory IdeDbSecret.parse(Object? data) {
    final m = toolMap(data);
    final d = toolMap(m['db']);
    return IdeDbSecret(
      IdeDbInfo(
        host: toolStr(d['host'], max: 253),
        port: d['port'] is num
            ? '${toolInt(d['port'])}'
            : toolStr(d['port'], max: 8),
        database: toolStr(d['database'], max: 100),
        username: toolStr(d['username'], max: 100),
      ),
      toolStr(m['password'], max: 500),
    );
  }

  /// Không cho mật khẩu lọt vào chuỗi in log.
  @override
  String toString() => 'IdeDbSecret(***)';
}
