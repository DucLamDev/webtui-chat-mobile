import 'dart:math';

/// Thông tin máy đã gắn IDE (cất trong kho bảo mật của máy).
final class IdeDeviceCredentials {
  const IdeDeviceCredentials({
    required this.instanceId,
    required this.chatUserId,
    required this.deviceId,
    required this.seed,
    this.serverScope = '',
    this.stepAlias = '',
  });

  /// Tên khoá xác nhận mới cho một lần gắn: mỗi lần gắn một khoá riêng, nên
  /// gắn lại (kể cả bị từ chối / hết hạn) không đè khoá của lần gắn đang dùng.
  static String newStepKeyAlias(String instanceId, {Random? random}) {
    final rng = random ?? Random.secure();
    final suffix = List.generate(
      8,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'webtui-ide-step-$instanceId-$suffix';
  }

  /// UUID của IDE (lấy từ mã QR).
  final String instanceId;
  final String chatUserId;

  /// `d_…` do IDE cấp khi bấm Xác nhận.
  final String deviceId;

  /// Hạt giống Ed25519 (32 byte) base64. Không bao giờ rời máy.
  final String seed;

  /// Định danh máy chủ chat đã gắn (khác máy chủ → coi như chưa gắn).
  final String serverScope;

  /// Tên khoá xác nhận lúc gắn (bản ghi cũ chưa có thì theo tên cũ).
  final String stepAlias;

  /// Tên khoá xác nhận trong chip bảo mật của máy.
  String get stepKeyAlias =>
      stepAlias.isNotEmpty ? stepAlias : 'webtui-ide-step-$instanceId';

  Map<String, Object?> toJson() => {
    'instanceId': instanceId,
    'chatUserId': chatUserId,
    'deviceId': deviceId,
    'seed': seed,
    'serverScope': serverScope,
    'stepAlias': stepAlias,
  };

  static IdeDeviceCredentials? fromJson(Object? json) {
    if (json is! Map) return null;
    String text(String key) {
      final v = json[key];
      return v is String ? v : '';
    }

    final creds = IdeDeviceCredentials(
      instanceId: text('instanceId'),
      chatUserId: text('chatUserId'),
      deviceId: text('deviceId'),
      seed: text('seed'),
      serverScope: text('serverScope'),
      stepAlias: text('stepAlias'),
    );
    if (creds.instanceId.isEmpty ||
        creds.chatUserId.isEmpty ||
        creds.deviceId.isEmpty ||
        creds.seed.isEmpty) {
      return null;
    }
    return creds;
  }
}
