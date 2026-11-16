import '../../../../l10n/app_strings.dart';

/// Ai được gọi thoại / video cho tôi trong workspace (lõi 3.5).
enum WhoCanCallMe {
  everyone('everyone'),
  workspaceMembers('workspace_members'),
  contacts('contacts'),
  nobody('nobody');

  const WhoCanCallMe(this.apiValue);

  final String apiValue;

  String get label => switch (this) {
    everyone => tr('Mọi người', 'Everyone'),
    workspaceMembers => tr('Thành viên workspace', 'Workspace members'),
    contacts => tr('Bạn bè', 'Friends'),
    nobody => tr('Không ai', 'Nobody'),
  };

  String get description => switch (this) {
    everyone => tr(
      'Mọi người cùng workspace (trừ người đã chặn).',
      'Everyone in the workspace (except people you blocked).',
    ),
    workspaceMembers => tr(
      'Chỉ thành viên đang hoạt động của workspace.',
      'Only active members of the workspace.',
    ),
    contacts => tr(
      'Chỉ người đã kết bạn với bạn.',
      'Only people you are friends with.',
    ),
    nobody => tr('Không ai gọi được cho bạn.', 'Nobody can call you.'),
  };

  /// Giá trị lạ / thiếu thì coi như `everyone` (mặc định của máy chủ).
  static WhoCanCallMe fromApi(String value) {
    final normalized = value.trim().toLowerCase();
    for (final item in values) {
      if (item.apiValue == normalized) {
        return item;
      }
    }
    return everyone;
  }
}
