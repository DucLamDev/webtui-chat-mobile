import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/flavor/app_config.dart';
import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';

const _categories = <(String, String)>[
  ('bug', 'Báo lỗi'),
  ('idea', 'Đề xuất'),
  ('other', 'Khác'),
];

/// Góp ý ngay trong app: gửi tới quản trị workspace
/// (`POST /api/v1/workspaces/{id}/feedback`), xem ở trang admin → Góp ý.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _message = TextEditingController();
  String _category = 'bug';
  int _rating = 0;
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send(String workspaceId) async {
    final message = _message.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    final config = ref.read(appConfigProvider);
    final api = ref.read(apiTransportProvider);
    final platform = Theme.of(context).platform.name;
    try {
      await api.post<Object>(
        '/api/v1/workspaces/$workspaceId/feedback',
        data: {
          'category': _category,
          'message': message,
          if (_rating > 0) 'rating': _rating,
          'platform': platform,
          'app_version': config.appVersion,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cảm ơn bạn! Góp ý đã được gửi.')),
      );
      Navigator.of(context).maybePop();
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa gửi được góp ý. Thử lại sau.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = ref.watch(
      workspaceControllerProvider.select((state) => state.activeWorkspace?.id),
    );
    final canSend =
        workspaceId != null && _message.text.trim().isNotEmpty && !_sending;
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(title: const Text('Gửi góp ý')),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          children: [
            const Text('Bạn muốn góp ý về điều gì?'),
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              children: [
                for (final (value, label) in _categories)
                  ChoiceChip(
                    label: Text(label),
                    selected: _category == value,
                    onSelected: (_) => setState(() => _category = value),
                  ),
              ],
            ),
            const SizedBox(height: WebTuiSpacing.md),
            const Text('Đánh giá ứng dụng (không bắt buộc)'),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    tooltip: '$star sao',
                    onPressed: () => setState(() => _rating = star),
                    icon: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: star <= _rating
                          ? const Color(0xFFF59E0B)
                          : WebTuiColors.textMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            TextField(
              controller: _message,
              minLines: 5,
              maxLines: 10,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Mô tả lỗi gặp phải hoặc tính năng bạn mong muốn...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            FilledButton.icon(
              onPressed: canSend ? () => _send(workspaceId!) : null,
              icon: const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Đang gửi...' : 'Gửi góp ý'),
            ),
          ],
        ),
      ),
    );
  }
}
