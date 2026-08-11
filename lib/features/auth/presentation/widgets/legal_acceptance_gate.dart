import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/flavor/app_config.dart';
import '../../../../app/providers/foundation_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../controllers/legal_acceptance_controller.dart';

class LegalAcceptanceGate extends ConsumerStatefulWidget {
  const LegalAcceptanceGate({
    required this.accessToken,
    required this.serverUri,
    this.workspaceId,
    required this.child,
    super.key,
  });

  final String? accessToken;
  final Uri serverUri;
  final String? workspaceId;
  final Widget child;

  @override
  ConsumerState<LegalAcceptanceGate> createState() =>
      _LegalAcceptanceGateState();
}

class _LegalAcceptanceGateState extends ConsumerState<LegalAcceptanceGate> {
  bool _sessionUpdateScheduled = false;
  bool _loggingOut = false;

  bool get _authenticated => widget.accessToken?.trim().isNotEmpty == true;
  String? get _workspaceId {
    final value = widget.workspaceId?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  bool get _sessionReady => _authenticated && _workspaceId != null;

  String _scopeFor(LegalAcceptanceGate value) {
    final uri = value.serverUri;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final usesDefaultPort =
        (scheme == 'https' && uri.port == 443) ||
        (scheme == 'http' && uri.port == 80);
    final port = uri.hasPort && !usesDefaultPort ? ':${uri.port}' : '';
    final path = uri.path == '/'
        ? ''
        : uri.path.replaceFirst(RegExp(r'/$'), '');
    return '$scheme://$host$port$path|${value.accessToken?.trim() ?? ''}|'
        '${value.workspaceId?.trim() ?? ''}';
  }

  @override
  void initState() {
    super.initState();
    if (_authenticated) _scheduleSessionUpdate();
  }

  @override
  void didUpdateWidget(covariant LegalAcceptanceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldScope = _scopeFor(oldWidget);
    final newScope = _scopeFor(widget);
    if (oldScope == newScope) return;
    _scheduleSessionUpdate();
  }

  void _scheduleSessionUpdate() {
    if (_sessionUpdateScheduled) return;
    _sessionUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionUpdateScheduled = false;
      if (!mounted) return;
      final controller = ref.read(legalAcceptanceControllerProvider.notifier);
      final workspaceId = _workspaceId;
      if (_authenticated && workspaceId != null) {
        unawaited(controller.beginSession(workspaceId: workspaceId));
      } else {
        controller.endSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_authenticated) return widget.child;
    final state = ref.watch(legalAcceptanceControllerProvider);
    if (state.status == LegalAcceptanceStatus.idle && _sessionReady) {
      _scheduleSessionUpdate();
    }
    if (state.canCreateUserContent) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!state.gateVisible)
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Material(
                color: const Color(0xFFFFF4D8),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.md,
                    vertical: WebTuiSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined, size: 20),
                      const SizedBox(width: WebTuiSpacing.sm),
                      const Expanded(
                        child: Text(
                          'Chế độ chỉ đọc: cần đồng ý chính sách trước khi tạo nội dung.',
                        ),
                      ),
                      TextButton(
                        key: const Key('legal_gate_open'),
                        onPressed: () => ref
                            .read(legalAcceptanceControllerProvider.notifier)
                            .openGate(),
                        child: const Text('Xem lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (state.gateVisible) ...[
          const ModalBarrier(dismissible: false, color: Color(0x9907111F)),
          SafeArea(
            child: Center(
              child: _LegalAcceptancePanel(
                state: state,
                loggingOut: _loggingOut,
                onOpenTerms: () => _openLegalDocument(
                  ref.read(appConfigProvider).termsUrl,
                  'Điều khoản sử dụng',
                ),
                onOpenPrivacy: () => _openLegalDocument(
                  ref.read(appConfigProvider).privacyPolicyUrl,
                  'Chính sách quyền riêng tư',
                ),
                onAcceptedChanged: ref
                    .read(legalAcceptanceControllerProvider.notifier)
                    .setAcceptedBoth,
                onAccept: () => unawaited(
                  ref.read(legalAcceptanceControllerProvider.notifier).accept(),
                ),
                onRetry: () => unawaited(
                  ref.read(legalAcceptanceControllerProvider.notifier).retry(),
                ),
                onReadOnly: ref
                    .read(legalAcceptanceControllerProvider.notifier)
                    .dismissToReadOnly,
                onSettings: () => _openAllowedRoute('/settings'),
                onPrivacyAndAccount: () => _openAllowedRoute('/privacy'),
                onLogout: _loggingOut ? null : () => unawaited(_logout()),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openAllowedRoute(String location) {
    ref.read(legalAcceptanceControllerProvider.notifier).dismissToReadOnly();
    ref.read(appRouterProvider).go(location);
  }

  Future<void> _openLegalDocument(String url, String label) async {
    final opened = await ref.read(externalUrlLauncherProvider).open(url);
    if (!mounted || opened) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('Không mở được $label.')));
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      try {
        await ref.read(pushNotificationServiceProvider).unregister();
      } on Object {
        // Local logout remains available if push cleanup is unavailable.
      }
      await ref.read(logoutUseCaseProvider).execute();
      ref.read(legalAcceptanceControllerProvider.notifier).endSession();
      ref.invalidate(authAccessTokenProvider);
      if (mounted) ref.read(appRouterProvider).go('/login');
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }
}

class _LegalAcceptancePanel extends ConsumerWidget {
  const _LegalAcceptancePanel({
    required this.state,
    required this.loggingOut,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    required this.onAcceptedChanged,
    required this.onAccept,
    required this.onRetry,
    required this.onReadOnly,
    required this.onSettings,
    required this.onPrivacyAndAccount,
    required this.onLogout,
  });

  final LegalAcceptanceState state;
  final bool loggingOut;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final ValueChanged<bool> onAcceptedChanged;
  final VoidCallback onAccept;
  final VoidCallback onRetry;
  final VoidCallback onReadOnly;
  final VoidCallback onSettings;
  final VoidCallback onPrivacyAndAccount;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final isRequired = state.status == LegalAcceptanceStatus.required;
    final isLoading =
        state.status == LegalAcceptanceStatus.idle ||
        state.status == LegalAcceptanceStatus.loading;
    final isSubmitting = state.status == LegalAcceptanceStatus.submitting;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Card(
          margin: const EdgeInsets.all(WebTuiSpacing.lg),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WebTuiSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.policy_outlined, size: 44),
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  'Điều khoản và quyền riêng tư',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                const Text(
                  'Tài khoản cũ cần xác nhận chính sách hiện hành trước khi gửi tin nhắn, tải tệp, tạo kênh hoặc bắt đầu/nhận cuộc gọi. Bạn vẫn có thể đọc, báo cáo, chặn, mở Cài đặt, xóa tài khoản hoặc đăng xuất.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WebTuiSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('legal_gate_terms_link'),
                      onPressed: onOpenTerms,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text('Điều khoản · ${config.termsVersion}'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('legal_gate_privacy_link'),
                      onPressed: onOpenPrivacy,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(
                        'Quyền riêng tư · ${config.privacyPolicyVersion}',
                      ),
                    ),
                  ],
                ),
                if (isLoading || isSubmitting) ...[
                  const SizedBox(height: WebTuiSpacing.xl),
                  Center(
                    key: const Key('legal_gate_loading'),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: WebTuiSpacing.sm),
                        Text(
                          isSubmitting
                              ? 'Đang ghi nhận lựa chọn...'
                              : 'Đang kiểm tra trạng thái chính sách...',
                        ),
                      ],
                    ),
                  ),
                ] else if (isRequired) ...[
                  const SizedBox(height: WebTuiSpacing.lg),
                  CheckboxListTile(
                    key: const Key('legal_gate_checkbox'),
                    value: state.acceptedBoth,
                    onChanged: (value) => onAcceptedChanged(value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Tôi đã đọc và đồng ý Điều khoản sử dụng cùng Chính sách quyền riêng tư.',
                    ),
                  ),
                  const SizedBox(height: WebTuiSpacing.sm),
                  FilledButton.icon(
                    key: const Key('legal_gate_accept'),
                    onPressed: state.acceptedBoth ? onAccept : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Đồng ý và tiếp tục'),
                  ),
                ] else ...[
                  const SizedBox(height: WebTuiSpacing.lg),
                  FilledButton.icon(
                    key: const Key('legal_gate_retry'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử kiểm tra lại'),
                  ),
                ],
                if (state.errorMessage case final error?) ...[
                  const SizedBox(height: WebTuiSpacing.md),
                  Text(
                    error,
                    key: const Key('legal_gate_error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: WebTuiSpacing.lg),
                const Divider(),
                const SizedBox(height: WebTuiSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.sm,
                  children: [
                    TextButton.icon(
                      key: const Key('legal_gate_settings'),
                      onPressed: onSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Cài đặt'),
                    ),
                    TextButton.icon(
                      key: const Key('legal_gate_account'),
                      onPressed: onPrivacyAndAccount,
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text('Tài khoản & xóa dữ liệu'),
                    ),
                    TextButton.icon(
                      key: const Key('legal_gate_logout'),
                      onPressed: onLogout,
                      icon: loggingOut
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.logout),
                      label: const Text('Đăng xuất'),
                    ),
                  ],
                ),
                if (!state.isBusy) ...[
                  const SizedBox(height: WebTuiSpacing.sm),
                  TextButton(
                    key: const Key('legal_gate_read_only'),
                    onPressed: onReadOnly,
                    child: const Text('Tiếp tục ở chế độ chỉ đọc'),
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
