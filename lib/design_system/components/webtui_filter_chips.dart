import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_typography.dart';

/// Một chip trong [WebTuiFilterChipBar].
class WebTuiFilterChipData {
  const WebTuiFilterChipData({required this.label, this.count, this.key});

  final String label;

  /// Số đếm nằm trong chip (vd "Chưa đọc 4"); null hoặc 0 thì không hiện.
  final int? count;

  /// Khoá của chip (test / mã gọi tìm theo khoá).
  final Key? key;
}

/// Thanh lọc trượt ngang kiểu YouTube: chip phẳng cao 32, bo 8, không viền;
/// hàng chip tràn tới mép màn hình, cuộn có quán tính và nảy ở hai đầu, không
/// thanh cuộn; mép phải mờ dần khi còn chip phía sau; bấm chip thì rung nhẹ và
/// tự cuộn chip đó vào giữa. Vùng bấm mỗi chip cao 44.
class WebTuiFilterChipBar extends StatefulWidget {
  const WebTuiFilterChipBar({
    required this.chips,
    required this.selectedIndex,
    required this.onSelected,
    this.semanticLabel,
    super.key,
  });

  final List<WebTuiFilterChipData> chips;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? semanticLabel;

  @override
  State<WebTuiFilterChipBar> createState() => _WebTuiFilterChipBarState();
}

class _WebTuiFilterChipBarState extends State<WebTuiFilterChipBar> {
  final _controller = ScrollController();
  final _chipKeys = <GlobalKey>[];
  bool _moreAfter = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateFade);
    _syncKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void didUpdateWidget(covariant WebTuiFilterChipBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKeys();
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(widget.selectedIndex),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFade());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateFade)
      ..dispose();
    super.dispose();
  }

  void _syncKeys() {
    while (_chipKeys.length < widget.chips.length) {
      _chipKeys.add(GlobalKey());
    }
    if (_chipKeys.length > widget.chips.length) {
      _chipKeys.removeRange(widget.chips.length, _chipKeys.length);
    }
  }

  void _updateFade() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final more = position.pixels < position.maxScrollExtent - 1;
    if (more != _moreAfter) setState(() => _moreAfter = more);
  }

  /// Cuộn chip [index] vào giữa thanh (chip ở sát mép không bị che).
  void _reveal(int index) {
    if (!mounted || index < 0 || index >= _chipKeys.length) return;
    final chipContext = _chipKeys[index].currentContext;
    if (chipContext == null) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Scrollable.ensureVisible(
      chipContext,
      alignment: 0.5,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _select(int index) {
    HapticFeedback.selectionClick();
    widget.onSelected(index);
    _reveal(index);
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: widget.chips.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final chip = widget.chips[index];
        return KeyedSubtree(
          key: _chipKeys[index],
          child: _FilterChip(
            key: chip.key,
            data: chip,
            selected: index == widget.selectedIndex,
            onTap: () => _select(index),
          ),
        );
      },
    );
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: SizedBox(
        height: 44,
        // Luôn giữ ShaderMask (hết chip phía sau thì dải mờ thành đặc): đổi
        // cây widget sẽ dựng lại ListView và đưa vị trí cuộn về đầu.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [
              Colors.black,
              Colors.black,
              _moreAfter ? Colors.transparent : Colors.black,
            ],
            stops: [0, ((rect.width - 32) / rect.width).clamp(0, 1), 1],
          ).createShader(rect),
          child: list,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.data,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final WebTuiFilterChipData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? WebTuiColors.textOnPrimary
        : WebTuiColors.textPrimary;
    final count = data.count ?? 0;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected
                  ? WebTuiColors.primaryFill
                  : WebTuiColors.chipBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    count > 99 ? '99+' : '$count',
                    style: WebTuiTypography.bodySmall.copyWith(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? WebTuiColors.textOnPrimary
                          : WebTuiColors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
