/// Mã QR gắn máy: `webtui-ide-pair:v1:<uuid>:<26 ký tự base32 A-Z2-7>`.
final class IdePairCode {
  const IdePairCode({required this.instanceId, required this.code});

  final String instanceId;
  final String code;

  static final _pattern = RegExp(
    r'^webtui-ide-pair:v1:'
    r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    r':([A-Z2-7]{26})$',
  );

  /// Trả `null` khi sai định dạng (không cắt khoảng trắng, không đoán).
  static IdePairCode? tryParse(String raw) {
    final match = _pattern.firstMatch(raw);
    if (match == null) return null;
    return IdePairCode(
      instanceId: match.group(1)!.toLowerCase(),
      code: match.group(2)!,
    );
  }
}
