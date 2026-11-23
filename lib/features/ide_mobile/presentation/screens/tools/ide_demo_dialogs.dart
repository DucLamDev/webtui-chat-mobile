import 'package:flutter/material.dart';

import '../../../../../core/privacy/background_privacy.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_demo_models.dart';
import '../../widgets/ide_wb.dart';
import 'ide_tools_common.dart';

/// Giá trị người dùng nhập khi bật / sửa web demo.
final class DemoConfigInput {
  const DemoConfigInput({
    required this.server,
    required this.root,
    required this.public,
    required this.branch,
  });

  final String server;
  final String root;
  final bool public;
  final String branch;
}

final _rootRe = RegExp(
  r'^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}(/[A-Za-z0-9_][A-Za-z0-9._-]{0,63}){0,7}$',
);
final _branchRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$');

/// Thư mục gốc rỗng = gốc dự án; còn lại đúng mẫu hợp đồng, không `..`.
bool ideDemoRootOk(String v) =>
    v.isEmpty || (_rootRe.hasMatch(v) && !v.contains('..'));

bool ideDemoBranchOk(String v) =>
    v.isEmpty ||
    (_branchRe.hasMatch(v) && !v.contains('..') && !v.endsWith('/'));

Future<DemoConfigInput?> showDemoConfigSheet(
  BuildContext context, {
  required IdeDemoStatus status,
  required bool isGit,
  required bool editing,
}) => showModalBottomSheet<DemoConfigInput>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _DemoConfigSheet(status: status, isGit: isGit, editing: editing),
);

class _DemoConfigSheet extends StatefulWidget {
  const _DemoConfigSheet({
    required this.status,
    required this.isGit,
    required this.editing,
  });

  final IdeDemoStatus status;
  final bool isGit;
  final bool editing;

  @override
  State<_DemoConfigSheet> createState() => _DemoConfigSheetState();
}

