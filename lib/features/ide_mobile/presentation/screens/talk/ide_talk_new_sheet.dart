import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_talk_service.dart';
import '../../../domain/ide_talk_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_talk_providers.dart';

/// Tên mô hình + mức suy nghĩ đang chọn.
String ideTalkEffortText(String e) =>
    ideTalkEffortLabel(e, vi: tr('vi', 'en') == 'vi');

/// Mở bảng tạo chat mới; trả mã cuộc vừa tạo (hoặc `null` nếu huỷ).
Future<String?> showIdeTalkNewSheet(
  BuildContext context, {
  bool models = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => IdeTalkNewSheet(withModels: models),
  );
}

class IdeTalkNewSheet extends ConsumerStatefulWidget {
  const IdeTalkNewSheet({this.withModels = true, super.key});

  /// Có `talk.models` thì cho chọn mô hình / mức suy nghĩ.
  final bool withModels;

  @override
  ConsumerState<IdeTalkNewSheet> createState() => _IdeTalkNewSheetState();
}

class _IdeTalkNewSheetState extends ConsumerState<IdeTalkNewSheet> {
  final _text = TextEditingController();
  IdeTalkModels? _models;
  Object? _modelsError;
  String? _model;
  String? _effort;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.withModels) _loadModels();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final m = await ref.read(ideTalkServiceProvider).models();
      if (!mounted) return;
      setState(() {
        _models = m;
        _modelsError = null;
        _model = m.defaultModel?.id;
        _effort = _defaultEffort(m.defaultModel);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _modelsError = e);
    }
  }

  String? _defaultEffort(IdeTalkModelOption? m) {
    if (m == null || m.efforts.isEmpty) return null;
    return m.efforts.contains('medium') ? 'medium' : m.efforts.first;
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _text.text;
    if (text.trim().isEmpty) {
      setState(() => _error = tr('Hãy nhập câu hỏi.', 'Enter a message.'));
      return;
    }
    if (text.length > ideTalkMaxText) {
      setState(() => _error = tr('Tin nhắn quá dài.', 'Message too long.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(ideTalkServiceProvider)
          .send(id: 'new', text: text, model: _model, effort: _effort);
      if (mounted) Navigator.of(context).pop(r.id);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = ideMoreErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = _models;
    final selected = models?.byId(_model ?? '');
    // Đang gửi thì chặn đóng (vuốt, chạm nền, nút Back): không mất kết quả gửi.
    return PopScope(
      canPop: !_sending,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            0,
            WebTuiSpacing.lg,
            WebTuiSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Chat mới', 'New chat'),
                style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              TextField(
                key: const Key('talk_new_text'),
                controller: _text,
                minLines: 3,
                maxLines: 8,
                autofocus: true,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: tr('Bạn muốn hỏi gì?', 'What do you want to ask?'),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.withModels) ...[
                const SizedBox(height: WebTuiSpacing.md),
                if (_modelsError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(
                            'Chưa tải được danh sách mô hình, sẽ dùng mặc định.',
                            'Could not load models; the default will be used.',
                          ),
                          style: IdeType.bodySmall.copyWith(color: IdeWb.text),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadModels,
                        child: Text(tr('Thử lại', 'Retry')),
                      ),
                    ],
                  )
                else if (models == null)
                  const LinearProgressIndicator()
                else if (models.groups.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('talk_new_model'),
                    initialValue: _model,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Mô hình', 'Model'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in models.all)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            ideVisibleText(m.name),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _model = v;
                      final m = models.byId(v ?? '');
                      _effort =
                          _effort != null &&
                              (m?.efforts.contains(_effort) ?? false)
                          ? _effort
                          : _defaultEffort(m);
                    }),
                  ),
                  if (selected != null && selected.efforts.isNotEmpty) ...[
                    const SizedBox(height: WebTuiSpacing.sm),
                    Text(
                      tr('Mức suy nghĩ', 'Effort'),
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: IdeWb.text,
                      ),
                    ),
                    Wrap(
                      spacing: WebTuiSpacing.sm,
                      children: [
                        for (final e in selected.efforts)
                          ChoiceChip(
                            key: Key('talk_effort_$e'),
                            label: Text(ideTalkEffortText(e)),
                            selected: _effort == e,
                            onSelected: (_) => setState(() => _effort = e),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: WebTuiSpacing.sm),
                Text(_error!, style: TextStyle(color: IdeWb.danger)),
              ],
              const SizedBox(height: WebTuiSpacing.md),
              FilledButton(
                key: const Key('talk_new_send'),
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('Bắt đầu chat', 'Start chat')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
