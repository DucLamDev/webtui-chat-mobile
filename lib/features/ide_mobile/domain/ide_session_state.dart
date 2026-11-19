/// Số nguyên từ JSON của IDE; `null` nếu không phải số hữu hạn (`1e999` giải mã
/// ra vô cực, `toInt()` sẽ ném).
int? ideJsonInt(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite) return value.toInt();
  return null;
}

/// Kết quả áp một khung `patch`.
enum IdePatchResult {
  applied,

  /// `base` lệch `revision` hiện có, hoặc patch trỏ tới mục không có: phải gửi
  /// `subscribe` lại để lấy cả state.
  needsResubscribe,
}

/// Bộ ráp state phiên AI, đúng như IDE web (`applyState` / `applyPatch`) và
/// phía máy `make_patch`: `set` / `del` khoá, `lists.messages|activity`
/// (`full` thay mục, `{id, textFrom, text}` nối chữ theo vị trí UTF-16),
/// `order`. Thuần Dart, không phụ thuộc Flutter.
final class IdeSessionState {
  IdeSessionState();

  Map<String, Object?> _state = <String, Object?>{};

  static const patchLists = ['messages', 'activity'];

  /// `null` khi chưa nhận state đầu tiên.
  int? get revision {
    final value = _state['revision'];
    return ideJsonInt(value);
  }

  bool get hasState => _state.isNotEmpty;

  Map<String, Object?> get raw => Map.unmodifiable(_state);

  IdeSessionView get view => IdeSessionView(_state);

  /// Khung `{"type":"state","state":{...}}`: thay toàn bộ.
  void applyState(Map<String, Object?> state) {
    _state = _deepCopy(state) as Map<String, Object?>;
  }

  /// Khung `{"type":"patch",...}`. Không đổi gì nếu trả về
  /// [IdePatchResult.needsResubscribe].
  IdePatchResult applyPatch(Map<String, Object?> patch) {
    final base = patch['base'];
    final rev = patch['revision'] ?? patch['rev'];
    if (revision == null || ideJsonInt(base) != revision) {
      return IdePatchResult.needsResubscribe;
    }
    // Làm trên bản sao: lỗi giữa chừng không để state nửa vời.
    final next = Map<String, Object?>.of(_state);
    final set = patch['set'];
    if (set is Map) {
      set.forEach((k, v) => next[k.toString()] = _deepCopy(v));
    }
    final del = patch['del'];
    if (del is List) {
      for (final k in del) {
        next.remove(k.toString());
      }
    }
    final lists = patch['lists'];
    if (lists is Map) {
      for (final entry in lists.entries) {
        final key = entry.key.toString();
        final record = entry.value;
        if (record is! Map) return IdePatchResult.needsResubscribe;
        final merged = _mergeList(next[key], record);
        if (merged == null) return IdePatchResult.needsResubscribe;
        next[key] = merged;
      }
    }
    final nextRev = ideJsonInt(rev);
    if (nextRev != null) next['revision'] = nextRev;
    _state = next;
    return IdePatchResult.applied;
  }

