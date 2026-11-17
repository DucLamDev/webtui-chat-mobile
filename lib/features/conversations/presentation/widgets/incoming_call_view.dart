import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_avatar.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';

/// Màn cuộc gọi đến toàn màn hình (kiểu Zalo, làm thêm), tông sáng theo giao
/// diện app (nền tối thì dịu theo nền tối): nền trắng pha nhẹ màu người gọi với
/// mảng màu mờ trôi chậm, ảnh lớn có sóng lan ra, tên lớn, hai nút tròn
/// Từ chối / Trả lời (nút Trả lời rung như chuông reo); thêm Nhắn tin (từ chối
/// rồi mở trò chuyện) và Tắt chuông (im chuông mà cuộc gọi vẫn chờ).
///
/// Hiệu ứng: màn trượt lên khi xuất hiện, sóng quanh ảnh, ảnh "thở", nút Trả
/// lời lắc, dấu "…" chạy. Máy bật giảm chuyển động thì đứng yên hết.
///
/// Chỉ là giao diện: chuông, hẹn giờ, đóng khi máy chủ báo nằm ở hộp thoại
/// gọi tới widget này.
class IncomingCallView extends StatefulWidget {
  const IncomingCallView({
    required this.name,
    required this.isVideo,
    required this.onAccept,
    required this.onDecline,
    this.avatarUrl,
    this.gender,
    this.isGroup = false,
    this.subtitle,
    this.onMessage,
    this.onSilence,
    this.silenced = false,
    super.key,
  });

  /// Tên người gọi (gọi 1-1) hoặc tên nhóm (gọi nhóm). Trống thì ghi
  /// "Cuộc gọi đến".
  final String name;
  final bool isVideo;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final String? avatarUrl;

  /// Giới tính người gọi (vẽ hình người khi chưa có ảnh). Gọi nhóm: bỏ trống.
  final String? gender;
  final bool isGroup;

  /// Dòng dưới tên; trống thì "đang gọi cho bạn" / "đang gọi nhóm" (dấu "…"
  /// chạy được thêm tự động).
  final String? subtitle;

  /// null = ẩn nút Nhắn tin.
  final VoidCallback? onMessage;

  /// null = ẩn nút Tắt chuông.
  final VoidCallback? onSilence;
  final bool silenced;

  @override
  State<IncomingCallView> createState() => _IncomingCallViewState();
}

