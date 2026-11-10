import 'dart:async';

import '../../../core/error/failure.dart';
import '../data/meeting_remote_data_source.dart';
import '../domain/meeting_models.dart';

enum GroupCallChoice { accept, decline, timedOut }

/// Phần giao diện / hệ điều hành của cuộc gọi nhóm, tách khỏi luồng nghiệp vụ.
abstract interface class GroupCallPresenter {
  /// Hiện chuông trong app. Trả về lựa chọn của người dùng, hoặc `null` khi
  /// chuông bị tắt từ xa ([dismissRinging]).
  Future<GroupCallChoice?> showRinging(GroupCall call);

  /// Tắt chuông trong app và giao diện cuộc gọi gốc (CallKit / thông báo)
  /// của [groupCallId] mà không báo gì lên máy chủ.
  Future<void> dismissRinging(String groupCallId);

  /// Vào họp sau khi nhận.
  Future<void> openMeeting(GroupCall call, MeetingJoinInfo join);

  void showError(String message);
}

/// Điều phối cuộc gọi nhóm đến: chuông, nhận, từ chối, tắt chuông.
final class GroupCallCoordinator {
  GroupCallCoordinator({
    required MeetingApi api,
    required GroupCallPresenter presenter,
    String? Function()? currentUserId,
  }) : _api = api,
       _presenter = presenter,
       _currentUserId = currentUserId;

  final MeetingApi _api;
  final GroupCallPresenter _presenter;
  final String? Function()? _currentUserId;
  final _ringing = <String>{};
  final _accepting = <String>{};

  bool isRinging(String groupCallId) => _ringing.contains(groupCallId);

  /// `GroupCallStarted` hoặc push `group_call_invite`.
  Future<void> handleStarted(GroupCall call) async {
    if (call.id.isEmpty ||
        !call.isRinging ||
        _ringing.contains(call.id) ||
        _accepting.contains(call.id)) {
      return;
    }
    final self = _currentUserId?.call();
    if (self != null && self.isNotEmpty && call.startedBy == self) return;
    _ringing.add(call.id);
    final GroupCallChoice? choice;
    try {
      choice = await _presenter.showRinging(call);
    } finally {
      _ringing.remove(call.id);
    }
    switch (choice) {
      case GroupCallChoice.accept:
        await accept(call);
      case GroupCallChoice.decline:
        await decline(call);
      case GroupCallChoice.timedOut || null:
        // Máy chủ tự dừng chuông sau hết giờ; chỉ cần tắt giao diện gốc.
        await _presenter.dismissRinging(call.id);
    }
  }

  /// `GroupCallRingStopped`, `GroupCallEnded` hoặc push `group_call_cancel`.
  Future<void> handleStopped(String groupCallId) async {
    final id = groupCallId.trim();
    if (id.isEmpty || _accepting.contains(id)) return;
    await _presenter.dismissRinging(id);
  }

  /// Nhận cuộc gọi: lấy token rồi vào họp. Trả `true` khi đã xử lý xong (kể cả
  /// cuộc gọi đã kết thúc), `false` khi nên thử lại (mất mạng, lỗi máy chủ).
  Future<bool> accept(GroupCall call) async {
    if (!_accepting.add(call.id)) return false;
    try {
      final acceptance = await _api.acceptGroupCall(
        workspaceId: call.workspaceId,
        channelId: call.channelId,
        groupCallId: call.id,
      );
      // Đã nhận ở máy này: tắt chuông còn lại (chuông gốc, hộp thoại).
      await _presenter.dismissRinging(call.id);
      await _presenter.openMeeting(acceptance.call ?? call, acceptance.join);
      return true;
    } on Failure catch (failure) {
      _presenter.showError(failure.message);
      if (_isFinal(failure)) {
        await _presenter.dismissRinging(call.id);
        return true;
      }
      return false;
    } finally {
      _accepting.remove(call.id);
    }
  }

  /// Từ chối: máy chủ ngừng đổ chuông mọi máy của người này.
  Future<bool> decline(GroupCall call) async {
    await _presenter.dismissRinging(call.id);
    try {
      await _api.declineGroupCall(
        workspaceId: call.workspaceId,
        channelId: call.channelId,
        groupCallId: call.id,
      );
      return true;
    } on Failure catch (failure) {
      return _isFinal(failure);
    }
  }

  bool _isFinal(Failure failure) =>
      failure.kind == FailureKind.notFound ||
      failure.kind == FailureKind.conflict ||
      failure.kind == FailureKind.forbidden ||
      failure.kind == FailureKind.validation;
}
