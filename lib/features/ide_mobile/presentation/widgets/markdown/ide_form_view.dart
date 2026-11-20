import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
import 'ide_blocks_model.dart';

/// Biểu mẫu đã gửi trong phiên chạy này ("mã tin:thứ tự"), để vẽ lại tin giữa
/// chừng vẫn hiện "Đã gửi" (như `SENT` của IDE web).
final Set<String> ideSentForms = <String>{};

/// Biểu mẫu thật. Gửi → [onSubmit] với chuỗi trả lời giống IDE web; [onSubmit]
/// null thì chỉ xem. [onSubmit] ném lỗi → mở lại để gửi tiếp.
class IdeFormView extends StatefulWidget {
  const IdeFormView({
    required this.spec,
    required this.onSubmit,
    this.sentKey,
    super.key,
  });

  final IdeFormSpec spec;
  final FutureOr<dynamic> Function(String answer)? onSubmit;
  final String? sentKey;

  @override
  State<IdeFormView> createState() => _IdeFormViewState();
}

class _IdeFormViewState extends State<IdeFormView> {
  final _formKey = GlobalKey<FormState>();
  final _values = <String, Object?>{};
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  bool _sent = false;
  bool _failed = false;
  String? _empty;

  @override
  void initState() {
    super.initState();
    _sent = widget.sentKey != null && ideSentForms.contains(widget.sentKey);
    for (final f in widget.spec.fields) {
      if (f.type == IdeFieldType.text ||
          f.type == IdeFieldType.number ||
          f.type == IdeFieldType.textarea ||
          f.type == IdeFieldType.date) {
        _controllers[f.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _live => widget.onSubmit != null && !_sent;

  Future<void> _submit() async {
    if (!_live || _busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final values = <String, Object?>{
      for (final f in widget.spec.fields)
        f.id: _controllers[f.id]?.text ?? _values[f.id],
    };
    final answer = ideFormAnswer(widget.spec, values);
    if (answer == null) {
      setState(
        () => _empty = tr(
          'Hãy điền ít nhất một ô.',
          'Fill in at least one field.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _empty = null;
    });
    final key = widget.sentKey;
    if (key != null) ideSentForms.add(key);
    try {
      final r = await widget.onSubmit!(answer);
      if (r == false) throw StateError('submit refused');
      if (mounted) setState(() => _sent = true);
    } on Object {
      if (key != null) ideSentForms.remove(key);
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(IdeFormField f) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    _controllers[f.id]!.text =
        '${picked.year}-${two(picked.month)}-${two(picked.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final enabled = _live && !_busy;
    final status = _sent
        ? tr('Đã gửi', 'Sent')
        : _failed
        ? tr('Chưa gửi được, thử lại.', 'Could not send, try again.')
        : _empty ??
              (widget.onSubmit == null
                  ? tr(
                      'Chỉ xem: biểu mẫu cũ hoặc không nằm trong khung chat.',
                      'View only: old form or not in a chat.',
                    )
                  : '');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: IdeWbPalette.of(context).bg,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: IdeWbPalette.of(context).border),
      ),
      // Material trong suốt để ListTile (ô chọn) không bị khung nền che hiệu ứng.
      child: Material(
        type: MaterialType.transparency,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (spec.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                  child: Text(
                    spec.title,
                    style: IdeType.titleMedium.copyWith(
                      color: IdeWbPalette.of(context).textStrong,
                    ),
                  ),
                ),
              for (final f in spec.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                  child: _field(f, enabled),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: IdeType.bodySmall.copyWith(
                        color: _failed || _empty != null
                            ? IdeWbPalette.of(context).danger
                            : IdeWbPalette.of(context).text2,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 44),
                    ),
                    onPressed: enabled ? _submit : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            spec.submit.isEmpty
                                ? tr('Gửi', 'Send')
                                : spec.submit,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(IdeFormField f, bool enabled) {
    final label = f.required ? '${f.label} *' : f.label;
    String? requiredCheck(String? v) => f.required && (v ?? '').trim().isEmpty
        ? tr('Bắt buộc', 'Required')
        : null;
    switch (f.type) {
      case IdeFieldType.checkbox:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(f.label),
          value: _values[f.id] == true,
          onChanged: enabled
              ? (v) => setState(() => _values[f.id] = v == true)
              : null,
        );
      case IdeFieldType.select:
        return DropdownButtonFormField<String>(
          initialValue: _values[f.id] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final o in f.options)
              DropdownMenuItem(
                value: o,
                child: Text(o, overflow: TextOverflow.ellipsis),
              ),
          ],
          validator: requiredCheck,
          onChanged: enabled ? (v) => _values[f.id] = v : null,
        );
      case IdeFieldType.date:
        return TextFormField(
          controller: _controllers[f.id],
          readOnly: true,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: label,
            hintText: f.placeholder.isEmpty ? null : f.placeholder,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
          ),
          validator: requiredCheck,
          onTap: enabled ? () => _pickDate(f) : null,
        );
      case IdeFieldType.textarea:
        return TextFormField(
          controller: _controllers[f.id],
          enabled: enabled,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: label,
            hintText: f.placeholder.isEmpty ? null : f.placeholder,
          ),
          validator: requiredCheck,
        );
      case IdeFieldType.number:
        return TextFormField(
          controller: _controllers[f.id],
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: label,
            hintText: f.placeholder.isEmpty ? null : f.placeholder,
          ),
          validator: (v) {
            final r = requiredCheck(v);
            if (r != null) return r;
            final t = (v ?? '').trim();
            if (t.isNotEmpty && num.tryParse(t.replaceAll(',', '.')) == null) {
              return tr('Nhập một số', 'Enter a number');
            }
            return null;
          },
        );
      case IdeFieldType.text:
        return TextFormField(
          controller: _controllers[f.id],
          enabled: enabled,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: label,
            hintText: f.placeholder.isEmpty ? null : f.placeholder,
            counterText: '',
          ),
          validator: requiredCheck,
        );
    }
  }
}
