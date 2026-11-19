/// Mô hình Máy chủ của tôi và Điện thoại đã gắn (`servers.*`, `devices.*`).
library;

import 'ide_tools_models.dart';

final class IdeServer {
  const IdeServer({
    required this.name,
    this.host = '',
    this.port,
    this.user = '',
    this.label = '',
    this.keyOk = false,
    this.fingerprint = '',
    this.createdAt,
    this.projects = const [],
  });

  final String name;
  final String host;
  final int? port;
  final String user;
  final String label;
  final bool keyOk;
  final String fingerprint;
  final DateTime? createdAt;
  final List<String> projects;

  static List<IdeServer> parseList(Object? data) => [
    for (final s in toolMaps(toolMap(data)['items'], max: 200))
      if (toolStr(s['name']).isNotEmpty)
        IdeServer(
          name: toolStr(s['name'], max: 40),
          host: toolStr(s['host'], max: 253),
          port: s['port'] == null ? null : toolInt(s['port']),
          user: toolStr(s['user'], max: 40),
          label: toolStr(s['label'], max: 120),
          keyOk: toolBool(s['key_ok']),
          fingerprint: toolStr(s['fingerprint'], max: 100),
          createdAt: toolTime(s['created_at']),
          projects: toolStrings(s['projects'], max: 50, len: 80),
        ),
  ];
}

final class IdeDevice {
  const IdeDevice({
    required this.id,
    this.name = '',
    this.createdAt,
    this.lastUsed,
    this.current = false,
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final DateTime? lastUsed;
  final bool current;

  static List<IdeDevice> parseList(Object? data) => [
    for (final d in toolMaps(toolMap(data)['items'], max: 200))
      if (RegExp(
        r'^[A-Za-z0-9_-]{8,64}$',
      ).hasMatch(toolStr(d['device_id'], max: 80)))
        IdeDevice(
          id: toolStr(d['device_id'], max: 80),
          name: toolStr(d['name'], max: 120),
          createdAt: toolTime(d['created_at']),
          lastUsed: toolTime(d['last_used']),
          current: toolBool(d['current']),
        ),
  ];
}
