import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers/foundation_providers.dart';

/// Mỗi thao tác xác thực riêng; không lưu token ra đĩa hoặc dùng lại sau đổi tài khoản.
Future<String?> requestReauthToken(
  BuildContext context,
  WidgetRef ref, {
  String? reason,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReauthDialog(reason: reason),
);

/// Không có token được giữ ngoài phạm vi thao tác hiện tại.
void clearReauthToken(WidgetRef ref) {}

class _ReauthDialog extends ConsumerStatefulWidget {
  const _ReauthDialog({this.reason});
  final String? reason;
  @override
  ConsumerState<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends ConsumerState<_ReauthDialog> {
  final _value = TextEditingController();
  final _focus = FocusNode();
  String _method = 'password';
  String? _error;
  bool _busy = false;
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
        .authenticate(reason: 'Mở ô xác thực lại');
    if (mounted && ok) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Xác thực lại'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.reason ?? 'Nhập mật khẩu hoặc mã xác thực để tiếp tục.'),
          DropdownButton<String>(
            value: _method,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'password', child: Text('Mật khẩu')),
              DropdownMenuItem(value: 'totp', child: Text('Mã TOTP')),
              DropdownMenuItem(
                value: 'recovery_code',
                child: Text('Mã khôi phục'),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _method = value;
                        _value.clear();
                        _error = null;
                      });
                    }
                  },
          ),
          TextField(
            controller: _value,
            focusNode: _focus,
            autofocus: true,
            enabled: !_busy,
            obscureText: _method == 'password',
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: _method == 'totp'
                ? TextInputType.number
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: _method == 'password' ? 'Mật khẩu' : 'Mã xác thực',
            ),
            onSubmitted: (_) => _submit(),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _focusWithBiometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Mở ô nhập bằng vân tay'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Huỷ'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Đang kiểm tra…' : 'Xác nhận'),
      ),
    ],
  );
}
