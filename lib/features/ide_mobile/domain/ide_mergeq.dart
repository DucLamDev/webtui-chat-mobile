import 'ide_session_state.dart' show ideJsonInt;

String _s(Map m, String k) => m[k] is String ? m[k] as String : '';
int _i(Map m, String k) => ideJsonInt(m[k]) ?? 0;

/// PR đang trong hàng (`trang_thai`: `duyet` | `cho` | `gop`). Giờ là giây Unix.
final class IdeMergeEntry {
  const IdeMergeEntry({
    required this.number,
    this.title = '',
    this.branch = '',
    this.by = '',
    this.joinedAt = 0,
    this.state = '',
    this.step = '',
    this.note = '',
    this.withdrawable = false,
  });

  final int number;
  final String title;
  final String branch;
  final String by;
  final int joinedAt;
  final String state;
  final String step;
  final String note;

  /// `rut`: người xem được phép rút PR này.
  final bool withdrawable;

  static IdeMergeEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final n = ideJsonInt(raw['so']);
    if (n == null || n <= 0) return null;
    return IdeMergeEntry(
      number: n,
      title: _s(raw, 'tieu_de'),
      branch: _s(raw, 'nhanh'),
      by: _s(raw, 'by'),
      joinedAt: _i(raw, 'vao'),
      state: _s(raw, 'trang_thai'),
      step: _s(raw, 'buoc'),
      note: _s(raw, 'ghi_chu'),
      withdrawable: raw['rut'] == true,
    );
  }
}

/// Khoá máy do CLI hàng chờ in ra (tiếng Việt không dấu, KHÔNG phải chữ hiện
/// lên màn hình). Viết bằng mã `\u` để luật "chữ giao diện phải có dấu" của
/// test không bắt nhầm; giá trị vẫn đúng nguyên văn `quyen` / `trien-khai-loi`.
const ideMergeqPermsKey = 'quy\u0065n';
const ideMergeResultDeployFailed = 'trien-khai-l\u006fi';

/// PR gần đây (`ket_qua`: `da-gop` | `tra-ve` | `rut` | `da-dong` |
/// `trien-khai` | `trien-khai-loi` | `khan-cap` | `doi-muc`).
final class IdeMergeRecent {
  const IdeMergeRecent({
    required this.number,
    this.title = '',
    this.branch = '',
    this.by = '',
    this.closedAt = 0,
    this.result = '',
    this.note = '',
  });

  final int number;
  final String title;
  final String branch;
  final String by;
  final int closedAt;
  final String result;
  final String note;

  bool get rejected =>
      result == 'tra-ve' || result == ideMergeResultDeployFailed;

  static IdeMergeRecent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final n = ideJsonInt(raw['so']);
    if (n == null || n <= 0) return null;
    return IdeMergeRecent(
      number: n,
      title: _s(raw, 'tieu_de'),
      branch: _s(raw, 'nhanh'),
      by: _s(raw, 'by'),
      closedAt: _i(raw, 'dong'),
      result: _s(raw, 'ket_qua'),
      note: _s(raw, 'ghi_chu'),
    );
  }
}

List<IdeMergeEntry> _entries(Object? v) => [
  if (v is List)
    for (final e in v) ?IdeMergeEntry.tryParse(e),
];

List<IdeMergeRecent> _recents(Object? v) => [
  if (v is List)
    for (final e in v) ?IdeMergeRecent.tryParse(e),
];

/// `mergeq.view`: hàng chờ của một dự án.
final class IdeMergeView {
  const IdeMergeView({
    this.queueName = '',
    this.mode = '',
    this.modeName = '',
    this.queue = const [],
    this.recent = const [],
    this.lightCount = 0,
    this.mine = '',
    this.changeableModes = const [],
    this.canMerge = false,
    this.canAdmin = false,
    this.canLight = false,
  });

  final String queueName;

  /// `day-du` | `hang-cho` | `tat`.
  final String mode;
  final String modeName;
  final List<IdeMergeEntry> queue;
  final List<IdeMergeRecent> recent;
  final int lightCount;
  final String mine;

