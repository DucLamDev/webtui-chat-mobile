import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Cỡ chữ terminal: mặc định 13, chụm 2 ngón đổi trong khoảng này.
const ideTermMinFont = 8.0;
const ideTermMaxFont = 28.0;
const ideTermDefaultFont = 13.0;

double ideTermClampFont(double v) => v.clamp(ideTermMinFont, ideTermMaxFont);

/// Bảng màu terminal (chữ luôn đủ tương phản). Màn terminal luôn dùng bộ tối,
/// nền #181818 như khung terminal của IDE web.
TerminalTheme ideTermTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return dark
      ? const TerminalTheme(
          cursor: Color(0xFFE6EDF3),
          selection: Color(0x668100FF),
          foreground: Color(0xFFE6EDF3),
          background: Color(0xFF181818),
          black: Color(0xFF484F58),
          red: Color(0xFFFF7B72),
          green: Color(0xFF3FB950),
          yellow: Color(0xFFD29922),
          blue: Color(0xFF58A6FF),
          magenta: Color(0xFFBC8CFF),
          cyan: Color(0xFF39C5CF),
          white: Color(0xFFB1BAC4),
          brightBlack: Color(0xFF6E7681),
          brightRed: Color(0xFFFFA198),
          brightGreen: Color(0xFF56D364),
          brightYellow: Color(0xFFE3B341),
          brightBlue: Color(0xFF79C0FF),
          brightMagenta: Color(0xFFD2A8FF),
          brightCyan: Color(0xFF56D4DD),
          brightWhite: Color(0xFFF0F6FC),
          searchHitBackground: Color(0xFFD29922),
          searchHitBackgroundCurrent: Color(0xFF3FB950),
          searchHitForeground: Color(0xFF181818),
        )
      : const TerminalTheme(
          cursor: Color(0xFF1F2328),
          selection: Color(0x553B82F6),
          foreground: Color(0xFF1F2328),
          background: Color(0xFFF6F8FA),
          black: Color(0xFF24292F),
          red: Color(0xFFCF222E),
          green: Color(0xFF1A7F37),
          yellow: Color(0xFF9A6700),
          blue: Color(0xFF0969DA),
          magenta: Color(0xFF8250DF),
          cyan: Color(0xFF1B7C83),
          white: Color(0xFF6E7781),
          brightBlack: Color(0xFF57606A),
          brightRed: Color(0xFFA40E26),
          brightGreen: Color(0xFF116329),
          brightYellow: Color(0xFF7D4E00),
          brightBlue: Color(0xFF0550AE),
          brightMagenta: Color(0xFF6639BA),
          brightCyan: Color(0xFF136A71),
          brightWhite: Color(0xFF8C959F),
          searchHitBackground: Color(0xFFFFDF5D),
          searchHitBackgroundCurrent: Color(0xFF82E596),
          searchHitForeground: Color(0xFF1F2328),
        );
}
