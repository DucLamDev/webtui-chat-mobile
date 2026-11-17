import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';

/// Tin gửi khi bấm "Vẫy tay chào" (giống nút trên web).
const chatGreetingWaveText = '👋';

/// Câu gợi ý mở đầu chat 1-1: bấm thì điền vào ô soạn (chưa gửi, sửa được).
List<String> chatGreetingSuggestions() => [
  tr('Chào bạn!', 'Hi there!'),
  tr('Bạn rảnh trao đổi chút không?', 'Got a minute to chat?'),
  tr('Cảm ơn bạn nhé!', 'Thanks a lot!'),
];

/// Màn chào khi phòng chat chưa có tin nhắn (kiểu web, làm mềm hơn cho điện
/// thoại): ảnh người kia (chat 1-1) hoặc biểu tượng nhóm nằm giữa hai vòng
/// "sóng chào", huy hiệu bàn tay vẫy, lời mời, nút "Vẫy tay chào" gửi 👋 và
/// (chat 1-1) vài câu gợi ý điền sẵn vào ô soạn.
///
/// [groupChat] `false` và không phải chat 1-1 (chat với bot tự động, phiên riêng
/// của kênh nghiệp vụ): lời mời trung tính, không nhắc "nhóm".
///
/// [onWave] / [onSuggestion] `null` thì ẩn (bị chặn, chỉ đọc, chat bot). Hiện
/// lên một lần (mờ dần + trượt nhẹ), tắt khi máy bật giảm chuyển động.
class ChatGreetingEmptyState extends StatelessWidget {
  const ChatGreetingEmptyState({
    required this.directChat,
    required this.title,
    this.groupChat = true,
    this.avatarUrl,
    this.avatarGender,
    this.onWave,
    this.onSuggestion,
    super.key,
  });

  final bool directChat;
  final bool groupChat;

  /// Tên người kia (chat 1-1) hoặc tên nhóm.
  final String title;
  final String? avatarUrl;
  final WebTuiAvatarGender? avatarGender;
  final VoidCallback? onWave;
  final ValueChanged<String>? onSuggestion;

  @override
  Widget build(BuildContext context) {
    final name = title.trim();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final content = Column(
      key: const Key('chat_greeting_empty_state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _GreetingHalo(
          directChat: directChat,
          groupChat: groupChat,
          name: name,
          avatarUrl: avatarUrl,
          avatarGender: avatarGender,
        ),
        const SizedBox(height: WebTuiSpacing.xl),
        Text(
          directChat && name.isNotEmpty
              ? tr('Gửi lời chào tới $name', 'Say hello to $name')
              : tr(
                  'Hãy là người mở đầu cuộc trò chuyện',
                  'Be the first to start the conversation',
                ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.titleLarge.copyWith(
            fontSize: 19,
            color: WebTuiColors.textPrimary,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.sm),
        Text(
          directChat
              ? tr(
                  'Hai bạn chưa nhắn tin với nhau.\nMột lời chào là khởi đầu tuyệt vời!',
                  "You two haven't chatted yet.\nA quick hello is a great start!",
                )
              : groupChat
              ? tr(
                  'Nhóm chưa có tin nhắn nào.\nTin nhắn mới sẽ xuất hiện tại đây.',
                  'No messages in this group yet.\nNew messages will appear here.',
                )
              : tr(
                  'Tin nhắn mới sẽ xuất hiện tại đây.',
                  'New messages will appear here.',
                ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: WebTuiTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w400,
            color: WebTuiColors.textSecondary,
          ),
        ),
        if (onWave != null) ...[
          const SizedBox(height: WebTuiSpacing.xl),
          FilledButton.icon(
            key: const Key('chat_greeting_wave'),
            onPressed: onWave,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.fromLTRB(18, 0, 22, 0),
              shape: const StadiumBorder(),
              textStyle: WebTuiTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            icon: const Icon(WebTuiIcons.wave, size: 22),
            label: Text(
              directChat
                  ? tr('Vẫy tay chào', 'Wave hello')
                  : tr('Chào cả nhóm', 'Wave to the group'),
            ),
          ),
        ],
        if (directChat && onSuggestion != null) ...[
          const SizedBox(height: WebTuiSpacing.lg),
          Text(
            tr('Hoặc bắt đầu bằng', 'Or start with'),
            style: WebTuiTypography.labelSmall.copyWith(
              color: WebTuiColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.xs,
            children: [
              for (final (index, text) in chatGreetingSuggestions().indexed)
                _SuggestionChip(
                  key: Key('chat_greeting_suggestion_$index'),
                  text: text,
                  onTap: () => onSuggestion!(text),
                ),
            ],
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.xxl,
          vertical: WebTuiSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - WebTuiSpacing.xl * 2).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - value)),
                    child: child,
                  ),
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ảnh / biểu tượng giữa hai vòng sóng nhạt, huy hiệu bàn tay vẫy ở góc.
class _GreetingHalo extends StatelessWidget {
  const _GreetingHalo({
    required this.directChat,
    required this.groupChat,
    required this.name,
    required this.avatarUrl,
    required this.avatarGender,
  });

  final bool directChat;
  final bool groupChat;
  final String name;
  final String? avatarUrl;
  final WebTuiAvatarGender? avatarGender;

  static const double _outer = 156;
  static const double _inner = 122;
  static const double _avatar = 88;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    final ring = WebTuiColors.primary;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: _outer,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _Ring(
              size: _outer,
              color: ring.withValues(alpha: dark ? 0.1 : 0.07),
            ),
            _Ring(
              size: _inner,
              color: ring.withValues(alpha: dark ? 0.16 : 0.11),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: WebTuiColors.surface, width: 3),
              ),
              child: directChat
                  ? WebTuiAvatar(
                      label: name.isEmpty ? '?' : name,
                      imageUrl: avatarUrl,
                      gender: avatarGender,
                      size: _avatar,
                    )
                  : Container(
                      width: _avatar,
                      height: _avatar,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: WebTuiColors.surface,
                      ),
                      child: Icon(
                        groupChat ? WebTuiIcons.group : WebTuiIcons.newMessage,
                        size: 38,
                        color: WebTuiColors.primary,
                      ),
                    ),
            ),
            Positioned(
              right: (_outer - _avatar) / 2 - 6,
              bottom: (_outer - _avatar) / 2 - 4,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: WebTuiColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  WebTuiIcons.wave,
                  size: 20,
                  color: const Color(0xFFD97706),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Câu gợi ý dạng viên thuốc (như chip lọc): nền xám nhạt, chữ đậm vừa; vùng
/// bấm cao 44.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap, super.key});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Điền "$text" vào ô soạn', 'Fill "$text" into the composer'),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: WebTuiColors.surface,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
