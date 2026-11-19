import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ide_ready.dart';

/// Một phiên terminal trong `term.list`.
final class IdeTermItem {
  const IdeTermItem({
    required this.name,
    required this.root,
    required this.cmd,
    this.attached = false,
  });

  final String name;
  final String root;

  /// `claude | codex | shell | ssh:<alias> | my-ssh:<alias>`.
  final String cmd;

  /// Đang có máy khác (máy tính, điện thoại khác) gắn vào.
  final bool attached;

  /// Tên thư mục cuối của dự án.
  String get project {
    final parts = root.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? root : parts.last;
  }

  static IdeTermItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || !ideTermNameOk(name)) return null;
    return IdeTermItem(
      name: name,
      root: raw['root'] is String ? raw['root'] as String : '',
      cmd: raw['cmd'] is String ? raw['cmd'] as String : 'shell',
      attached: raw['attached'] == true,
    );
  }
}

final _nameRe = RegExp(r'^[a-zA-Z0-9_.-]{1,64}$');

/// Tên phiên hợp lệ theo hợp đồng.
bool ideTermNameOk(String name) => _nameRe.hasMatch(name);

List<IdeTermItem> parseIdeTermItems(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [for (final e in items) ?IdeTermItem.tryParse(e)];
}

/// Máy SSH chọn được trong "Terminal mới".
final class IdeTermHost {
  const IdeTermHost({required this.alias, required this.label});
  final String alias;
  final String label;
}

final class IdeTermTargets {
  const IdeTermTargets({this.ssh = const [], this.mySsh = const []});
  final List<IdeTermHost> ssh;
  final List<IdeTermHost> mySsh;

  static IdeTermTargets parse(Object? data) {
    List<IdeTermHost> hosts(Object? raw) => [
      if (raw is List)
        for (final e in raw)
          if (e is Map &&
              e['alias'] is String &&
              (e['alias'] as String).isNotEmpty)
            IdeTermHost(
              alias: e['alias'] as String,
              label: e['label'] is String && (e['label'] as String).isNotEmpty
                  ? e['label'] as String
                  : e['alias'] as String,
            ),
    ];
    final map = data is Map ? data : const {};
    return IdeTermTargets(ssh: hosts(map['ssh']), mySsh: hosts(map['my_ssh']));
  }
}

/// Kiểu terminal mới (giá trị `cmd` gửi lên IDE).
enum IdeTermKind { shell, claude, codex, ssh, mySsh }

String ideTermCmd(IdeTermKind kind, [String alias = '']) => switch (kind) {
  IdeTermKind.shell => 'shell',
  IdeTermKind.claude => 'claude',
  IdeTermKind.codex => 'codex',
  IdeTermKind.ssh => 'ssh:$alias',
  IdeTermKind.mySsh => 'my-ssh:$alias',
};

/// Mở terminal có sẵn ([name]) hoặc tạo mới ([root] + [cmd]).
final class IdeTermOpenTarget {
  const IdeTermOpenTarget.existing(String this.name) : root = '', cmd = '';

  const IdeTermOpenTarget.create({required this.root, required this.cmd})
    : name = null;

  final String? name;
  final String root;
  final String cmd;

  Map<String, Object?> frame(int cols, int rows) => name != null
      ? {'type': 'term', 'name': name}
      : {
          'type': 'term',
          'new': {
            'root': root,
            'cmd': cmd,
            'cols': ideTermCols(cols),
            'rows': ideTermRows(rows),
          },
        };

  @override
  bool operator ==(Object other) =>
      other is IdeTermOpenTarget &&
      other.name == name &&
      other.root == root &&
      other.cmd == cmd;

  @override
  int get hashCode => Object.hash(name, root, cmd);
}

/// Giới hạn kích cỡ theo hợp đồng: cột 20–500, hàng 5–200.
int ideTermCols(int v) => v.clamp(20, 500);
int ideTermRows(int v) => v.clamp(5, 200);

/// Mỗi khung `tin` tối đa 64 KB (byte trước khi base64).
const ideTermMaxChunk = 64 * 1024;

/// Cắt [text] (UTF-8) thành các khối ≤ [max] byte, không cắt giữa một ký tự.
List<Uint8List> ideTermChunks(String text, {int max = ideTermMaxChunk}) {
  final bytes = utf8.encode(text);
  if (bytes.isEmpty) return const [];
  final out = <Uint8List>[];
  var start = 0;
  while (start < bytes.length) {
    var end = math.min(start + max, bytes.length);
    if (end < bytes.length) {
      // Lùi tới đầu ký tự (byte nối có dạng 10xxxxxx).
      while (end > start + 1 && (bytes[end] & 0xC0) == 0x80) {
        end--;
      }
    }
    out.add(Uint8List.fromList(bytes.sublist(start, end)));
    start = end;
  }
  return out;
}

