import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/foundation_providers.dart';
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
    final token = await requestReauthToken(
      context,
      ref,
      reason: enable ? 'Bật mã xác thực TOTP' : 'Tắt mã xác thực TOTP',
    );
    if (!mounted || token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = ref.read(mfaUseCasesProvider);
    if (enable) {
      final result = await service.enroll(token);
      if (!mounted) return;
      setState(() {
        _enrollment = result.valueOrNull;
        _error = result.failureOrNull?.message;
        _busy = false;
      });
    } else {
      final result = await service.disable(token);
      if (!mounted) return;
      setState(() {
        _error = result.failureOrNull?.message;
        _busy = false;
        _recoveryCodes = null;
      });
      if (result.isSuccess) await _load();
    }
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
    appBar: AppBar(title: const Text('Xác thực TOTP')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: _load, child: const Text('Thử lại')),
        ],
        if (_status == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_status != null && !_status!.enabled)
          const Text('Máy chủ chưa bật tính năng xác thực TOTP.'),
        if (_status?.enabled == true && _enrollment == null) ...[
          Text(_status!.totpEnabled ? 'TOTP đang bật.' : 'TOTP chưa bật.'),
          FilledButton(
            onPressed: _busy ? null : () => _change(!_status!.totpEnabled),
            child: Text(_status!.totpEnabled ? 'Tắt TOTP' : 'Bật TOTP'),
          ),
        ],
        if (_enrollment != null) ...[
          const Text(
            'Nhập khoá bên dưới vào ứng dụng xác thực, rồi nhập mã 6 số để hoàn tất.',
          ),
          SelectableText(_enrollment!.secret),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Mã TOTP 6 số'),
          ),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: const Text('Xác nhận bật TOTP'),
          ),
        ],
        if (_recoveryCodes != null) ...[
          const Text(
            'Lưu các mã khôi phục ở nơi an toàn. Mỗi mã chỉ dùng một lần; chúng không được lưu trong ứng dụng.',
          ),
          SelectableText(_recoveryCodes!.join('\n')),
          TextButton(
            onPressed: () => setState(() => _recoveryCodes = null),
            child: const Text('Đã lưu mã'),
          ),
        ],
      ],
    ),
  );
}
