import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../application/use_cases/message_card_form_validator.dart';
import '../../../domain/entities/message_card.dart';
import 'card_common.dart';

/// Biểu mẫu trong thẻ: ô theo loại, kiểm ở client trước khi gửi, hiện lỗi từng
/// ô (của client hoặc `details.fields` của máy chủ). Gửi xong hiện "Bạn đã gửi
/// lúc …"; biểu mẫu chỉ gửi một lần thì khoá lại.
class MessageCardFormView extends StatefulWidget {
  const MessageCardFormView({
    required this.form,
    required this.onSubmit,
    this.submittedAt,
    this.submitting = false,
    this.serverFieldErrors = const {},
    this.errorMessage,
    super.key,
  });

  final MessageCardForm form;

  /// Gửi giá trị đang nhập; trả `true` khi máy chủ đã nhận.
  final Future<bool> Function(Map<String, Object?> values) onSubmit;
  final DateTime? submittedAt;
  final bool submitting;
  final Map<String, String> serverFieldErrors;
  final String? errorMessage;

  bool get locked => !form.allowMultiple && submittedAt != null;

  @override
  State<MessageCardFormView> createState() => _MessageCardFormViewState();
}

class _MessageCardFormViewState extends State<MessageCardFormView> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Object?> _values = {};
  Map<String, String> _clientErrors = const {};

  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  @override
  void didUpdateWidget(covariant MessageCardFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.form, widget.form)) _syncFields();
  }

  void _syncFields() {
    for (final field in widget.form.fields) {
      final isText = switch (field.type) {
        MessageCardFieldType.text ||
        MessageCardFieldType.textarea ||
        MessageCardFieldType.number => true,
        _ => false,
      };
      if (isText) _controllers.putIfAbsent(field.id, TextEditingController.new);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _currentValues() => {
    ..._values,
    for (final entry in _controllers.entries) entry.key: entry.value.text,
  };

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final values = _currentValues();
    final errors = validateMessageCardForm(widget.form, values);
    setState(() => _clientErrors = errors);
    if (errors.isNotEmpty) return;
    await widget.onSubmit(values);
  }

  Future<void> _pickDate(MessageCardFormField field) async {
    final current = _values[field.id];
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current is DateTime ? current : now,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 100),
      helpText: field.label,
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _values[field.id] = DateTime(picked.year, picked.month, picked.day);
      _clientErrors = {..._clientErrors}..remove(field.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final locked = widget.locked;
    final enabled = !locked && !widget.submitting;
    final errors = {...widget.serverFieldErrors, ..._clientErrors};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (form.fields.isEmpty)
          const MessageCardEmptyNote('Biểu mẫu chưa có ô nào.'),
        for (final field in form.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
            child: _buildField(field, enabled, errors[field.id]),
          ),
        if (widget.submittedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: WebTuiColors.accentGreen,
                ),
                const SizedBox(width: WebTuiSpacing.xs),
                Expanded(
                  child: Text(
                    'Bạn đã gửi lúc ${formatCardDateTime(widget.submittedAt!)}',
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (widget.errorMessage != null && !locked)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            child: Text(
              widget.errorMessage!,
              style: WebTuiTypography.labelSmall.copyWith(
                color: WebTuiColors.danger,
              ),
            ),
          ),
        if (!locked && form.fields.isNotEmpty)
          FilledButton(
            onPressed: enabled ? _submit : null,
            child: widget.submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(form.submitLabel),
          ),
      ],
    );
  }

  Widget _buildField(MessageCardFormField field, bool enabled, String? error) {
    final label = field.required ? '${field.label} *' : field.label;
    switch (field.type) {
      case MessageCardFieldType.text ||
          MessageCardFieldType.textarea ||
          MessageCardFieldType.number:
        final isNumber = field.type == MessageCardFieldType.number;
        final isArea = field.type == MessageCardFieldType.textarea;
        return TextField(
          key: ValueKey('card-field-${field.id}'),
          controller: _controllers[field.id],
          enabled: enabled,
          minLines: isArea ? 3 : 1,
          maxLines: isArea ? 6 : 1,
          maxLength: isNumber ? null : field.effectiveMaxLength,
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : isArea
              ? TextInputType.multiline
              : TextInputType.text,
          onChanged: (_) {
            if (_clientErrors.containsKey(field.id)) {
              setState(
                () => _clientErrors = {..._clientErrors}..remove(field.id),
              );
            }
          },
          decoration: _decoration(
            label,
            error,
            hint: field.placeholder ?? _numberHint(field),
          ),
        );
      case MessageCardFieldType.select:
        final value = _values[field.id] as String?;
        return DropdownButtonFormField<String>(
          key: ValueKey('card-field-${field.id}'),
          initialValue: value,
          isExpanded: true,
          decoration: _decoration(label, error, hint: field.placeholder),
          items: [
            for (final option in field.options)
              DropdownMenuItem(
                value: option.value,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled
              ? (selected) => setState(() {
                  _values[field.id] = selected;
                  _clientErrors = {..._clientErrors}..remove(field.id);
                })
              : null,
        );
      case MessageCardFieldType.date:
        final value = _values[field.id];
        return InkWell(
          key: ValueKey('card-field-${field.id}'),
          borderRadius: BorderRadius.circular(WebTuiRadii.sm),
          onTap: enabled ? () => _pickDate(field) : null,
          child: InputDecorator(
            isEmpty: value == null,
            decoration:
                _decoration(
                  label,
                  error,
                  hint: field.placeholder ?? 'Chọn ngày',
                ).copyWith(
                  enabled: enabled,
                  suffixIcon: const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                  ),
                ),
            child: value is DateTime
                ? Text(formatCardDay(value), style: WebTuiTypography.bodySmall)
                : null,
          ),
        );
      case MessageCardFieldType.checkbox:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              key: ValueKey('card-field-${field.id}'),
              value: _values[field.id] == true,
              onChanged: enabled
                  ? (checked) => setState(() {
                      _values[field.id] = checked == true;
                      _clientErrors = {..._clientErrors}..remove(field.id);
                    })
                  : null,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(label, style: WebTuiTypography.bodySmall),
            ),
            if (error != null)
              Text(
                error,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.danger,
                ),
              ),
          ],
        );
    }
  }

  String? _numberHint(MessageCardFormField field) {
    if (field.type != MessageCardFieldType.number) return null;
    final min = field.min;
    final max = field.max;
    if (min != null && max != null) {
      return 'Từ ${formatMessageCardNumber(min)} đến ${formatMessageCardNumber(max)}';
    }
    if (min != null) return 'Từ ${formatMessageCardNumber(min)}';
    if (max != null) return 'Tối đa ${formatMessageCardNumber(max)}';
    return null;
  }

  InputDecoration _decoration(String label, String? error, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      errorMaxLines: 2,
      isDense: true,
      counterText: '',
      border: const OutlineInputBorder(),
    );
  }
}
