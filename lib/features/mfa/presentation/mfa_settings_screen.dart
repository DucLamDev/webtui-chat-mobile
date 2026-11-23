import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/foundation_providers.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/app_strings.dart';
import '../domain/mfa_repository.dart';
import 'reauth_prompt.dart';

class MfaSettingsScreen extends ConsumerStatefulWidget {
  const MfaSettingsScreen({super.key});
  @override
  ConsumerState<MfaSettingsScreen> createState() => _MfaSettingsScreenState();
}

class _MfaSettingsScreenState extends ConsumerState<MfaSettingsScreen> {
  final _code = TextEditingController();
  MfaStatus? _status;
  TotpEnrollment? _enrollment;
  List<String>? _recoveryCodes;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ref.read(mfaUseCasesProvider).status();
    if (!mounted) return;
    setState(() {
      _status = result.valueOrNull;
      _error = result.failureOrNull?.message;
    });
  }

  Future<void> _change(bool enable) async {
    final reason = enable
        ? tr('Bật mã xác thực TOTP', 'Turn on TOTP verification')
        : tr('Tắt mã xác thực TOTP', 'Turn off TOTP verification');
    // Tắt TOTP: tài khoản đang có yếu tố thứ hai nên máy chủ bắt buộc xác thực
    // lại bằng mã, không nhận token chỉ từ mật khẩu.
    var secondFactorOnly = !enable;
    final service = ref.read(mfaUseCasesProvider);
    while (true) {
      if (!mounted) return;
      final token = await requestReauthToken(
        context,
        ref,
        reason: reason,
        secondFactorOnly: secondFactorOnly,
      );
      if (!mounted || token == null) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      if (enable) {
        final result = await service.enroll(token);
        if (!mounted) return;
        if (_needsSecondFactor(result.failureOrNull, secondFactorOnly)) {
          secondFactorOnly = true;
          setState(() => _busy = false);
          continue;
        }
        setState(() {
          _enrollment = result.valueOrNull;
          _error = _failureMessage(result.failureOrNull);
          _busy = false;
        });
      } else {
        final result = await service.disable(token);
        if (!mounted) return;
        if (_needsSecondFactor(result.failureOrNull, secondFactorOnly)) {
          secondFactorOnly = true;
          setState(() => _busy = false);
          continue;
        }
        setState(() {
          _error = _failureMessage(result.failureOrNull);
          _busy = false;
          _recoveryCodes = null;
        });
        if (result.isSuccess) await _load();
      }
      return;
    }
  }

  /// Token chỉ từ mật khẩu bị từ chối: hỏi lại một lần bằng yếu tố thứ hai.
  bool _needsSecondFactor(Failure? failure, bool alreadySecondFactor) =>
      !alreadySecondFactor &&
      failure != null &&
      failure.hasCode(reauthSecondFactorRequiredCode);

  String? _failureMessage(Failure? failure) {
    if (failure == null) return null;
    if (failure.hasCode(reauthSecondFactorRequiredCode)) {
      return tr(
        'Cần xác thực lại bằng mã từ ứng dụng xác thực hoặc mã khôi phục. '
            'Nếu tài khoản chỉ có passkey, hãy làm thao tác này trên web.',
        'Verify again with an authenticator app code or a recovery code. '
            'If the account only has a passkey, do this on the web.',
      );
    }
    return failure.message;
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(mfaUseCasesProvider)
        .confirm(_code.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.failureOrNull?.message;
      if (result.isSuccess) {
        _enrollment = null;
        _code.clear();
        _recoveryCodes = result.valueOrNull;
      }
    });
    if (result.isSuccess) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Xác thực TOTP', 'TOTP verification'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: _load, child: Text(tr('Thử lại', 'Retry'))),
        ],
        if (_status == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_status != null && !_status!.enabled)
          Text(
            tr(
              'Máy chủ chưa bật tính năng xác thực TOTP.',
              'The server has not enabled TOTP verification.',
            ),
          ),
        if (_status?.enabled == true && _enrollment == null) ...[
          Text(
            _status!.totpEnabled
                ? tr('TOTP đang bật.', 'TOTP is on.')
                : tr('TOTP chưa bật.', 'TOTP is off.'),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _change(!_status!.totpEnabled),
            child: Text(
              _status!.totpEnabled
                  ? tr('Tắt TOTP', 'Turn off TOTP')
                  : tr('Bật TOTP', 'Turn on TOTP'),
            ),
          ),
        ],
        if (_enrollment != null) ...[
          Text(
            tr(
              'Nhập khoá bên dưới vào ứng dụng xác thực, rồi nhập mã 6 số để hoàn tất.',
              'Enter the key below in your authenticator app, then enter the 6-digit code to finish.',
            ),
          ),
          SelectableText(_enrollment!.secret),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: tr('Mã TOTP 6 số', '6-digit TOTP code'),
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: Text(tr('Xác nhận bật TOTP', 'Confirm turning on TOTP')),
          ),
        ],
        if (_recoveryCodes != null) ...[
          Text(
            tr(
              'Lưu các mã khôi phục ở nơi an toàn. Mỗi mã chỉ dùng một lần; chúng không được lưu trong ứng dụng.',
              'Keep your recovery codes somewhere safe. Each code can be used once; they are not stored in the app.',
            ),
          ),
          SelectableText(_recoveryCodes!.join('\n')),
          TextButton(
            onPressed: () => setState(() => _recoveryCodes = null),
            child: Text(tr('Đã lưu mã', 'I saved the codes')),
          ),
        ],
      ],
    ),
  );
}
