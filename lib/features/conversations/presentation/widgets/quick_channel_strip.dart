import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../domain/entities/conversation_summary.dart';
import 'business_channel_grid.dart';

/// Dải kênh nghiệp vụ (đơn hàng, gia hạn...) đầu hộp thư, mặc định thu gọn
/// thành một dòng cho rộng chỗ danh sách; bấm dòng đó để mở / đóng. Thứ tự cố
/// định theo danh mục nghiệp vụ, tin chưa đọc hiện bằng huy hiệu (khi thu gọn
/// thì cộng dồn lên dòng tiêu đề).
class QuickChannelStrip extends StatefulWidget {
  const QuickChannelStrip({
    required this.channels,
    required this.onTap,
    required this.onShowAll,
    super.key,
  });

  final List<ConversationSummary> channels;
  final ValueChanged<ConversationSummary> onTap;
  final VoidCallback onShowAll;

  @override
  State<QuickChannelStrip> createState() => QuickChannelStripState();
}

class QuickChannelStripState extends State<QuickChannelStrip> {
  // Nhớ trạng thái mở / đóng trong phiên, kể cả khi đổi bộ lọc rồi quay lại.
  static const _storageId = 'quick-channel-strip-expanded';
  bool _expanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final saved = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _storageId);
    if (saved is bool) {
      _expanded = saved;
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, _expanded, identifier: _storageId);
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.channels;
    final unread = channels.fold<int>(
      0,
      (sum, channel) =>
          sum + (channel.unreadCount > 0 ? channel.unreadCount : 0),
    );
    // Máy bật giảm chuyển động thì mở / đóng ngay, không hiệu ứng.
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: WebTuiSpacing.sm,
            top: WebTuiSpacing.xs,
            right: WebTuiSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  expanded: _expanded,
                  child: InkWell(
                    key: const ValueKey('quick-channel-toggle'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: _toggle,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WebTuiSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Nghiệp vụ',
                              style: TextStyle(
                                color: WebTuiColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: WebTuiSpacing.xs),
                            Text(
                              '${channels.length} kênh',
                              style: const TextStyle(
                                color: WebTuiColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            if (!_expanded && unread > 0) ...[
                              const SizedBox(width: WebTuiSpacing.xs),
                              _UnreadPill(count: unread),
                            ],
                            const SizedBox(width: 2),
                            AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: motion,
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: WebTuiColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_expanded)
                TextButton(
                  onPressed: widget.onShowAll,
                  child: const Text('Xem tất cả'),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: motion,
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: WebTuiSpacing.md,
                    ),
                    itemCount: channels.length,
                    separatorBuilder: (context, index) {
                      return const SizedBox(width: WebTuiSpacing.xs);
                    },
                    itemBuilder: (context, index) {
                      final channel = channels[index];
                      return BusinessChannelTile(
                        channel: channel,
                        onTap: () => widget.onTap(channel),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.danger,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: WebTuiColors.textOnPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
