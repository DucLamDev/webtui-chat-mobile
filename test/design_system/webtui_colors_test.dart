import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';

void main() {
  tearDown(() => WebTuiColors.apply(Brightness.light));

  test('apply(dark) đổi nền và chữ, apply(light) trả về giá trị cũ', () {
    expect(WebTuiColors.brightness, Brightness.light);
    expect(WebTuiColors.background, const Color(0xFFF6F8FC));
    expect(WebTuiColors.textPrimary, const Color(0xFF172033));

    WebTuiColors.apply(Brightness.dark);
    expect(WebTuiColors.brightness, Brightness.dark);
    expect(WebTuiColors.background, isNot(const Color(0xFFF6F8FC)));
    expect(WebTuiColors.textPrimary, isNot(const Color(0xFF172033)));
    expect(WebTuiColors.surface, const Color(0xFF172131));

    WebTuiColors.apply(Brightness.light);
    expect(WebTuiColors.background, const Color(0xFFF6F8FC));
    expect(WebTuiColors.textPrimary, const Color(0xFF172033));
    expect(WebTuiColors.surface, const Color(0xFFFFFFFF));
  });

  test('bảng tối: chữ trên nền đủ tương phản (>= 4.5:1)', () {
    WebTuiColors.apply(Brightness.dark);
    for (final bg in [
      WebTuiColors.background,
      WebTuiColors.surface,
      WebTuiColors.messageIncoming,
      WebTuiColors.messageOutgoing,
    ]) {
      expect(
        _contrast(WebTuiColors.textPrimary, bg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(WebTuiColors.textSecondary, bg),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      _contrast(WebTuiColors.textOnPrimary, WebTuiColors.primaryPressed),
      greaterThanOrEqualTo(3),
    );
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
