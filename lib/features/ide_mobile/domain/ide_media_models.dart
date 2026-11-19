import 'dart:convert';
import 'dart:typed_data';

import 'ide_session_state.dart';

/// Mô hình Màn hình app (`appscreen.*`) và Studio video (`video.*`), Phụ lục C3.
/// Mọi giá trị từ IDE đều được kiểm: sai kiểu / vô lý thì bỏ hoặc đổi về mặc định.

/// Trần ảnh khung Màn hình app sau khi giải mã (1 MB).
const ideFrameMaxBytes = 1024 * 1024;

/// Ảnh cảnh ≤ 8 MB, video ≤ 150 MB (lớn hơn: "Mở trên máy tính").
const ideVideoImageMaxBytes = 8 * 1024 * 1024;
const ideVideoFileMaxBytes = 150 * 1024 * 1024;

/// Số hữu hạn, không âm, không quá [max]; ngoài ra `null` (hiện "—").
num? ideMediaNum(Object? v, {num max = 1e9}) {
  if (v is! num || !v.isFinite || v < 0 || v > max) return null;
  return v;
}

int? ideMediaInt(Object? v, {int max = 1000000000}) {
  final n = ideMediaNum(v, max: max);
  return n?.toInt();
}

String _str(Object? v, [int max = 400]) {
  if (v is! String) return '';
  return v.length > max ? v.substring(0, max) : v;
}

/// Thời lượng `m:ss` (hoặc `h:mm:ss`); không hợp lệ → "—".
String ideMediaDuration(Object? seconds) {
  final n = ideMediaNum(seconds, max: 86400 * 10);
  if (n == null) return '—';
  final s = n.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

// ---------------------------------------------------------------- Màn hình app

final class IdeAppCheck {
  const IdeAppCheck({required this.run});

  /// `false`: máy IDE chưa cài công cụ ("nhờ quản trị").
  final bool run;

  static IdeAppCheck parse(Object? raw) =>
      IdeAppCheck(run: raw is Map && raw['run'] == true);
}

final class IdeAppDevice {
  const IdeAppDevice({
    required this.key,
    required this.label,
    required this.platform,
  });

  final String key;
  final String label;
  final String platform;
}

final class IdeAppSession {
  const IdeAppSession({
    required this.project,
    required this.status,
    required this.device,
    required this.dark,
  });

  /// TÊN dự án (không phải đường dẫn).
  final String project;

  /// `starting` | `running`.
  final String status;
  final String device;
  final bool dark;

  bool get starting => status == 'starting';
}

final class IdeAppStatus {
  const IdeAppStatus({
    this.sessions = const [],
    this.max = 2,
    this.devices = const [],
  });

  final List<IdeAppSession> sessions;
  final int max;
  final List<IdeAppDevice> devices;

  /// Phiên của dự án [name] (`my:` ở đầu tên được bỏ khi so).
  IdeAppSession? sessionOf(String name) {
    String bare(String s) => s.startsWith('my:') ? s.substring(3) : s;
    for (final s in sessions) {
      if (s.project == name || bare(s.project) == bare(name)) return s;
    }
    return null;
  }

  static IdeAppStatus parse(Object? raw) {
    if (raw is! Map) return const IdeAppStatus();
    final sessions = <IdeAppSession>[];
    final rs = raw['sessions'];
    if (rs is List) {
      for (final e in rs.take(20)) {
        if (e is! Map) continue;
        final p = _str(e['project'], 200);
        if (p.isEmpty) continue;
        final st = e['status'] == 'starting' ? 'starting' : 'running';
        sessions.add(
          IdeAppSession(
            project: p,
            status: st,
            device: _str(e['device'], 40),
            dark: e['dark'] == true,
          ),
        );
      }
    }
    final devices = <IdeAppDevice>[];
    final rd = raw['devices'];
    if (rd is Map) {
      for (final e in rd.entries.take(40)) {
        final k = e.key;
        final v = e.value;
        if (k is! String || k.isEmpty || k.length > 40 || v is! Map) continue;
        final label = _str(v['label'], 80);
        devices.add(
          IdeAppDevice(
            key: k,
            label: label.isEmpty ? k : label,
            platform: _str(v['platform'], 20),
          ),
        );
      }
    }
    return IdeAppStatus(
      sessions: sessions,
      max: ideMediaInt(raw['max'], max: 100) ?? 2,
      devices: devices,
    );
  }
}

/// Một khung ảnh PNG đã giải mã và kiểm.
final class IdeAppFrame {
  const IdeAppFrame({required this.w, required this.h, required this.bytes});

  final int w;
  final int h;
  final Uint8List bytes;

  double get aspect => w / h;

  /// `null` khi sai mime / `w`,`h` vô lý / base64 hỏng / ảnh quá 1 MB / không
  /// phải PNG: người gọi bỏ khung này và giữ khung cũ.
  static IdeAppFrame? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final w = ideMediaInt(raw['w'], max: 20000);
    final h = ideMediaInt(raw['h'], max: 20000);
    if (w == null || h == null || w < 1 || h < 1) return null;
    if (raw['mime'] != 'image/png') return null;
    final data = raw['data'];
    // base64 của 1 MB dài tối đa ~1,4 triệu ký tự: chặn trước khi giải mã.
    if (data is! String || data.isEmpty || data.length > 1400000) return null;
    final Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      return null;
    }
    if (bytes.length < 8 || bytes.length > ideFrameMaxBytes) return null;
    const sig = [0x89, 0x50, 0x4E, 0x47];
    for (var i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return null;
    }
    return IdeAppFrame(w: w, h: h, bytes: bytes);
  }
}

