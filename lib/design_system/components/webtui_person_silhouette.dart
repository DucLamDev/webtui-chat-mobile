import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';

/// Giới tính dùng để chọn hình người mặc định khi chưa có ảnh đại diện.
/// Giá trị thiếu hoặc không nhận ra được coi là trung tính.
enum WebTuiAvatarGender {
  male,
  female,
  neutral;

  /// Đọc giá trị máy chủ (`male`, `female`, `unspecified`, thiếu).
  static WebTuiAvatarGender parse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'male' => WebTuiAvatarGender.male,
      'female' => WebTuiAvatarGender.female,
      _ => WebTuiAvatarGender.neutral,
    };
  }
}

const _malePaths = <String>[
  'M33.5 37.5c0-11.6 7.4-19.5 16.5-19.5s16.5 7.9 16.5 19.5c0 10.6-7.4 20.5-16.5 20.5s-16.5-9.9-16.5-20.5z',
  'M43 55h14v10H43z',
  'M12 100c0-20.5 15-34 32-35h12c17 1 32 14.5 32 35z',
];

const _femalePaths = <String>[
  'M50 15.5c-12.4 0-21.5 10.6-21.5 26.5 0 7.6-1.4 15.5-5 22.5 4.6 4 10.4 5.5 16 5.5h21c5.6 0 11.4-1.5 16-5.5-3.6-7-5-14.9-5-22.5 0-15.9-9.1-26.5-21.5-26.5z',
  'M20 100c0-18.2 13.6-30.5 30-30.5s30 12.3 30 30.5z',
];

const _neutralPaths = <String>['M17 100c0-21 14.8-35 33-35s33 14 33 35z'];

/// Đổi chuỗi path SVG tối giản (M, c, s, h, v, H, V, L, z; chữ thường là toạ độ
/// tương đối) sang [Path].
Path webTuiPathFromSvg(String data) {
  final tokens = RegExp(
    r'[a-zA-Z]|-?\d*\.?\d+',
  ).allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var x = 0.0;
  var y = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  // Điểm điều khiển thứ hai của lệnh cong trước đó (cho `s`).
  double? lastCx;
  double? lastCy;
  String? cmd;
  double n() => double.parse(tokens[i++]);
  bool isCommand(String t) => RegExp(r'^[a-zA-Z]$').hasMatch(t);
  while (i < tokens.length) {
    if (isCommand(tokens[i])) cmd = tokens[i++];
    final c = cmd;
    if (c == null) break;
    switch (c) {
      case 'M':
      case 'm':
        final dx = n();
        final dy = n();
        x = c == 'm' ? x + dx : dx;
        y = c == 'm' ? y + dy : dy;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cmd = c == 'm' ? 'l' : 'L';
        lastCx = null;
      case 'L':
      case 'l':
        final dx = n();
        final dy = n();
        x = c == 'l' ? x + dx : dx;
        y = c == 'l' ? y + dy : dy;
        path.lineTo(x, y);
        lastCx = null;
      case 'H':
      case 'h':
        final v = n();
        x = c == 'h' ? x + v : v;
        path.lineTo(x, y);
        lastCx = null;
      case 'V':
      case 'v':
        final v = n();
        y = c == 'v' ? y + v : v;
        path.lineTo(x, y);
        lastCx = null;
      case 'C':
      case 'c':
        final rel = c == 'c';
        final x1 = n() + (rel ? x : 0);
        final y1 = n() + (rel ? y : 0);
        final x2 = n() + (rel ? x : 0);
        final y2 = n() + (rel ? y : 0);
        final ex = n() + (rel ? x : 0);
        final ey = n() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        lastCx = x2;
        lastCy = y2;
        x = ex;
        y = ey;
      case 'S':
      case 's':
        final rel = c == 's';
        final x1 = lastCx == null ? x : 2 * x - lastCx;
        final y1 = lastCy == null || lastCx == null ? y : 2 * y - lastCy;
        final x2 = n() + (rel ? x : 0);
        final y2 = n() + (rel ? y : 0);
        final ex = n() + (rel ? x : 0);
        final ey = n() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        lastCx = x2;
        lastCy = y2;
        x = ex;
        y = ey;
      case 'Z':
      case 'z':
        path.close();
        x = startX;
        y = startY;
        lastCx = null;
        cmd = null;
      default:
        throw FormatException('Lệnh path không hỗ trợ: $c');
    }
  }
  return path;
}

final _silhouetteCache = <WebTuiAvatarGender, List<Path>>{};

List<Path> _silhouettePaths(WebTuiAvatarGender gender) {
  return _silhouetteCache.putIfAbsent(gender, () {
    final paths = switch (gender) {
      WebTuiAvatarGender.male => _malePaths,
      WebTuiAvatarGender.female => _femalePaths,
      WebTuiAvatarGender.neutral => _neutralPaths,
    };
    final result = paths.map(webTuiPathFromSvg).toList();
    if (gender == WebTuiAvatarGender.neutral) {
      result.insert(
        0,
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(50, 39), radius: 17)),
      );
    }
    return result;
  });
}

/// Hình người xám kiểu mạng xã hội: nền kín + hình theo giới tính, hệ toạ độ
/// 100x100 co theo khung. Việc cắt tròn / bo góc do widget cha làm.
class WebTuiPersonSilhouette extends StatelessWidget {
  const WebTuiPersonSilhouette({required this.gender, super.key});

  final WebTuiAvatarGender gender;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    return CustomPaint(
      painter: WebTuiPersonSilhouettePainter(
        gender: gender,
        background: dark ? const Color(0xFF2A3546) : const Color(0xFFE4E6EB),
        figure: dark ? const Color(0xFF5D6B80) : const Color(0xFFBCC0C4),
      ),
      size: Size.infinite,
    );
  }
}

class WebTuiPersonSilhouettePainter extends CustomPainter {
  const WebTuiPersonSilhouettePainter({
    required this.gender,
    required this.background,
    required this.figure,
  });

  final WebTuiAvatarGender gender;
  final Color background;
  final Color figure;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final paint = Paint()
      ..color = figure
      ..isAntiAlias = true;
    for (final path in _silhouettePaths(gender)) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WebTuiPersonSilhouettePainter old) {
    return old.gender != gender ||
        old.background != background ||
        old.figure != figure;
  }
}
