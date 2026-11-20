import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_server_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_tools_common.dart';

final _nameRe = RegExp(r'^[a-z0-9][a-z0-9-]{1,30}$');
final _userRe = RegExp(r'^[a-z_][a-z0-9_.-]{0,31}$');

/// Máy chủ của tôi (Phụ lục C3): danh sách VPS riêng của chính tài khoản.
class IdeServersScreen extends ConsumerStatefulWidget {
  const IdeServersScreen({super.key});

  @override
  ConsumerState<IdeServersScreen> createState() => _IdeServersScreenState();
}

class _IdeServersScreenState extends ConsumerState<IdeServersScreen> {
  int _gen = 0;

  Future<void> _openSheet(IdeServer? server) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ServerSheet(server: server),
    );
    if (done == true && mounted) setState(() => _gen++);
  }

  Future<void> _showKey() async {
    try {
      final key = await ref.read(ideServersServiceProvider).pubkey();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ServerKeySheet(pubkey: key),
      );
    } on Object catch (e) {
      if (mounted) ideToolsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = ideToolsHas(ref, 'servers.add');
    final canKey = ideToolsHas(ref, 'servers.key');
    return IdeMorePage(
      title: tr('Máy chủ của tôi', 'My servers'),
      actions: [
        if (canKey)
          IconButton(
            key: const Key('ide_servers_key'),
            tooltip: tr('Khoá công khai', 'Public key'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: _showKey,
          ),
      ],
      floating: canAdd
          ? FloatingActionButton.extended(
              key: const Key('ide_servers_add'),
              onPressed: () => _openSheet(null),
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm máy chủ', 'Add server')),
            )
          : null,
      body: !ideToolsHas(ref, 'servers.list')
          ? ideToolsUnsupported()
          : IdeLoader<List<IdeServer>>(
              key: ValueKey(_gen),
              load: () => ref.read(ideServersServiceProvider).list(),
              builder: (context, items, reload) {
                if (items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 320,
                          child: WebTuiEmptyState(
                            title: tr('Chưa có máy chủ nào', 'No servers yet'),
                            message: tr(
                              'Thêm VPS của bạn để IDE làm việc trên đó.',
                              'Add your VPS so the IDE can work on it.',
                            ),
                            icon: Icons.dns_outlined,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    key: const Key('ide_servers_list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      WebTuiSpacing.lg,
                      WebTuiSpacing.sm,
                      WebTuiSpacing.lg,
                      96,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: WebTuiSpacing.sm),
                    itemBuilder: (_, i) => _ServerCard(
                      server: items[i],
                      onEdit: () => _openSheet(items[i]),
                      onChanged: reload,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ServerCard extends ConsumerStatefulWidget {
  const _ServerCard({
    required this.server,
    required this.onEdit,
    required this.onChanged,
  });

  final IdeServer server;
  final VoidCallback onEdit;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends ConsumerState<_ServerCard> {
  bool _busy = false;

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(ideServersServiceProvider)
          .check(widget.server.name, isCancelled: () => !mounted);
      if (!mounted) return;
      ideToolsSnack(
        context,
        r.ok
            ? tr('Kết nối tốt', 'Connection OK')
            : (r.message.isEmpty
                  ? tr('Không kết nối được', 'Cannot connect')
                  : ideVisibleText(r.message)),
      );
    } on Object catch (e) {
      if (mounted) ideToolsError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final s = widget.server;
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Gỡ máy chủ?', 'Remove server?'),
      message: tr(
        'Gỡ ${ideVisibleText(s.name)} khỏi tài khoản của bạn.',
        'Remove ${ideVisibleText(s.name)} from your account.',
      ),
      confirmLabel: tr('Gỡ', 'Remove'),
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(ideServersServiceProvider);
      try {
        await svc.remove(s.name);
      } on IdeConflict {
        if (!mounted) return;
        final again = await showWebTuiConfirmDialog(
          context,
          title: tr('Còn dự án đang dùng', 'Projects still use it'),
          message: tr(
            'Một số dự án còn dùng máy chủ này. Vẫn gỡ và bỏ liên kết?',
            'Some projects still use this server. Remove it anyway?',
          ),
          confirmLabel: tr('Vẫn gỡ', 'Remove anyway'),
          destructive: true,
        );
        if (again != true) return;
        await svc.remove(s.name, withProjects: true);
      }
      if (!mounted) return;
      await widget.onChanged();
    } on Object catch (e) {
      if (mounted) ideToolsError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.server;
    final canCheck = ideToolsHas(ref, 'servers.check');
    final canEdit = ideToolsHas(ref, 'servers.edit');
    final canRemove = ideToolsHas(ref, 'servers.remove');
    final title = s.label.isNotEmpty ? s.label : s.name;
    return IdeCard(
      key: Key('ide_server_${s.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                ideVisibleText(title),
                style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
              ),
              IdeTag(
                s.keyOk
                    ? tr('Đã có khoá', 'Key set')
                    : tr('Chưa có khoá', 'No key'),
                color: s.keyOk ? IdeWb.ok : IdeWb.warn,
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          ToolInfoRow(tr('Tên', 'Name'), ideVisibleText(s.name)),
          ToolInfoRow(
            tr('Địa chỉ', 'Address'),
            '${ideVisibleText(s.user)}@${ideVisibleText(s.host)}:${s.port ?? 22}',
          ),
          if (s.fingerprint.isNotEmpty)
            ToolInfoRow(
              tr('Dấu vân tay', 'Fingerprint'),
              ideVisibleText(s.fingerprint),
            ),
          if (s.createdAt != null)
            ToolInfoRow(
              tr('Thêm lúc', 'Added'),
              ideFormatDateTime(s.createdAt!),
            ),
          if (s.projects.isNotEmpty)
            ToolInfoRow(
              tr('Dự án', 'Projects'),
              s.projects.map(ideVisibleText).join(', '),
            ),
          const SizedBox(height: WebTuiSpacing.xs),
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.xs,
            children: [
              if (canCheck)
                OutlinedButton(
                  key: Key('ide_server_check_${s.name}'),
                  style: ideToolsBtn(),
                  onPressed: _busy ? null : _check,
                  child: Text(tr('Kiểm tra', 'Check')),
                ),
              if (canEdit)
                OutlinedButton(
                  key: Key('ide_server_edit_${s.name}'),
                  style: ideToolsBtn(),
                  onPressed: _busy ? null : widget.onEdit,
                  child: Text(tr('Sửa', 'Edit')),
                ),
              if (canRemove)
                OutlinedButton(
                  key: Key('ide_server_remove_${s.name}'),
                  style: ideToolsBtn(color: IdeWb.danger),
                  onPressed: _busy ? null : _remove,
                  child: Text(tr('Gỡ', 'Remove')),
                ),
              if (_busy)
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sheet thêm / sửa máy chủ. Mật khẩu: ô ẩn ký tự; ô được xoá ngay khi gửi, còn
/// chuỗi Dart đã lấy ra không xoá được khỏi bộ nhớ (chỉ bỏ tham chiếu sớm).
class ServerSheet extends ConsumerStatefulWidget {
  const ServerSheet({this.server, super.key});

  final IdeServer? server;

  @override
  ConsumerState<ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends ConsumerState<ServerSheet> {
  late final _name = TextEditingController(text: widget.server?.name ?? '');
  late final _host = TextEditingController(text: widget.server?.host ?? '');
  late final _port = TextEditingController(
    text: '${widget.server?.port ?? 22}',
  );
  late final _user = TextEditingController(text: widget.server?.user ?? 'root');
  late final _label = TextEditingController(text: widget.server?.label ?? '');
  final _pass = TextEditingController();
  bool _sending = false;
  bool _monitor = true;
  String? _error;
  String? _pubkey;
  final _fieldErr = <String, String>{};

  bool get _edit => widget.server != null;

  @override
  void dispose() {
    _pass.clear();
    for (final c in [_name, _host, _port, _user, _label, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    _fieldErr.clear();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (!_edit &&
        _name.text.trim().isNotEmpty &&
        !_nameRe.hasMatch(_name.text.trim())) {
      _fieldErr['name'] = tr(
        '2–31 ký tự a-z, 0-9, dấu gạch',
        '2–31 chars a-z, 0-9, dash',
      );
    }
    if (host.isEmpty || host.length > 253 || host.contains(RegExp(r'\s'))) {
      _fieldErr['host'] = tr('Địa chỉ không hợp lệ', 'Invalid address');
    }
    if (port == null || port < 1 || port > 65535) {
      _fieldErr['port'] = tr('Cổng 1–65535', 'Port 1–65535');
    }
    if (!_userRe.hasMatch(_user.text.trim())) {
      _fieldErr['user'] = tr('Tên người dùng không hợp lệ', 'Invalid user');
    }
    if (_label.text.trim().length > 120) {
      _fieldErr['label'] = tr('Tối đa 120 ký tự', 'At most 120 chars');
    }
    return _fieldErr.isEmpty;
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (!_validate()) {
      setState(() {});
      return;
    }
    final svc = ref.read(ideServersServiceProvider);
    final host = _host.text.trim();
    final port = int.parse(_port.text.trim());
    final user = _user.text.trim();
    final label = _label.text.trim();
    // Lấy mật khẩu rồi xoá ô ngay, trước khi chờ mạng.
    final pw = _pass.text;
    _pass.clear();
    setState(() {
      _sending = true;
      _error = null;
      _pubkey = null;
    });
    try {
      final s = widget.server;
      final r = s == null
          ? await svc.add(
              name: _name.text.trim(),
              host: host,
              port: port,
              user: user,
              label: label,
              password: pw,
              monitor: _monitor,
              isCancelled: () => !mounted,
            )
          : await svc.edit(
              s.name,
              label: label == s.label ? null : label,
              host: host == s.host ? null : host,
              port: port == s.port ? null : port,
              user: user == s.user ? null : user,
              password: pw,
              isCancelled: () => !mounted,
            );
      if (!mounted) return;
      if (r.ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _sending = false;
        _error = r.message.isEmpty
            ? tr('Không hoàn tất được.', 'Could not finish.')
            : ideVisibleText(r.message);
      });
    } on Object catch (e) {
      String? key;
      if (!_edit && pw.isEmpty && e is IdeBadRequest && e.hint == 'pubkey') {
        try {
          key = await svc.pubkey();
        } on Object {
          key = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = ideMoreErrorText(e);
        _pubkey = (key != null && key.isNotEmpty) ? key : null;
      });
    }
  }

  Widget _field(
    String id,
    TextEditingController c,
    String label, {
    TextInputType? type,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: TextField(
        key: Key('ide_server_f_$id'),
        controller: c,
        enabled: !_sending,
        obscureText: obscure,
        enableSuggestions: !obscure,
        autocorrect: false,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          errorText: _fieldErr[id],
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: !_sending,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.lg,
          WebTuiSpacing.lg,
          WebTuiSpacing.lg + bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _edit
                  ? tr('Sửa máy chủ', 'Edit server')
                  : tr('Thêm máy chủ', 'Add server'),
              style: IdeType.titleLarge.copyWith(color: IdeWb.textStrong),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            if (!_edit)
              _field(
                'name',
                _name,
                tr('Tên (không bắt buộc)', 'Name (optional)'),
              ),
            _field(
              'host',
              _host,
              tr('Địa chỉ máy chủ', 'Host'),
              type: TextInputType.url,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    'port',
                    _port,
                    tr('Cổng', 'Port'),
                    type: TextInputType.number,
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  flex: 2,
                  child: _field('user', _user, tr('Người dùng', 'User')),
                ),
              ],
            ),
            _field('label', _label, tr('Nhãn', 'Label')),
            _field(
              'password',
              _pass,
              _edit
                  ? tr(
                      'Mật khẩu mới (bỏ trống nếu giữ)',
                      'New password (blank to keep)',
                    )
                  : tr(
                      'Mật khẩu SSH (chỉ dùng một lần)',
                      'SSH password (used once)',
                    ),
              obscure: true,
            ),
            if (!_edit)
              SwitchListTile(
                key: const Key('ide_server_f_monitor'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Bật giám sát', 'Enable monitoring')),
                value: _monitor,
                onChanged: _sending
                    ? null
                    : (v) => setState(() => _monitor = v),
              ),
            Text(
              tr(
                'Mật khẩu không được lưu; chỉ dùng để cài khoá SSH rồi bỏ.',
                'The password is not stored; it only installs the SSH key.',
              ),
              style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Text(
                  _error!,
                  key: const Key('ide_server_error'),
                  style: IdeType.bodyMedium.copyWith(color: IdeWb.danger),
                ),
              ),
            if (_pubkey != null)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: _KeyBox(pubkey: _pubkey!),
              ),
            const SizedBox(height: WebTuiSpacing.md),
            FilledButton(
              key: const Key('ide_server_submit'),
              style: ideToolsFilledBtn(),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_edit ? tr('Lưu', 'Save') : tr('Thêm', 'Add')),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyBox extends StatelessWidget {
  const _KeyBox({required this.pubkey});

  final String pubkey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            'Chưa vào được bằng khoá. Thêm khoá công khai này vào authorized_keys của máy chủ rồi thử lại:',
            'Key login failed. Add this public key to the server authorized_keys and retry:',
          ),
          style: IdeType.bodySmall.copyWith(color: IdeWb.text),
        ),
        const SizedBox(height: WebTuiSpacing.xs),
        SelectableText(
          pubkey,
          key: const Key('ide_server_pubkey'),
          style: IdeType.bodySmall.copyWith(
            fontFamily: WebTuiTypography.monoFamily,
            color: IdeWb.textStrong,
          ),
        ),
        TextButton.icon(
          key: const Key('ide_server_pubkey_copy'),
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: () => ideToolsCopy(context, pubkey),
          icon: const Icon(Icons.copy, size: 18),
          label: Text(tr('Chép khoá', 'Copy key')),
        ),
      ],
    );
  }
}

class ServerKeySheet extends StatelessWidget {
  const ServerKeySheet({required this.pubkey, super.key});

  final String pubkey;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: pubkey.isEmpty
          ? Text(tr('Chưa có khoá công khai.', 'No public key yet.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Khoá công khai SSH của bạn', 'Your SSH public key'),
                  style: IdeType.titleLarge.copyWith(color: IdeWb.textStrong),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                _KeyBox(pubkey: pubkey),
              ],
            ),
    );
  }
}
