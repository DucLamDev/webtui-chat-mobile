import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/foundation_providers.dart';
import '../../../design_system/components/webtui_components.dart';
import '../../../design_system/icons/webtui_icons.dart';
import '../../../design_system/tokens/webtui_spacing.dart';
import '../../../l10n/app_strings.dart';

/// Mã lỗi khi thao tác đổi yếu tố xác thực cần token xác thực lại bằng yếu tố
/// thứ hai (mã ứng dụng xác thực / mã khôi phục), không chỉ mật khẩu.
const reauthSecondFactorRequiredCode = 'REAUTH_SECOND_FACTOR_REQUIRED';

/// Mỗi thao tác xác thực riêng; không lưu token ra đĩa hoặc dùng lại sau đổi tài khoản.
///
/// [secondFactorOnly]: chỉ cho nhập mã OTP / mã khôi phục (bắt buộc bước xác
/// thực hai lớp cho thao tác đổi yếu tố xác thực).
Future<String?> requestReauthToken(
  BuildContext context,
  WidgetRef ref, {
  String? reason,
  bool secondFactorOnly = false,
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _ReauthDialog(reason: reason, secondFactorOnly: secondFactorOnly),
);

class _ReauthDialog extends ConsumerStatefulWidget {
  const _ReauthDialog({this.reason, this.secondFactorOnly = false});
  final String? reason;
  final bool secondFactorOnly;
  @override
  ConsumerState<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends ConsumerState<_ReauthDialog> {
  final _value = TextEditingController();
  final _focus = FocusNode();
  late String _method = widget.secondFactorOnly ? 'totp' : 'password';
  String? _error;
  bool _busy = false;
  bool _showPassword = false;
  @override
  void dispose() {
    _value.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _value.text.isEmpty) return;
    final useCases = ref.read(mfaUseCasesProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await useCases.reauthenticate(_method, _value.text);
    if (!mounted) return;
    // Không nhận kết quả của máy chủ/tài khoản đã rời trong lúc chờ.
    if (!identical(useCases, ref.read(mfaUseCasesProvider))) {
      Navigator.pop(context);
      return;
    }
    result.when(
      success: (token) => Navigator.pop(context, token),
      failure: (failure) {
        setState(() {
          _busy = false;
          _error = failure.message;
          _value.clear();
        });
      },
    );
  }

  Future<void> _focusWithBiometric() async {
    final ok = await ref
        .read(biometricAuthServiceProvider)
        .authenticate(
          reason: tr('Mở ô xác thực lại', 'Open re-authentication'),
        );
    if (mounted && ok) _focus.requestFocus();
  }

  List<(String, String)> get _methods => [
    if (!widget.secondFactorOnly) ('password', tr('Mật khẩu', 'Password')),
    ('totp', tr('Mã OTP', 'OTP code')),
    ('recovery_code', tr('Khôi phục', 'Recovery')),
  ];

  @override
  Widget build(BuildContext context) {
    final password = _method == 'password';
    return WebTuiDialog(
      title: tr('Xác thực lại', 'Verify again'),
      message:
          widget.reason ??
          (widget.secondFactorOnly
              ? tr(
                  'Nhập mã từ ứng dụng xác thực hoặc mã khôi phục để tiếp tục.',
                  'Enter a code from your authenticator app or a recovery code to continue.',
                )
              : tr(
                  'Nhập mật khẩu hoặc mã xác thực để tiếp tục.',
                  'Enter your password or verification code to continue.',
                )),
      icon: WebTuiIcons.lock,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            key: const Key('reauth_method'),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            segments: [
              for (final (value, label) in _methods)
                ButtonSegment<String>(
                  value: value,
                  label: Text(label, maxLines: 1),
                ),
            ],
            selected: {_method},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() {
                    _method = value.first;
                    _value.clear();
                    _error = null;
                    _showPassword = false;
                  }),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          WebTuiDialogTextField(
            key: const Key('reauth_input'),
            controller: _value,
            focusNode: _focus,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            label: password
                ? tr('Mật khẩu', 'Password')
                : tr('Mã xác thực', 'Verification code'),
            autofocus: true,
            obscureText: password && !_showPassword,
            keyboardType: _method == 'totp'
                ? TextInputType.number
                : TextInputType.text,
            errorText: _error,
            prefixIcon: password ? WebTuiIcons.key : WebTuiIcons.shieldCheck,
            suffix: password
                ? IconButton(
                    key: const Key('reauth_toggle_password'),
                    tooltip: _showPassword
                        ? tr('Ẩn mật khẩu', 'Hide password')
                        : tr('Hiện mật khẩu', 'Show password'),
                    icon: Icon(
                      _showPassword ? WebTuiIcons.lock : WebTuiIcons.view,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  )
                : null,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          Align(
            child: TextButton.icon(
              key: const Key('reauth_biometric'),
              onPressed: _busy ? null : _focusWithBiometric,
              icon: const Icon(WebTuiIcons.fingerprint, size: 20),
              label: Text(tr('Mở ô nhập bằng vân tay', 'Use fingerprint')),
            ),
          ),
        ],
      ),
      actions: [
        WebTuiDialogAction(
          key: const Key('reauth_cancel'),
          label: tr('Huỷ', 'Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        WebTuiDialogAction(
          key: const Key('reauth_confirm'),
          label: tr('Xác nhận', 'Confirm'),
          primary: true,
          loading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
