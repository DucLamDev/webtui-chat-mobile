import '../../../domain/ide_session_state.dart' show ideJsonInt;

/// Đọc mềm JSON của state phiên AI (thiếu khoá / sai kiểu thì trả rỗng).
String aiStr(Object? v) => v is String ? v : '';

int aiInt(Object? v) => ideJsonInt(v) ?? 0;

bool aiBool(Object? v) => v == true;

Map<String, Object?> aiMap(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : const {};

List<Map<String, Object?>> aiList(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, Object?>.from(e),
      ]
    : const [];

/// Tên cuối của đường dẫn.
String aiBaseName(String path) {
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final i = trimmed.lastIndexOf('/');
  return i < 0 ? trimmed : trimmed.substring(i + 1);
}
