import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../core/privacy/background_privacy.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/icons/webtui_icons.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../mfa/presentation/reauth_prompt.dart';
import '../../../domain/entities/chat_message.dart';

class SecretMessageComposer extends ConsumerWidget {
  const SecretMessageComposer({
    required this.workspaceId,
    required this.channelId,
    required this.onSent,
    super.key,
  });
  final String workspaceId;
  final String channelId;
  final VoidCallback onSent;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(activeServerDiscoveryProvider)?.capabilities.secretMessages !=
        true) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      icon: const Icon(WebTuiIcons.lock),
      label: const Text('Bí mật 24h'),
      onPressed: () async {
        final sent = await showDialog<bool>(
          context: context,
          builder: (_) =>
              _SecretComposer(workspaceId: workspaceId, channelId: channelId),
        );
        if (sent == true) onSent();
      },
    );
  }
}

class _SecretComposer extends ConsumerStatefulWidget {
  const _SecretComposer({required this.workspaceId, required this.channelId});
  final String workspaceId;
  final String channelId;
  @override
  ConsumerState<_SecretComposer> createState() => _SecretComposerState();
}

class _SecretComposerState extends ConsumerState<_SecretComposer> {
  final _body = TextEditingController();
  String _clientId = const Uuid().v4();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _body.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(secretMessageUseCasesProvider)
        .send(widget.workspaceId, widget.channelId, _body.text, _clientId);
    if (!mounted) return;
    if (result.isSuccess) {
      _body.clear();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = result.failureOrNull!.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => WebTuiDialog(
    title: 'Tin bí mật 24h',
    message: 'Chỉ gửi chữ. Không lưu bản nháp hoặc hàng chờ offline.',
    icon: WebTuiIcons.lock,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _body,
          autofocus: true,
          enabled: !_busy,
          maxLength: 8000,
          minLines: 2,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Nội dung tin bí mật'),
          onChanged: (_) => _clientId = const Uuid().v4(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: WebTuiColors.danger),
            ),
          ),
      ],
    ),
    actions: [
      WebTuiDialogAction(
        label: 'Huỷ',
        onPressed: _busy ? null : () => Navigator.pop(context),
      ),
      WebTuiDialogAction(
        label: _busy ? 'Đang gửi…' : 'Gửi',
        primary: true,
        onPressed: _busy ? null : _send,
      ),
    ],
  );
}

class SecretMessageBubble extends ConsumerStatefulWidget {
  const SecretMessageBubble({required this.message, super.key});
  final ChatMessage message;
  @override
  ConsumerState<SecretMessageBubble> createState() =>
      _SecretMessageBubbleState();
}

class _SecretMessageBubbleState extends ConsumerState<SecretMessageBubble> {
  Timer? _timer;
  bool _busy = false;
  String? _error;
  bool get _expired =>
      widget.message.expiresAt == null ||
      !DateTime.now().isBefore(widget.message.expiresAt!);
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reveal() async {
    final token = await requestReauthToken(
      context,
      ref,
      reason: 'Xem tin bí mật trong tối đa 60 giây',
    );
    if (!mounted || token == null || _expired) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final useCases = ref.read(secretMessageUseCasesProvider);
    final message = widget.message;
    final result = await useCases.reveal(
      message.workspaceId,
      message.channelId,
      message.id,
      token,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (_expired ||
        !identical(useCases, ref.read(secretMessageUseCasesProvider))) {
      return;
    }
    if (result.isFailure) {
      setState(() => _error = result.failureOrNull!.message);
      return;
    }
    const privacy = BackgroundPrivacyController();
    await privacy.setSecureScreen(true);
    try {
      if (mounted && !_expired) {
        await showDialog<void>(
          context: context,
          builder: (_) => _SecretReveal(
            body: result.valueOrNull!,
            expiresAt: message.expiresAt!,
          ),
        );
      }
    } finally {
      await privacy.setSecureScreen(false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_expired ? 'Tin bí mật đã hết hạn' : 'Tin nhắn bí mật'),
          if (!_expired)
            Text(
              'Còn ${(widget.message.expiresAt!.difference(DateTime.now()).inSeconds / 60).ceil()} phút',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!_expired)
            TextButton(
              onPressed: _busy ? null : _reveal,
              child: Text(_busy ? 'Đang mở…' : 'Xem'),
            ),
        ],
      ),
    ),
  );
}

class _SecretReveal extends StatefulWidget {
  const _SecretReveal({required this.body, required this.expiresAt});
  final String body;
  final DateTime expiresAt;
  @override
  State<_SecretReveal> createState() => _SecretRevealState();
}

class _SecretRevealState extends State<_SecretReveal>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ttl = widget.expiresAt.difference(DateTime.now());
    _timer = Timer(
      ttl < const Duration(seconds: 60) ? ttl : const Duration(seconds: 60),
      _conceal,
    );
  }

  void _conceal() {
    if (mounted) Navigator.pop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _conceal();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebTuiDialog(
    title: 'Tin bí mật',
    icon: WebTuiIcons.lock,
    content: Text(widget.body),
    actions: [
      WebTuiDialogAction(
        label: 'Đóng',
        primary: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}