  static List<Map<String, Object?>>? _mergeList(Object? current, Map record) {
    final list = <Map<String, Object?>>[
      if (current is List)
        for (final item in current)
          if (item is Map) Map<String, Object?>.from(item),
    ];
    final index = <String, int>{};
    for (var i = 0; i < list.length; i++) {
      final id = '${list[i]['id']}';
      if (index.containsKey(id)) {
        // id trùng: không biết patch trúng mục nào.
        if (record['items'] is List && (record['items'] as List).isNotEmpty) {
          return null;
        }
      }
      index[id] = i;
    }
    final items = record['items'];
    if (items is List) {
      for (final raw in items) {
        if (raw is! Map) return null;
        final full = raw['full'];
        if (full is Map) {
          final item = _deepCopy(full) as Map<String, Object?>;
          final id = '${item['id']}';
          final at = index[id];
          if (at != null) {
            list[at] = item;
          } else {
            index[id] = list.length;
            list.add(item);
          }
          continue;
        }
        final id = '${raw['id']}';
        final from = raw['textFrom'];
        final text = raw['text'];
        final at = index[id];
        final cut = ideJsonInt(from);
        if (at == null || cut == null || text is! String) return null;
        final old = list[at]['text'];
        final oldText = old is String ? old : '';
        if (cut < 0 || cut > oldText.length) return null;
        // String của Dart là UTF-16, cùng đơn vị với JavaScript / `js_len`.
        list[at] = {...list[at], 'text': oldText.substring(0, cut) + text};
      }
    }
    final order = record['order'];
    if (order is List) {
      final byId = <String, Map<String, Object?>>{
        for (final item in list) '${item['id']}': item,
      };
      final ordered = <Map<String, Object?>>[];
      for (final id in order) {
        final item = byId['$id'];
        if (item == null) return null;
        ordered.add(item);
      }
      return ordered;
    }
    return list;
  }

  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final e in value.entries) e.key.toString(): _deepCopy(e.value),
      };
    }
    if (value is List) return [for (final e in value) _deepCopy(e)];
    return value;
  }
}

/// Quyền điều khiển của máy này trên phiên.
final class IdeRole {
  const IdeRole({
    this.control = false,
    this.free = false,
    this.controllerKind = '',
  });

  final bool control;
  final bool free;
  final String controllerKind;
}

/// Lớp xem có kiểu trên state phiên. Đọc mềm: thiếu khoá hoặc sai kiểu thì
/// trả giá trị rỗng, không ném lỗi.
final class IdeSessionView {
  const IdeSessionView(this._s);

  final Map<String, Object?> _s;

  List<Map<String, Object?>> _list(String key) {
    final v = _s[key];
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map) Map<String, Object?>.from(e),
    ];
  }

  Map<String, Object?> _map(String key) {
    final v = _s[key];
    return v is Map ? Map<String, Object?>.from(v) : const {};
  }

  bool _bool(String key) => _s[key] == true;

  String _str(String key) {
    final v = _s[key];
    return v is String ? v : '';
  }

  int _int(String key) {
    final v = _s[key];
    return ideJsonInt(v) ?? 0;
  }

  int get revision => _int('revision');
  List<Map<String, Object?>> get messages => _list('messages');
  List<Map<String, Object?>> get activity => _list('activity');
  List<Map<String, Object?>> get approvals => _list('approvals');
  Object? get plan => _s['plan'];
  List<Map<String, Object?>> get queue => _list('queue');
  bool get queuePaused => _bool('queuePaused');
  bool get busy => _bool('busy');
  bool get planPending => _bool('planPending');
  String get planPhase => _str('planPhase');
  String get teamPhase => _str('teamPhase');
  Object? get teamBoard => _s['teamBoard'];
  Map<String, Object?> get settings => _map('settings');
  List<Map<String, Object?>> get models => _list('models');
  List<Map<String, Object?>> get commands => _list('commands');
  List<Map<String, Object?>> get artifacts => _list('artifacts');
  List<Map<String, Object?>> get changes => _list('changes');
  List<Map<String, Object?>> get tasks => _list('tasks');
  List<Map<String, Object?>> get background => _list('background');
  List<Map<String, Object?>> get checkpoints => _list('checkpoints');
  Map<String, Object?> get usage => _map('usage');
  Map<String, Object?> get context => _map('context');
  bool get fastAllowed => _bool('fastAllowed');
  Object? get stall => _s['stall'];
  String get suggestion => _str('suggestion');
  Object? get modelSwitch => _s['modelSwitch'];
  Object? get accountActual => _s['accountActual'];

  /// Mọi khoá `quota*` (vd. `quota`, `quotaFive`, `quotaWeek`).
  Map<String, Object?> get quota => {
    for (final e in _s.entries)
      if (e.key.startsWith('quota')) e.key: e.value,
  };

  IdeRole get role {
    final r = _map('role');
    return IdeRole(
      control: r['control'] == true,
      free: r['free'] == true,
      controllerKind: r['controllerKind'] is String
          ? r['controllerKind']! as String
          : '',
    );
  }
}
