/// Ai được gọi thoại / video cho tôi trong workspace (lõi 3.5).
enum WhoCanCallMe {
  everyone(
    'everyone',
    'Mọi người',
    'Mọi người cùng workspace (trừ người đã chặn).',
  ),
  workspaceMembers(
    'workspace_members',
    'Thành viên workspace',
    'Chỉ thành viên đang hoạt động của workspace.',
  ),
  contacts('contacts', 'Bạn bè', 'Chỉ người đã kết bạn với bạn.'),
  nobody('nobody', 'Không ai', 'Không ai gọi được cho bạn.');

  const WhoCanCallMe(this.apiValue, this.label, this.description);

  final String apiValue;
  final String label;
  final String description;

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
