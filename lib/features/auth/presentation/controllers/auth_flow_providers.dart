import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/session_termination.dart';

/// Lý do vừa bị đưa về màn đăng nhập (phiên bị thu hồi, phải đăng nhập lại,
/// bị từ chối duyệt thiết bị). Màn đăng nhập đọc một lần rồi xoá.
final loginNoticeProvider = StateProvider<SessionEndedNotice?>((_) => null);

/// Dữ liệu điền sẵn cho màn đăng nhập / đăng ký khi mở từ lời mời.
final class LoginPrefill {
  const LoginPrefill({this.inviteToken, this.domain});

  final String? inviteToken;

  /// Tên miền máy chủ của lời mời khi app chưa kết nối máy chủ nào.
  final String? domain;
}

final loginPrefillProvider = StateProvider<LoginPrefill?>((_) => null);
