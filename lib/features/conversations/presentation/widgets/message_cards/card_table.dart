import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../domain/entities/message_card.dart';
import 'card_common.dart';

/// Bảng của thẻ: cuộn ngang khi nhiều cột; nhiều hàng thì hiện 20 hàng đầu và
/// nút xem thêm.
class MessageCardTableView extends StatefulWidget {
  const MessageCardTableView({required this.table, super.key});

  final MessageCardTable table;

  @override
  State<MessageCardTableView> createState() => _MessageCardTableViewState();
}

class _MessageCardTableViewState extends State<MessageCardTableView> {
  static const _collapsedRows = 20;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    if (table.columns.isEmpty || table.rows.isEmpty) {
      return const MessageCardEmptyNote('Bảng chưa có dữ liệu.');
    }
    final rows = _expanded
        ? table.rows
        : table.rows.take(_collapsedRows).toList(growable: false);
    final hidden = table.rows.length - rows.length;
    final hasHeader = table.columns.any((column) => column.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: WebTuiColors.border),
            borderRadius: BorderRadius.circular(WebTuiRadii.sm),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WebTuiRadii.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                border: const TableBorder(
                  horizontalInside: BorderSide(color: WebTuiColors.border),
                ),
                children: [
                  if (hasHeader)
                    TableRow(
                      decoration: const BoxDecoration(
                        color: WebTuiColors.backgroundMuted,
                      ),
                      children: [
                        for (final column in table.columns)
                          _Cell(text: column, header: true),
                      ],
                    ),
                  for (final row in rows)
                    TableRow(
                      children: [for (final cell in row) _Cell(text: cell)],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (hidden > 0 || _expanded && table.rows.length > _collapsedRows)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Thu gọn' : 'Xem thêm $hidden hàng'),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.text, this.header = false});

  final String text;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 56, maxWidth: 220),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.sm,
          vertical: 6,
        ),
        child: Text(
          text,
          maxLines: header ? 2 : 4,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.bodySmall.copyWith(
            color: header
                ? WebTuiColors.textSecondary
                : WebTuiColors.textPrimary,
            fontWeight: header ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
