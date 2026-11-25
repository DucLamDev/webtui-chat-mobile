import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Người đang dùng VPSTTT IDE: máy chủ chat + tài khoản.
final class IdeWebOwner {
  const IdeWebOwner({required this.scopeId, required this.userId});

  final String scopeId;
  final String userId;

  /// Không đảo ngược được, chỉ để so "cùng người" và đặt tên khoá.
  String get digest =>
      sha256.convert(utf8.encode('$scopeId|$userId')).toString();

  @override
  bool operator ==(Object other) =>
      other is IdeWebOwner &&
      other.scopeId == scopeId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(scopeId, userId);
}
