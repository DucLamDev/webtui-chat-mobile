import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_term.dart';

/// Hành động của một phím phụ.
typedef IdeTermNavBuilder = String Function(int mod, bool appCursor);

/// Hàng phím phụ cuộn ngang: Esc, Tab, Ctrl, Alt (dính), 4 mũi tên, `| ~ / -`,
/// Home, End, PgUp, PgDn. Mỗi phím cao và rộng ≥ 44.
class IdeTermExtraKeys extends StatelessWidget {
  const IdeTermExtraKeys({
    required this.ctrl,
    required this.alt,
    required this.onToggleCtrl,
    required this.onToggleAlt,
    required this.onText,
    required this.onNav,
    super.key,
  });

  final bool ctrl;
  final bool alt;
  final VoidCallback onToggleCtrl;
  final VoidCallback onToggleAlt;
  final ValueChanged<String> onText;
  final ValueChanged<IdeTermNavBuilder> onNav;

  @override
  Widget build(BuildContext context) {
    Widget key(
      String id,
      Widget label,
      VoidCallback onTap, {
      bool active = false,
      String? tooltip,
    }) => _Key(
      key: Key('term_key_$id'),
      active: active,
      tooltip: tooltip,
      onTap: onTap,
      child: label,
    );
    Widget text(String id, String shown, String send) =>
        key(id, Text(shown), () => onText(send));
    Widget nav(String id, IconData icon, String tip, IdeTermNavBuilder b) =>
        key(id, Icon(icon, size: 22), () => onNav(b), tooltip: tip);
    Widget navText(String id, String shown, IdeTermNavBuilder b) =>
        key(id, Text(shown), () => onNav(b));
    return Material(
      color: WebTuiColors.surface,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: WebTuiColors.hairline)),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          children: [
            text('esc', 'Esc', IdeTermKeys.esc),
            text('tab', 'Tab', IdeTermKeys.tab),
            key('ctrl', const Text('Ctrl'), onToggleCtrl, active: ctrl),
            key('alt', const Text('Alt'), onToggleAlt, active: alt),
            nav(
              'left',
              Icons.keyboard_arrow_left_rounded,
              tr('Mũi tên trái', 'Left'),
              (m, a) => IdeTermKeys.arrow('left', appCursor: a, mod: m),
            ),
            nav(
              'down',
              Icons.keyboard_arrow_down_rounded,
              tr('Mũi tên xuống', 'Down'),
              (m, a) => IdeTermKeys.arrow('down', appCursor: a, mod: m),
            ),
            nav(
              'up',
              Icons.keyboard_arrow_up_rounded,
              tr('Mũi tên lên', 'Up'),
              (m, a) => IdeTermKeys.arrow('up', appCursor: a, mod: m),
            ),
            nav(
              'right',
              Icons.keyboard_arrow_right_rounded,
              tr('Mũi tên phải', 'Right'),
              (m, a) => IdeTermKeys.arrow('right', appCursor: a, mod: m),
            ),
            text('pipe', '|', '|'),
            text('tilde', '~', '~'),
            text('slash', '/', '/'),
            text('dash', '-', '-'),
            navText(
              'home',
              'Home',
              (m, a) => IdeTermKeys.home(appCursor: a, mod: m),
            ),
            navText(
              'end',
              'End',
              (m, a) => IdeTermKeys.end(appCursor: a, mod: m),
            ),
            navText('pgup', 'PgUp', (m, a) => IdeTermKeys.pageUp(mod: m)),
            navText('pgdn', 'PgDn', (m, a) => IdeTermKeys.pageDown(mod: m)),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.child,
    required this.onTap,
    this.active = false,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = active ? WebTuiColors.textOnPrimary : WebTuiColors.textPrimary;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? WebTuiColors.primary : WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: fg),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      child: tooltip == null ? body : Tooltip(message: tooltip!, child: body),
    );
  }
}
