import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/qr_login_use_cases.dart';
import '../../domain/entities/qr_login.dart';

enum QrLoginPhase {
  /// Chờ quét mã.
  idle,

  /// Đang gửi `/scan`.
  checking,

  /// Hiện thông tin máy tính, chờ Đồng ý / Từ chối.
  confirm,

  /// Đang gửi `/approve` hoặc `/reject`.
  deciding,
  approved,
  rejected,
  error,
}

final class QrLoginState {
  const QrLoginState({
    this.phase = QrLoginPhase.idle,
    this.payload,
    this.scan,
    this.errorMessage,
  });

  final QrLoginPhase phase;
  final QrLoginPayload? payload;
  final QrLoginScan? scan;
  final String? errorMessage;

  bool get isBusy =>
      phase == QrLoginPhase.checking || phase == QrLoginPhase.deciding;
}

/// Điện thoại (đã đăng nhập) duyệt đăng nhập cho máy tính bằng mã QR.
/// Mã sai định dạng / sai máy chủ bị chặn trước khi gửi bất cứ gì.
final class QrLoginController extends StateNotifier<QrLoginState> {
  QrLoginController({
    required Result<QrLoginPayload> Function(String raw) readPayload,
    required Future<Result<QrLoginScan>> Function(QrLoginPayload payload) scan,
    required Future<Result<String>> Function(
      QrLoginPayload payload, {
      required bool approve,
    })
    decide,
  }) : _readPayload = readPayload,
       _scan = scan,
       _decide = decide,
       super(const QrLoginState());

  final Result<QrLoginPayload> Function(String raw) _readPayload;
  final Future<Result<QrLoginScan>> Function(QrLoginPayload payload) _scan;
  final Future<Result<String>> Function(
    QrLoginPayload payload, {
    required bool approve,
  })
  _decide;

  Future<void> submitScannedValue(String raw) async {
    if (state.isBusy) return;
    final parsed = _readPayload(raw);
    switch (parsed) {
      case FailureResult<QrLoginPayload>(:final failure):
        state = QrLoginState(
          phase: QrLoginPhase.error,
          errorMessage: failure.message,
        );
        return;
      case Success<QrLoginPayload>(value: final payload):
        state = QrLoginState(phase: QrLoginPhase.checking, payload: payload);
        final result = await _scan(payload);
        if (!mounted) return;
        switch (result) {
          case Success<QrLoginScan>(value: final scan):
            state = QrLoginState(
              phase: QrLoginPhase.confirm,
              payload: payload,
              scan: scan,
            );
          case FailureResult<QrLoginScan>(:final failure):
            state = QrLoginState(
              phase: QrLoginPhase.error,
              errorMessage: qrLoginFailureMessage(failure),
            );
        }
    }
  }

  Future<void> decide({required bool approve}) async {
    final payload = state.payload;
    if (state.phase != QrLoginPhase.confirm || payload == null) return;
    state = QrLoginState(
      phase: QrLoginPhase.deciding,
      payload: payload,
      scan: state.scan,
    );
    final result = await _decide(payload, approve: approve);
    if (!mounted) return;
    switch (result) {
      case Success<String>(value: final status):
        state = QrLoginState(
          phase: status == 'rejected' || !approve
              ? QrLoginPhase.rejected
              : QrLoginPhase.approved,
          scan: state.scan,
        );
      case FailureResult<String>(:final failure):
        state = QrLoginState(
          phase: QrLoginPhase.error,
          errorMessage: qrLoginFailureMessage(failure),
        );
    }
  }

  /// Quét lại mã khác: bỏ hết dữ liệu mã cũ (kể cả `secret`).
  void reset() {
    if (state.isBusy) return;
    state = const QrLoginState();
  }
}

final qrLoginControllerProvider =
    StateNotifierProvider.autoDispose<QrLoginController, QrLoginState>((ref) {
      return QrLoginController(
        readPayload: (raw) =>
            ref.read(readQrLoginPayloadUseCaseProvider).execute(raw),
        scan: (payload) =>
            ref.read(scanQrLoginUseCaseProvider).execute(payload),
        decide: (payload, {required approve}) => ref
            .read(decideQrLoginUseCaseProvider)
            .execute(payload, approve: approve),
      );
    });