class _IncomingCallViewState extends State<IncomingCallView>
    with TickerProviderStateMixin {
  /// Sóng quanh ảnh, ảnh thở, mảng màu nền trôi, ba chấm (lặp).
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// Nút Trả lời lắc như chuông reo rồi nghỉ (lặp).
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Màn trượt lên + hiện dần khi xuất hiện (một lần).
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      _ambient.stop();
      _ring.stop();
      _enter.value = 1;
    } else {
      if (!_ambient.isAnimating) _ambient.repeat();
      if (!_ring.isAnimating) _ring.repeat();
      if (_enter.value == 0 && !_enter.isAnimating) _enter.forward();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    _ring.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.name.trim().isEmpty
        ? tr('Cuộc gọi đến', 'Incoming call')
        : widget.name.trim();
    final kind = widget.isGroup
        ? (widget.isVideo
              ? tr('Cuộc gọi nhóm video', 'Group video call')
              : tr('Cuộc gọi nhóm thoại', 'Group voice call'))
        : (widget.isVideo
              ? tr('Cuộc gọi video đến', 'Incoming video call')
              : tr('Cuộc gọi thoại đến', 'Incoming voice call'));
    final rawLine = widget.subtitle?.trim().isNotEmpty == true
        ? widget.subtitle!.trim()
        : (widget.isGroup
              ? tr('đang gọi nhóm', 'is calling the group')
              : tr('đang gọi cho bạn', 'is calling you'));
    // Dấu "…" do hiệu ứng thêm vào: bỏ dấu sẵn có ở cuối câu.
    final line = rawLine.replaceFirst(RegExp(r'(…|\.\.\.)$'), '').trimRight();
    final palette = _CallPalette.of(title);
    return Material(
      key: const Key('incoming_call_view'),
      color: palette.page,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(
            palette: palette,
            avatarUrl: widget.avatarUrl,
            drift: _ambient,
            animate: !_reduceMotion,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Màn thấp (điện thoại nhỏ, chia đôi màn hình): thu gọn ảnh,
                // chữ, khoảng cách; vẫn thiếu chỗ thì cuộn được, không tràn.
                final compact = constraints.maxHeight < 640;
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: AnimatedBuilder(
                        animation: _enter,
                        builder: (context, child) {
                          final t = Curves.easeOutCubic.transform(_enter.value);
                          return Opacity(
                            opacity: t,
                            child: Transform.translate(
                              offset: Offset(0, 28 * (1 - t)),
                              child: child,
                            ),
                          );
                        },
                        child: _content(
                          palette: palette,
                          compact: compact,
                          title: title,
                          kind: kind,
                          line: line,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _content({
    required _CallPalette palette,
    required bool compact,
    required String title,
    required String kind,
    required String line,
  }) {
    final onMessage = widget.onMessage;
    final onSilence = widget.onSilence;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SizedBox(height: compact ? 12 : 20),
          _KindPill(palette: palette, isVideo: widget.isVideo, label: kind),
          const Spacer(flex: 2),
          _RippleAvatar(
            palette: palette,
            animation: _ambient,
            animate: !_reduceMotion,
            compact: compact,
            child: WebTuiAvatar(
              label: title,
              imageUrl: widget.avatarUrl,
              icon: widget.isGroup ? WebTuiIcons.group : null,
              gender: widget.isGroup
                  ? null
                  : WebTuiAvatarGender.parse(widget.gender),
              size: compact ? 94 : 114,
            ),
          ),
          SizedBox(height: compact ? 16 : 26),
          Text(
            title,
            key: const Key('incoming_call_name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: compact ? 26 : 30,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          _CallingLine(
            text: line,
            color: palette.textMuted,
            animation: _ambient,
            animate: !_reduceMotion,
          ),
          const Spacer(flex: 3),
          if (onMessage != null || onSilence != null) ...[
            Row(
              children: [
                if (onMessage != null)
                  Expanded(
                    child: _SmallAction(
                      key: const Key('incoming_call_message'),
                      palette: palette,
                      icon: WebTuiIcons.newMessage,
                      label: tr('Nhắn tin', 'Message'),
                      onPressed: onMessage,
                    ),
                  ),
                if (onSilence != null)
                  Expanded(
                    child: _SmallAction(
                      key: const Key('incoming_call_silence'),
                      palette: palette,
                      icon: WebTuiIcons.bellOff,
                      label: widget.silenced
                          ? tr('Đã tắt chuông', 'Silenced')
                          : tr('Tắt chuông', 'Silence'),
                      onPressed: widget.silenced ? null : onSilence,
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 18 : 28),
          ],
          Row(
            children: [
              Expanded(
                child: _CallButton(
                  key: const Key('incoming_call_decline'),
                  palette: palette,
                  color: palette.decline,
                  icon: Icons.call_end_rounded,
                  label: tr('Từ chối', 'Decline'),
                  semanticLabel: tr(
                    'Từ chối cuộc gọi của $title',
                    'Decline call from $title',
                  ),
                  onPressed: widget.onDecline,
                ),
              ),
              Expanded(
                child: _CallButton(
                  key: const Key('incoming_call_accept'),
                  palette: palette,
                  color: palette.accept,
                  icon: widget.isVideo
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  label: tr('Trả lời', 'Answer'),
                  semanticLabel: tr(
                    'Trả lời cuộc gọi của $title',
                    'Answer call from $title',
                  ),
                  ring: _reduceMotion ? null : _ring,
                  onPressed: widget.onAccept,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 20 : 36),
        ],
      ),
    );
  }
}

/// Màu của màn theo giao diện app: nền sáng (mặc định) hoặc tối dịu.
final class _CallPalette {
  const _CallPalette({
    required this.dark,
    required this.page,
    required this.tint,
    required this.tintSoft,
    required this.text,
    required this.textMuted,
    required this.chip,
    required this.chipBorder,
    required this.accent,
  });

  factory _CallPalette.of(String name) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    final tone = webTuiAvatarGradientFor(name).colors.first;
    return _CallPalette(
      dark: dark,
      page: WebTuiColors.page,
      tint: tone,
      tintSoft: Color.lerp(WebTuiColors.page, tone, dark ? 0.22 : 0.14)!,
      text: WebTuiColors.textPrimary,
      textMuted: WebTuiColors.textMuted,
      chip: dark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.88),
      chipBorder: WebTuiColors.hairline,
      accent: WebTuiColors.primary,
    );
  }

  final bool dark;
  final Color page;

  /// Màu của người gọi (cùng bảng màu ảnh đại diện).
  final Color tint;

  /// Màu người gọi pha loãng vào nền (đầu màn).
  final Color tintSoft;
  final Color text;
  final Color textMuted;
  final Color chip;
  final Color chipBorder;
  final Color accent;

  Color get decline => const Color(0xFFF04444);
  Color get accept => const Color(0xFF12B76A);
}

/// Nền: trắng pha nhẹ màu người gọi ở đầu màn, hai mảng màu mờ trôi chậm, ảnh
/// người gọi làm mờ rất nhạt nếu có.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.palette,
    required this.drift,
    required this.animate,
    this.avatarUrl,
  });

  final _CallPalette palette;
  final Animation<double> drift;
  final bool animate;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim() ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.tintSoft, palette.page, palette.page],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        if (url.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) => Opacity(
              opacity: palette.dark ? 0.22 : 0.16,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: WebTuiBoundedNetworkImage(
                  imageUrl: url,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  maxBytes: webTuiMaxAvatarImageBytes,
                  fit: BoxFit.cover,
                  fallback: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        AnimatedBuilder(
          animation: drift,
          builder: (context, _) {
            final phase = animate ? drift.value * 2 * math.pi : 0.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                _Blob(
                  color: palette.tint.withValues(
                    alpha: palette.dark ? 0.20 : 0.16,
                  ),
                  size: 300,
                  alignment: Alignment(
                    -0.9 + 0.12 * math.sin(phase),
                    -0.75 + 0.06 * math.cos(phase),
                  ),
                ),
                _Blob(
                  color: palette.accent.withValues(
                    alpha: palette.dark ? 0.16 : 0.10,
                  ),
                  size: 260,
                  alignment: Alignment(
                    0.95 - 0.10 * math.cos(phase),
                    -0.2 + 0.08 * math.sin(phase),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.color,
    required this.size,
    required this.alignment,
  });

  final Color color;
  final double size;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.palette,
    required this.isVideo,
    required this.label,
  });

  final _CallPalette palette;
  final bool isVideo;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chip,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.chipBorder),
        boxShadow: palette.dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? WebTuiIcons.video : WebTuiIcons.phone,
              size: 16,
              color: palette.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ảnh người gọi có viền trắng, ba vòng sóng màu người gọi lan ra lần lượt và
/// ảnh "thở" nhẹ (đứng yên khi giảm chuyển động).
class _RippleAvatar extends StatelessWidget {
  const _RippleAvatar({
    required this.palette,
    required this.animation,
    required this.animate,
    required this.compact,
    required this.child,
  });

  final _CallPalette palette;
  final Animation<double> animation;
  final bool animate;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 100.0 : 120.0;
    final extent = compact ? 168.0 : 220.0;
    return SizedBox.square(
      dimension: extent,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final value = animate ? animation.value : 0.0;
          final rings = <Widget>[
            if (animate)
              for (final offset in const [0.0, 1 / 3, 2 / 3])
                _Ring(
                  diameter: size + (extent - size) * ((value + offset) % 1.0),
                  color: palette.tint.withValues(
                    alpha: 0.26 * (1 - ((value + offset) % 1.0)),
                  ),
                )
            else
              _Ring(
                diameter: size + 30,
                color: palette.tint.withValues(alpha: 0.14),
              ),
          ];
          final breath = animate
              ? 1 + 0.025 * math.sin(value * 2 * math.pi)
              : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              ...rings,
              Transform.scale(scale: breath, child: child),
            ],
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.page,
            boxShadow: [
              BoxShadow(
                color: palette.tint.withValues(alpha: 0.26),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(padding: const EdgeInsets.all(3), child: child),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// "đang gọi cho bạn" + ba chấm chạy (đứng yên "…" khi giảm chuyển động).
class _CallingLine extends StatelessWidget {
  const _CallingLine({
    required this.text,
    required this.color,
    required this.animation,
    required this.animate,
  });

  final String text;
  final Color color;
  final Animation<double> animation;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: color, fontSize: 16, height: 1.35);
    return Semantics(
      label: '$text…',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              key: const Key('incoming_call_line'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final count = animate ? 1 + (animation.value * 3).floor() % 3 : 3;
              // Giữ chỗ đủ 3 chấm để chữ không xô qua lại.
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '.' * count),
                    TextSpan(
                      text: '.' * (3 - count),
                      style: const TextStyle(color: Colors.transparent),
                    ),
                  ],
                ),
                style: style,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Nút tròn lớn 72 có nhãn bên dưới. [ring] (nút Trả lời): lắc như chuông reo
/// rồi nghỉ, nảy nhẹ, quầng sáng nhịp theo.
class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.palette,
    required this.color,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.ring,
    super.key,
  });

  final _CallPalette palette;
  final Color color;
  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Animation<double>? ring;

  @override
  Widget build(BuildContext context) {
    final ring = this.ring;
    final button = Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: 72,
          child: ring == null
              ? Icon(icon, color: Colors.white, size: 32)
              : AnimatedBuilder(
                  animation: ring,
                  builder: (context, child) =>
                      Transform.rotate(angle: _shake(ring.value), child: child),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ring == null)
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: button,
            )
          else
            AnimatedBuilder(
              animation: ring,
              builder: (context, child) {
                final pulse = math.sin(ring.value * math.pi);
                return Transform.translate(
                  offset: Offset(0, -4 * _bounce(ring.value)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.24 + 0.22 * pulse),
                          blurRadius: 18 + 12 * pulse,
                          spreadRadius: 1 + 5 * pulse,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              },
              child: button,
            ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 40% đầu chu kỳ: lắc 6 nhịp ±0,26 rad giảm dần; phần còn lại đứng yên.
  static double _shake(double t) {
    if (t > 0.4) return 0;
    final local = t / 0.4;
    return 0.26 * math.sin(local * 6 * 2 * math.pi) * (1 - local);
  }

  /// Nảy nhẹ cùng lúc lắc.
  static double _bounce(double t) {
    if (t > 0.4) return 0;
    return math.sin(t / 0.4 * math.pi);
  }
}

/// Nút phụ nhỏ (Nhắn tin, Tắt chuông): vòng xám nhạt 52 + nhãn.
class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final _CallPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.chip,
                  border: Border.all(color: palette.chipBorder),
                ),
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(
                    icon,
                    size: 24,
                    color: enabled ? palette.text : palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: enabled ? palette.text : palette.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
