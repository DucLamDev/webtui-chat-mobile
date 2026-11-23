/// Dự án trong `projects.list` (giai đoạn 3: tab Dự án và Thêm dùng chung).
///
/// `name` là khoá gửi lại nguyên văn trong mọi `op` có tham số `project`
/// (dự án riêng có thể bắt đầu bằng `my:`); [title] để hiện.
enum IdeProjectKind {
  /// Có repo (GitHub / Gitea): PR, hàng chờ gộp, triển khai theo lần chạy.
  git,

  /// Dự án VPS: triển khai theo bản commit lịch sử, kéo về, khôi phục tệp.
  vps,

  /// Chỉ có mã trên Dev VPS, không triển khai.
  local,
}

final class IdeProjectTarget {
  const IdeProjectTarget({required this.name, this.label = ''});

  final String name;
  final String label;

  String get title => label.isNotEmpty ? label : name;
}

final class IdeProject {
  const IdeProject({
    required this.name,
    required this.root,
    this.label = '',
    this.kind = IdeProjectKind.local,
    this.my = false,
    this.branch = '',
    this.targets = const [],
    this.canMerge,
    this.canDeploy,
    this.canManage,
  });

  final String name;
  final String root;
  final String label;
  final IdeProjectKind kind;

  /// Dự án riêng (`vpsttt-my`): dùng `my.*` thay `deploy.*`.
  final bool my;
  final String branch;
  final List<IdeProjectTarget> targets;

  /// `null` = IDE không báo: cứ hiện nút, IDE trả `forbidden` nếu không được.
  final bool? canMerge;
  final bool? canDeploy;
  final bool? canManage;

  String get title {
    if (label.isNotEmpty) return label;
    return name.startsWith('my:') ? name.substring(3) : name;
  }

  bool get isGit => kind == IdeProjectKind.git;

  static IdeProject? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final root = raw['root'];
    if (name is! String || name.isEmpty || name.length > 200) return null;
    if (root is! String || root.isEmpty) return null;
    final kindRaw = raw['kind'] ?? raw['type'];
    final kind = switch (kindRaw) {
      'git' || 'github' || 'gitea' => IdeProjectKind.git,
      'vps' => IdeProjectKind.vps,
      'local' => IdeProjectKind.local,
      _ => raw['git'] == true ? IdeProjectKind.git : IdeProjectKind.local,
    };
    final can = raw['can'] is Map ? raw['can'] as Map : const {};
    bool? flag(String k) => can[k] is bool ? can[k] as bool : null;
    final targets = raw['targets'];
    return IdeProject(
      name: name,
      root: root,
      label: raw['label'] is String ? raw['label'] as String : '',
      kind: kind,
      my: raw['my'] == true || name.startsWith('my:'),
      branch: raw['branch'] is String ? raw['branch'] as String : '',
      targets: [
        if (targets is List)
          for (final t in targets)
            if (t is Map &&
                t['name'] is String &&
                (t['name'] as String).isNotEmpty)
              IdeProjectTarget(
                name: t['name'] as String,
                label: t['label'] is String ? t['label'] as String : '',
              ),
      ],
      canMerge: flag('merge'),
      canDeploy: flag('deploy'),
      canManage: flag('manage'),
    );
  }
}

List<IdeProject> parseIdeProjectList(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [for (final e in items) ?IdeProject.tryParse(e)];
}
