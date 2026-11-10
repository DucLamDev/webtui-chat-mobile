import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../domain/entities/inbox.dart';
import 'inbox_formatters.dart';

/// Nền ghi chú nội bộ (khác tin khách / trả lời).
const inboxNoteColor = Color(0xFFFFF4D6);
const inboxNoteBorderColor = Color(0xFFE8CF8A);
const inboxNoteLabel = 'Ghi chú nội bộ – khách không thấy';

/// Một tin: khách (trái, nền trắng), trả lời (phải, nền xanh) hoặc ghi chú
/// nội bộ (nền vàng, kèm nhãn). Tin trả lời có dòng trạng thái gửi.
class InboxMessageBubble extends StatelessWidget {
  const InboxMessageBubble({required this.message, this.onRetry, super.key});

  final InboxMessage message;

  /// Có giá trị khi tin gửi lỗi và còn gửi lại được.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final note = message.isNote;
    final customer = message.isFromCustomer;
    final color = note
        ? inboxNoteColor
        : customer
        ? WebTuiColors.messageIncoming
        : WebTuiColors.messageOutgoing;
    final border = note
        ? inboxNoteBorderColor
        : customer
        ? WebTuiColors.border
        : WebTuiColors.messageOutgoingBorder;
    final delivery = (!customer && !note) ? message.delivery.label : null;
    final failed = message.delivery == InboxDelivery.failed;
    return Align(
      alignment: customer ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          key: Key('inbox_message_${message.id}'),
          margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (note)
                const Padding(
                  padding: EdgeInsets.only(bottom: WebTuiSpacing.xs),
                  child: Text(
                    inboxNoteLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7A5B00),
                    ),
                  ),
                ),
              if (message.senderName.isNotEmpty && !customer)
                Text(
                  message.senderName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              SelectableText(message.body),
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                [
                  formatInboxMessageTime(message.createdAt),
                  ?delivery,
                ].join(' · '),
                key: Key('inbox_message_meta_${message.id}'),
                style: TextStyle(
                  fontSize: 11,
                  color: failed ? WebTuiColors.danger : WebTuiColors.textMuted,
                ),
              ),
              if (failed && message.error.isNotEmpty)
                Text(
                  message.error,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WebTuiColors.danger,
                  ),
                ),
              if (failed && message.retryable && onRetry != null)
                TextButton(
                  key: Key('inbox_retry_${message.clientMessageId}'),
                  onPressed: onRetry,
                  child: const Text('Gửi lại'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
