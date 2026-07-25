import 'package:flutter/material.dart';

import 'webtui_colors.dart';

final class WebTuiShadows {
  const WebTuiShadows._();

  static const soft = [
    BoxShadow(color: Color(0x120877F2), blurRadius: 14, offset: Offset(0, 6)),
  ];

  static const lift = [
    BoxShadow(color: Color(0x0F172033), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const divider = BoxShadow(
    color: WebTuiColors.border,
    blurRadius: 0,
    offset: Offset(0, 1),
  );
}