/// Làm sạch chữ dán vào terminal: `\r\n` / `\r` thành `\n` (để hỏi lại khi
/// dán nhiều dòng, `\r` lẻ là Enter chạy lệnh ngay), bỏ ESC và mọi ký tự điều
/// khiển khác trừ `\t`, `\n` (chặn chuỗi `ESC[201~` thoát chế độ dán an toàn).
String ideTermCleanPaste(String text) {
  final s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final out = StringBuffer();
  for (final r in s.runes) {
    final control = r < 0x20 || r == 0x7f || (r >= 0x80 && r <= 0x9f);
    if (control && r != 0x09 && r != 0x0a) continue;
    out.writeCharCode(r);
  }
  return out.toString();
}

/// Giải mã UTF-8 theo từng khối: byte của một ký tự bị cắt giữa hai khung
/// `tout` được giữ lại và ghép với khung sau. Byte sai thành U+FFFD.
final class IdeTermUtf8Decoder {
  IdeTermUtf8Decoder() {
    _input = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(_out));
  }

  final _out = StringBuffer();
  late final ByteConversionSink _input;

  String decode(List<int> bytes) {
    _input.add(bytes);
    final text = _out.toString();
    _out.clear();
    return text;
  }
}

/// Byte gửi cho phím phụ / phím bổ trợ. Thuần dữ liệu, không phụ thuộc xterm.
abstract final class IdeTermKeys {
  static const esc = '\x1b';
  static const tab = '\t';

  /// `appCursor`: chương trình bật chế độ con trỏ ứng dụng (ESC O A...).
  static String arrow(String dir, {bool appCursor = false, int mod = 1}) {
    final c = switch (dir) {
      'up' => 'A',
      'down' => 'B',
      'right' => 'C',
      _ => 'D',
    };
    if (mod > 1) return '$esc[1;$mod$c';
    return appCursor ? '${esc}O$c' : '$esc[$c';
  }

  static String home({bool appCursor = false, int mod = 1}) =>
      mod > 1 ? '$esc[1;${mod}H' : (appCursor ? '${esc}OH' : '$esc[H');

  static String end({bool appCursor = false, int mod = 1}) =>
      mod > 1 ? '$esc[1;${mod}F' : (appCursor ? '${esc}OF' : '$esc[F');

  static String pageUp({int mod = 1}) => mod > 1 ? '$esc[5;$mod~' : '$esc[5~';

  static String pageDown({int mod = 1}) => mod > 1 ? '$esc[6;$mod~' : '$esc[6~';

  /// Mã điều khiển của [ch] (a-z, `@ [ \ ] ^ _`, `?` = DEL); `null` nếu
  /// không có.
  static String? ctrl(String ch) {
    if (ch.length != 1) return null;
    final c = ch.codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x60);
    if (c >= 0x40 && c <= 0x5f) return String.fromCharCode(c - 0x40);
    if (c == 0x3f) return '\x7f';
    if (c == 0x20) return '\x00';
    return null;
  }
}

/// Giữ trạng thái Ctrl / Alt dính của hàng phím phụ. Bấm Ctrl rồi gõ một chữ
/// thì chữ đó thành mã điều khiển, sau đó Ctrl tự nhả.
class IdeTermModifiers {
  bool ctrl = false;
  bool alt = false;

  /// 1 + (shift 1) + (alt 2) + (ctrl 4) theo xterm.
  int get mod => 1 + (alt ? 2 : 0) + (ctrl ? 4 : 0);

  void clear() {
    ctrl = false;
    alt = false;
  }

  /// Văn bản gõ từ bàn phím mềm: áp dụng Ctrl / Alt dính lên ký tự đầu rồi nhả.
  /// Chuỗi dài (dán, gợi ý của bàn phím) và chuỗi điều khiển đi nguyên.
  String applyTyped(String text) {
    if (!ctrl && !alt) return text;
    if (text.isEmpty || text.runes.length != 1) return text;
    var out = text;
    if (ctrl) {
      final c = IdeTermKeys.ctrl(text);
      if (c != null) out = c;
    }
    if (alt) out = '${IdeTermKeys.esc}$out';
    clear();
    return out;
  }

  /// Phím phụ có mã cố định [seq]: Alt thêm ESC phía trước ký tự thường; mũi
  /// tên / Home / End dùng dạng có `mod`. Dùng [build] để dựng theo `mod`.
  String applyKey(String Function(int mod) build) {
    final out = build(mod);
    clear();
    return out;
  }

  /// Ký tự đơn của hàng phím (`|`, `~`, `/`, `-`): Ctrl / Alt áp như gõ tay.
  String applyChar(String ch) => applyTyped(ch);
}

/// IDE báo rõ `features.terminal == false` (quản trị tắt trên điện thoại).
/// Thiếu khoá thì coi như bật (IDE cũ không có cờ).
bool ideTermDisabled(IdeReady? ready) => ready?.features['terminal'] == false;
