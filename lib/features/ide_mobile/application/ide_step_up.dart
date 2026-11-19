import 'dart:async';
import 'dart:convert';

import '../data/ide_rpc_client.dart';
import '../domain/ide_canonical_json.dart';
import '../domain/ide_device_security.dart';
import '../domain/ide_errors.dart';

/// Bảng tóm tắt hiện cho người dùng trước khi ký.
final class IdeStepSummary {
  const IdeStepSummary({required this.summary, required this.op});

  final String summary;
  final String op;
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
      IdeStepSummary(summary: request.summary, op: request.op),
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
