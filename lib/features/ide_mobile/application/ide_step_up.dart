import 'dart:async';
import 'dart:convert';

import '../data/ide_rpc_client.dart';
import '../domain/ide_canonical_json.dart';
import '../domain/ide_device_security.dart';
import '../domain/ide_errors.dart';

/// Bảng tóm tắt hiện cho người dùng trước khi ký.
final class IdeStepSummary {
  const IdeStepSummary({
    required this.summary,
    required this.op,
    this.target = '',
  });

  /// Lời tóm tắt do IDE gửi (không tin: phải lọc trước khi hiện).
  final String summary;
  final String op;

  /// Đối tượng của thao tác, lấy từ tham số app gửi (phần được ký).
  final String target;
}

/// Khoá tham số chỉ đối tượng thao tác, theo thứ tự ưu tiên.
const _targetKeys = ['name', 'device_id', 'project', 'server', 'path', 'id'];

/// Thao tác tệp: đối tượng là đường dẫn bị tác động (không phải tên mới).
const _fileTargetKeys = ['path', 'root', 'id'];

/// Đối tượng thao tác từ tham số của chính app (vd tên máy chủ, mã điện thoại).
/// Đổi tên / chuyển / chép tệp thì ghi cả đích: `nguồn → đích`.
String ideStepTarget(Object? args, [String op = '']) {
  if (args is! Map) return '';
  String pick(List<String> keys) {
    for (final k in keys) {
      final v = args[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  if (!op.startsWith('files.')) return pick(_targetKeys);
  final source = pick(_fileTargetKeys);
  final dest = switch (op) {
    'files.rename' => pick(const ['name']),
    'files.move' || 'files.copy' => pick(const ['dest_dir']),
    _ => '',
  };
  if (dest.isEmpty) return source;
  return source.isEmpty ? dest : '$source → $dest';
}

/// Hiện bảng tóm tắt, trả `true` nếu người dùng bấm xác nhận.
typedef IdeStepPresenter = Future<bool> Function(IdeStepSummary summary);

/// `need_step` -> bảng tóm tắt -> chuỗi ký (hợp đồng mục 5) -> hộp vân tay của
/// máy ký bằng khoá P-256 -> chữ ký để gửi `step`. `null` = huỷ (gửi `cancel`).
final class IdeStepUp {
  IdeStepUp({
    required IdeDeviceSecurity security,
    required IdeStepPresenter present,
    required String Function() alias,
  }) : _security = security,
       _present = present,
       _alias = alias;

  final IdeDeviceSecurity _security;
  final IdeStepPresenter _present;
  final String Function() _alias;

  /// Hàng chờ dùng chung mọi nguồn (RPC client, các phiên AI): mỗi lúc chỉ một
  /// bảng tóm tắt / hộp vân tay.
  static Future<void> _tail = Future<void>.value();

  /// Dùng làm [IdeStepHandler] của `IdeRpcClient`.
  Future<String?> confirm(IdeStepRequest request) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous
        .then((_) => _confirmNow(request))
        .whenComplete(done.complete);
  }

  Future<String?> _confirmNow(IdeStepRequest request) async {
    final accepted = await _present(
      IdeStepSummary(
        summary: request.summary,
        op: request.op,
        target: ideStepTarget(request.args, request.op),
      ),
    );
    if (!accepted) return null;
    final String text;
    try {
      text = ideStepSigningString(
        stream: request.stream,
        req: request.req,
        challenge: request.challenge,
        op: request.op,
        args: request.args,
      );
    } on ArgumentError {
      throw const IdeStepFailed();
    }
    try {
      return await _security.signWithStepKey(
        alias: _alias(),
        data: utf8.encode(text),
        reason: request.summary.isEmpty
            ? request.op
            : '${request.summary} (${request.op})',
      );
    } on StepKeyException catch (error) {
      if (error.cancelled) return null;
      throw const IdeStepFailed();
    }
  }
}