// ---------------------------------------------------------------- Studio video

/// Tiến trình đang chạy của một video.
final class IdeVideoProgress {
  const IdeVideoProgress({
    required this.step,
    required this.done,
    required this.total,
    required this.note,
    required this.state,
    required this.error,
  });

  final String step;
  final int? done;
  final int? total;
  final String note;

  /// `running` | `done` | `error` | `interrupted` (khác: coi như `done`).
  final String state;
  final String error;

  bool get running => state == 'running';

  /// 0..1 khi biết cả hai số; ngược lại `null` (thanh không xác định).
  double? get fraction {
    final d = done;
    final t = total;
    if (d == null || t == null || t <= 0) return null;
    return (d / t).clamp(0, 1).toDouble();
  }

  static IdeVideoProgress? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final st = raw['state'];
    return IdeVideoProgress(
      step: _str(raw['step'], 80),
      done: ideMediaInt(raw['done']),
      total: ideMediaInt(raw['total']),
      note: _str(raw['note'], 200),
      state: st is String && st.length <= 20 ? st : 'done',
      error: _str(raw['error'], 300),
    );
  }
}

/// Đường dẫn trong `data` là tương đối so với `root`: kiểm trước khi ghép.
/// Bỏ khi rỗng, bắt đầu `/` hay `\`, ổ đĩa (`C:`), có `..`, ký tự điều khiển
/// hoặc ký tự định dạng vô hình.
String? ideMediaSafeRelPath(Object? raw) {
  if (raw is! String || raw.isEmpty || raw.length > 400) return null;
  if (raw.startsWith('/') || raw.startsWith('\\') || raw.startsWith('~')) {
    return null;
  }
  if (raw.contains('..') || raw.contains('\\')) return null;
  if (RegExp(r'^[A-Za-z]:').hasMatch(raw)) return null;
  if (RegExp(
    r'[\u0000-\u001f\u007f-\u009f  ]|\p{Cf}',
    unicode: true,
  ).hasMatch(raw)) {
    return null;
  }
  return raw;
}

/// `<root>/<tương đối>` hoặc `null` nếu đường dẫn không an toàn.
String? ideMediaJoin(String root, Object? rel) {
  final r = ideMediaSafeRelPath(rel);
  if (r == null || root.isEmpty) return null;
  final base = root.endsWith('/') ? root.substring(0, root.length - 1) : root;
  return '$base/$r';
}

