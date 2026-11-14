import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../../domain/entities/work_hub.dart';

/// Bảng thêm / sửa lối tắt. Trả `true` khi đã lưu.
Future<bool?> showShortcutFormSheet(
  BuildContext context, {
  required String workspaceId,
  AppShortcut? shortcut,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) =>
        ShortcutFormSheet(workspaceId: workspaceId, shortcut: shortcut),
  );
}

class ShortcutFormSheet extends ConsumerStatefulWidget {
  const ShortcutFormSheet({
    required this.workspaceId,
    this.shortcut,
    super.key,
  });

  final String workspaceId;
  final AppShortcut? shortcut;

  @override
  ConsumerState<ShortcutFormSheet> createState() => _ShortcutFormSheetState();
}

class _ShortcutFormSheetState extends ConsumerState<ShortcutFormSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.shortcut?.title ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.shortcut?.url ?? '',
  );
  late String _icon = webTuiShortcutIconKeys.contains(widget.shortcut?.icon)
      ? widget.shortcut!.icon
      : 'link';
  late String _color = webTuiShortcutColorKeys.contains(widget.shortcut?.color)
      ? widget.shortcut!.color
      : 'blue';
  String? _titleError;
  String? _urlError;
  String? _serverError;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final titleError = validateShortcutTitle(_title.text);
    final urlError = validateShortcutUrl(_url.text);
    setState(() {
      _titleError = titleError;
      _urlError = urlError;
      _serverError = null;
    });
    if (titleError != null || urlError != null) return;
    setState(() => _saving = true);
    final result = await ref
        .read(saveAppShortcutUseCaseProvider)
        .execute(
          workspaceId: widget.workspaceId,
          shortcutId: widget.shortcut?.id,
          draft: AppShortcutDraft(
            title: _title.text,
            url: _url.text,
            icon: _icon,
            color: _color,
          ),
        );
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _serverError = failure.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = webTuiShortcutColors(_color);
    final editing = widget.shortcut != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('shortcut_form'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing ? 'Sửa lối tắt' : 'Thêm lối tắt',
              style: WebTuiTypography.titleLarge.copyWith(
                fontWeight: FontWeight.w800,
                color: WebTuiColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('shortcut_title'),
              controller: _title,
              enabled: !_saving,
              maxLength: maxShortcutTitleLength,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Tên hiển thị',
                errorText: _titleError,
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('shortcut_url'),
              controller: _url,
              enabled: !_saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Đường dẫn (https://...)',
                errorText: _urlError,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Biểu tượng',
              style: WebTuiTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in webTuiShortcutIconKeys)
                  _IconChoice(
                    key: Key('shortcut_icon_$key'),
                    icon: webTuiShortcutIcon(key),
                    selected: key == _icon,
                    background: colors.background,
                    foreground: colors.foreground,
                    onTap: _saving ? null : () => setState(() => _icon = key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Màu',
              style: WebTuiTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final key in webTuiShortcutColorKeys)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _ColorChoice(
                      key: Key('shortcut_color_$key'),
                      colorKey: key,
                      selected: key == _color,
                      onTap: _saving
                          ? null
                          : () => setState(() => _color = key),
                    ),
                  ),
              ],
            ),
            if (_serverError != null) ...[
              const SizedBox(height: 12),
              Text(
                _serverError!,
                key: const Key('shortcut_server_error'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.danger,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('shortcut_save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Đang lưu...' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.background,
    required this.foreground,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final bool selected;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected ? background : WebTuiColors.backgroundMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? foreground : Colors.transparent,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          size: 24,
          color: selected ? foreground : WebTuiColors.textSecondary,
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.colorKey,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String colorKey;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = webTuiShortcutColors(colorKey);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Màu $colorKey',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.foreground,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? WebTuiColors.textPrimary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(WebTuiIcons.taskDone, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
