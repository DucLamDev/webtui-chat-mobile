import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Khoảng đệm đáy vừa đủ cho thanh dính đáy màn hình (ô nhập tin, thanh tab
/// nổi), thay cho `SafeArea` cộng nguyên vùng an toàn.
///
/// - iPhone / iPad: vùng an toàn đáy (34 / 20) cao hơn chỗ thanh home thật sự
///   chiếm, nên bớt tối đa 12 để thanh nằm sát ngay trên thanh home như
///   Telegram / Zalo; vẫn chừa ít nhất 16 (không đè lên thanh home).
/// - Android: giữ đúng vùng an toàn (thanh 3 nút 48, thanh cử chỉ 24) để không
///   đè nút hệ thống.
/// - Đệm đáy lớn hơn vùng an toàn hệ thống (đã cộng chỗ của thanh khác, vd. thân
///   màn có thanh tab nổi) thì giữ nguyên.
/// - Bàn phím mở: đệm đáy về 0, chỉ còn [minimum].
double webTuiBottomInset(BuildContext context, {double minimum = 0}) {
  final padding = MediaQuery.paddingOf(context).bottom;
  final system = MediaQuery.viewPaddingOf(context).bottom;
  final platform = Theme.of(context).platform;
  final homeIndicator =
      platform == TargetPlatform.iOS && padding > 0 && padding <= system;
  final inset = homeIndicator
      ? math.max(padding - 12, math.min(padding, 16.0))
      : padding;
  return math.max(inset, minimum);
}