final class IdeVideoRow {
  const IdeVideoRow({
    required this.slug,
    required this.title,
    required this.ratio,
    required this.scenes,
    required this.seconds,
    required this.state,
    required this.error,
    required this.video,
    required this.draft,
    required this.cover,
    required this.status,
  });

  final String slug;
  final String title;
  final String ratio;
  final int? scenes;
  final num? seconds;

  /// `da-xuat` | `nhap` | `kich-ban` | `loi`; lạ giữ nguyên.
  final String state;
  final String error;
  final String? video;
  final String? draft;
  final String? cover;
  final IdeVideoProgress? status;

  bool get running => status?.running ?? false;

  static IdeVideoRow? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'];
    if (slug is! String || !RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(slug)) {
      return null;
    }
    if (slug.contains('..')) return null;
    final title = _str(raw['title'], 200);
    return IdeVideoRow(
      slug: slug,
      title: title.isEmpty ? slug : title,
      ratio: _str(raw['ratio'], 12),
      scenes: ideMediaInt(raw['scenes']),
      seconds: ideMediaNum(raw['seconds'], max: 86400 * 10),
      state: _str(raw['state'], 20),
      error: _str(raw['error'], 300),
      video: ideMediaSafeRelPath(raw['video']),
      draft: ideMediaSafeRelPath(raw['draft']),
      cover: ideMediaSafeRelPath(raw['cover']),
      status: IdeVideoProgress.tryParse(raw['status']),
    );
  }
}

List<IdeVideoRow> ideParseVideoList(Object? raw) {
  final out = <IdeVideoRow>[];
  final list = raw is Map ? raw['videos'] : null;
  if (list is List) {
    for (final e in list.take(500)) {
      final r = IdeVideoRow.tryParse(e);
      if (r != null) out.add(r);
    }
  }
  return out;
}

final class IdeVideoScene {
  const IdeVideoScene({
    required this.n,
    required this.text,
    required this.caption,
    required this.image,
    required this.kind,
  });

  final int n;
  final String text;
  final String caption;

  /// Đường dẫn ảnh tương đối đã kiểm; `null` khi không có / không an toàn.
  final String? image;
  final String kind;
}

final class IdeVideoDetail {
  const IdeVideoDetail({
    required this.video,
    required this.scenes,
    required this.error,
  });

  final IdeVideoRow video;
  final List<IdeVideoScene> scenes;
  final String error;

  static IdeVideoDetail? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final row = IdeVideoRow.tryParse(raw['video']);
    if (row == null) return null;
    final scenes = <IdeVideoScene>[];
    final rs = raw['scenes'];
    if (rs is List) {
      var i = 0;
      for (final e in rs.take(1000)) {
        i++;
        if (e is! Map) continue;
        scenes.add(
          IdeVideoScene(
            n: ideJsonInt(e['n']) ?? i,
            text: _str(e['text'], 2000),
            caption: _str(e['caption'], 1000),
            image: ideMediaSafeRelPath(e['image']),
            kind: _str(e['kind'], 12),
          ),
        );
      }
    }
    final files = raw['files'];
    final err = _str(raw['error'], 300);
    // Ưu tiên đường dẫn trong `files` (chính thức) khi dòng không có.
    final fv = files is Map ? ideMediaSafeRelPath(files['video']) : null;
    final fd = files is Map ? ideMediaSafeRelPath(files['draft']) : null;
    final fc = files is Map ? ideMediaSafeRelPath(files['cover']) : null;
    return IdeVideoDetail(
      video: IdeVideoRow(
        slug: row.slug,
        title: row.title,
        ratio: row.ratio,
        scenes: row.scenes,
        seconds: row.seconds,
        state: row.state,
        error: row.error,
        video: row.video ?? fv,
        draft: row.draft ?? fd,
        cover: row.cover ?? fc,
        status: row.status,
      ),
      scenes: err.isEmpty ? scenes : const [],
      error: err,
    );
  }
}
