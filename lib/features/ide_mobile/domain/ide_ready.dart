import 'ide_session_state.dart' show ideJsonInt;

/// Khung `ready` của IDE sau bắt tay: danh sách thao tác bản IDE này hỗ trợ.
final class IdeReady {
  const IdeReady({
    this.user = '',
    this.protocol = 0,
    this.ideVersion = '',
    this.ops = const {},
    this.features = const {},
  });

  final String user;
  final int protocol;
  final String ideVersion;
  final Set<String> ops;
  final Map<String, bool> features;

  bool hasOp(String op) => ops.contains(op);

  /// Có ít nhất một thao tác bắt đầu bằng `<prefix>.` (để hiện / ẩn tab).
  bool hasGroup(String prefix) => ops.any((o) => o.startsWith('$prefix.'));

  bool feature(String name) => features[name] == true;

  factory IdeReady.fromFrame(Map<String, Object?> frame) {
    final ops = frame['ops'];
    final features = frame['features'];
    return IdeReady(
      user: frame['user'] is String ? frame['user']! as String : '',
      protocol: ideJsonInt(frame['protocol']) ?? 0,
      ideVersion: frame['ide_version'] is String
          ? frame['ide_version']! as String
          : '',
      ops: {
        if (ops is List)
          for (final o in ops)
            if (o is String) o,
      },
      features: {
        if (features is Map)
          for (final e in features.entries)
            if (e.value is bool) e.key.toString(): e.value! as bool,
      },
    );
  }
}
