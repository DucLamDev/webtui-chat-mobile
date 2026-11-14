import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/tokens/webtui_channel_colors.dart';

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('mỗi loại kênh chính có màu riêng', () {
    final icons = [
      WebTuiIcons.channel,
      WebTuiIcons.announcement,
      WebTuiIcons.chitchat,
      WebTuiIcons.bot,
      WebTuiIcons.channelPrivate,
    ];
    final colors = icons.map((i) => webTuiChannelTone(i)!.icon).toSet();
    expect(colors.length, icons.length);
  });

  test('biểu tượng ngoài danh mục kênh trả null', () {
    expect(webTuiChannelTone(WebTuiIcons.tasks), isNull);
  });

  test('có bản nền tối khác bản sáng', () {
    final light = webTuiChannelTone(WebTuiIcons.channel)!;
    final dark = webTuiChannelTone(WebTuiIcons.channel, dark: true)!;
    expect(dark.background, isNot(light.background));
  });

  test('biểu tượng so với nền đạt tương phản tối thiểu 3:1', () {
    for (final pair in WebTuiChannelColors.all) {
      for (final dark in [false, true]) {
        final tone = dark ? pair.dark : pair.light;
        expect(
          _contrast(tone.icon, tone.background),
          greaterThanOrEqualTo(3.0),
          reason: 'dark=$dark ${tone.icon}',
        );
      }
    }
  });
}