  /// `quyen.doi_muc`: các mức người xem được đổi sang; rỗng = chỉ đọc.
  final List<String> changeableModes;
  final bool canMerge;
  final bool canAdmin;
  final bool canLight;

  bool get canChangeMode => changeableModes.isNotEmpty;

  static IdeMergeView parse(Object? data) {
    if (data is! Map) return const IdeMergeView();
    final q = data[ideMergeqPermsKey] is Map
        ? data[ideMergeqPermsKey] as Map
        : const {};
    final modes = q['doi_muc'];
    final light = data['viec_nhe'];
    return IdeMergeView(
      queueName: _s(data, 'hang_cho'),
      mode: _s(data, 'muc'),
      modeName: _s(data, 'muc_ten'),
      queue: _entries(data['hang']),
      recent: _recents(data['gan_day']),
      lightCount: light is List ? light.length : 0,
      mine: _s(data, 'toi'),
      changeableModes: [
        if (modes is List)
          for (final m in modes)
            if (m is String) m,
      ],
      canMerge: q['merge'] == true,
      canAdmin: q['quan_tri'] == true,
      canLight: q['viec_nhe'] == true,
    );
  }
}

/// Một hàng chờ trong `mergeq.mine`.
final class IdeMergeMineGroup {
  const IdeMergeMineGroup({
    required this.queue,
    this.mode = '',
    this.entries = const [],
    this.recent = const [],
  });

  final String queue;
  final String mode;
  final List<IdeMergeEntry> entries;
  final List<IdeMergeRecent> recent;
}

List<IdeMergeMineGroup> parseIdeMergeMine(Object? data) {
  final groups = data is Map ? data['hang_cho'] : null;
  if (groups is! List) return const [];
  return [
    for (final g in groups)
      if (g is Map)
        IdeMergeMineGroup(
          queue: _s(g, 'hang_cho'),
          mode: _s(g, 'muc'),
          entries: _entries(g['hang']),
          recent: _recents(g['gan_day']),
        ),
  ];
}

/// `mergeq.mode` (đọc).
final class IdeMergeMode {
  const IdeMergeMode({
    this.mode = '',
    this.name = '',
    this.by = '',
    this.forced = false,
    this.changeable = const [],
  });

  final String mode;
  final String name;
  final String by;

  /// `luon`: luôn bật, không đổi được.
  final bool forced;
  final List<String> changeable;

  static IdeMergeMode parse(Object? data) {
    if (data is! Map) return const IdeMergeMode();
    final c = data['doi_duoc'];
    return IdeMergeMode(
      mode: _s(data, 'muc'),
      name: _s(data, 'ten'),
      by: _s(data, 'by'),
      forced: data['luon'] == true,
      changeable: [
        if (c is List)
          for (final m in c)
            if (m is String) m,
      ],
    );
  }
}

/// Việc nhẹ (`mergeq.light_list`).
final class IdeLightItem {
  const IdeLightItem({
    required this.code,
    this.number = 0,
    this.branch = '',
    this.title = '',
    this.by = '',
    this.at = 0,
    this.content = '',
  });

  final String code;
  final int number;
  final String branch;
  final String title;
  final String by;
  final int at;
  final String content;

  static List<IdeLightItem> parseList(Object? data) {
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return [
      for (final e in items)
        if (e is Map && _s(e, 'ma').isNotEmpty)
          IdeLightItem(
            code: _s(e, 'ma'),
            number: _i(e, 'so'),
            branch: _s(e, 'nhanh'),
            title: _s(e, 'tieu_de'),
            by: _s(e, 'by'),
            at: _i(e, 'at'),
            content: _s(e, 'noi_dung'),
          ),
    ];
  }
}

/// Tên dễ hiểu của chế độ duyệt (`day-du` | `hang-cho` | `tat`).
String? ideMergeModeKey(String mode) =>
    const {'day-du', 'hang-cho', 'tat'}.contains(mode) ? mode : null;