class _DemoConfigSheetState extends State<_DemoConfigSheet> {
  late final TextEditingController _root;
  late final TextEditingController _branch;
  late String _server;
  late bool _public;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final s = widget.status;
    _root = TextEditingController(text: widget.editing ? s.root : '');
    _branch = TextEditingController(text: widget.editing ? s.branch : '');
    _server = s.server == 'apache' ? 'apache' : 'nginx';
    _public = widget.editing && s.public;
  }

  @override
  void dispose() {
    _root.dispose();
    _branch.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    final root = _root.text.trim();
    final branch = _branch.text.trim();
    if (!ideDemoRootOk(root) || !ideDemoBranchOk(branch)) {
      setState(() {});
      return;
    }
    _submitted = true;
    Navigator.of(context).pop(
      DemoConfigInput(
        server: _server,
        root: root,
        public: _public,
        branch: branch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final rootBad = !ideDemoRootOk(_root.text.trim());
    final branchBad = !ideDemoBranchOk(_branch.text.trim());
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: WebTuiSpacing.lg,
          right: WebTuiSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + WebTuiSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.editing
                    ? tr('Sửa cấu hình web demo', 'Edit web demo')
                    : tr('Bật web demo', 'Turn on web demo'),
                style: IdeType.titleLarge.copyWith(color: IdeWb.textStrong),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              if (!s.my) ...[
                Text(tr('Máy chủ web', 'Web server'), style: IdeType.bodySmall),
                const SizedBox(height: WebTuiSpacing.xs),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'nginx', label: Text('nginx')),
                    ButtonSegment(value: 'apache', label: Text('apache')),
                  ],
                  selected: {_server},
                  onSelectionChanged: (v) => setState(() => _server = v.first),
                ),
                const SizedBox(height: WebTuiSpacing.md),
              ],
              TextField(
                key: const Key('ide_demo_root'),
                controller: _root,
                maxLength: 600,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr(
                    'Thư mục gốc (trống = gốc dự án)',
                    'Root folder (empty = project root)',
                  ),
                  errorText: rootBad
                      ? tr(
                          'Chỉ chữ, số, . _ - và / giữa các thư mục con',
                          'Letters, digits, . _ - and / between folders only',
                        )
                      : null,
                  counterText: '',
                ),
              ),
              if (widget.isGit) ...[
                const SizedBox(height: WebTuiSpacing.sm),
                TextField(
                  key: const Key('ide_demo_branch'),
                  controller: _branch,
                  maxLength: 100,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: tr(
                      'Nhánh (trống = mặc định)',
                      'Branch (empty = default)',
                    ),
                    errorText: branchBad
                        ? tr('Tên nhánh không hợp lệ', 'Invalid branch name')
                        : null,
                    counterText: '',
                  ),
                ),
              ],
              if (!s.my || s.allowPublic)
                SwitchListTile(
                  key: const Key('ide_demo_public'),
                  contentPadding: EdgeInsets.zero,
                  value: _public,
                  onChanged: (v) => setState(() => _public = v),
                  title: Text(tr('Công khai', 'Public')),
                  subtitle: Text(
                    tr(
                      'Ai có địa chỉ cũng xem được; cần xác nhận vân tay.',
                      'Anyone with the address can view; needs fingerprint confirmation.',
                    ),
                  ),
                ),
              const SizedBox(height: WebTuiSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('ide_demo_config_ok'),
                  style: ideToolsFilledBtn(),
                  onPressed: rootBad || branchBad ? null : _submit,
                  child: Text(
                    widget.editing ? tr('Lưu', 'Save') : tr('Bật', 'Turn on'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hộp tạm hiện mật khẩu DB. Mật khẩu chỉ nằm trong [IdeDbSecret] truyền vào
/// và trong widget này; đóng hộp là không còn gì giữ nó.
Future<void> showDbSecretDialog(BuildContext context, IdeDbSecret secret) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DbSecretDialog(secret: secret),
    );

class _DbSecretDialog extends StatefulWidget {
  const _DbSecretDialog({required this.secret});

  final IdeDbSecret secret;

  @override
  State<_DbSecretDialog> createState() => _DbSecretDialogState();
}

class _DbSecretDialogState extends State<_DbSecretDialog> {
  bool _show = false;

  // Mật khẩu đang trên màn: chặn chụp / quay màn hình và ảnh trong trình
  // chuyển ứng dụng (Android); đóng hộp thì trả lại như cũ.
  static const _privacy = BackgroundPrivacyController();

  @override
  void initState() {
    super.initState();
    _privacy.acquireSecureScreen();
  }

  @override
  void dispose() {
    _privacy.releaseSecureScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.secret.info;
    final pw = widget.secret.password;
    return AlertDialog(
      title: Text(tr('Mật khẩu database', 'Database password')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'Chỉ hiện một lần. Đóng hộp này là mất, muốn xem lại phải gọi lại.',
                'Shown once. It is gone when you close this box; ask again to see it.',
              ),
              style: IdeType.bodySmall.copyWith(color: IdeWb.warn),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            ToolInfoRow(tr('Máy chủ', 'Host'), info.host),
            ToolInfoRow(tr('Cổng', 'Port'), info.port),
            ToolInfoRow(tr('Database', 'Database'), info.database),
            ToolInfoRow(tr('Tài khoản', 'User'), info.username),
            const SizedBox(height: WebTuiSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _show ? pw : '••••••••••••',
                    key: const Key('ide_db_password'),
                    style: IdeType.bodyMedium.copyWith(
                      fontFamily: WebTuiTypography.monoFamily,
                      color: IdeWb.textStrong,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _show ? tr('Ẩn', 'Hide') : tr('Hiện', 'Show'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(
                    _show
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                  onPressed: () => setState(() => _show = !_show),
                ),
                IconButton(
                  key: const Key('ide_db_copy'),
                  tooltip: tr('Chép', 'Copy'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => ideToolsCopySecret(context, pw),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ide_db_close'),
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Đóng', 'Close')),
        ),
      ],
    );
  }
}

/// Nhật ký web demo (≤ 120 dòng cuối).
Future<void> showDemoLogSheet(BuildContext context, String text) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            child: SelectableText(
              text.isEmpty ? tr('Chưa có nhật ký.', 'No log yet.') : text,
              key: const Key('ide_demo_log_text'),
              style: IdeType.bodySmall.copyWith(
                fontFamily: WebTuiTypography.monoFamily,
                color: IdeWb.textStrong,
              ),
            ),
          ),
        ),
      ),
    );
