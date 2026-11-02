import 'dart:convert';
import 'dart:math' as math;

// Định dạng bảng trắng dùng chung app + web (schema 2). Toạ độ nằm trong khung
// 800×420, làm tròn 1 chữ số thập phân khi lưu. Khoá cấp trên, khoá trong phần
// tử và phần tử không hiểu được đều giữ nguyên khi ghi để bản app / web khác
// (cũ hoặc mới hơn) không làm mất dữ liệu của nhau.

const double whiteboardWidth = 800;
const double whiteboardHeight = 420;
const int whiteboardSchema = 2;
const String whiteboardDefaultColor = '#111827';
const double whiteboardDefaultStrokeWidth = 4;
const double whiteboardDefaultTextSize = 20;
const double whiteboardDefaultIconSize = 48;
const double whiteboardMinPointDistance = 1.5;
const int whiteboardMaxBytes = 500 * 1024;
const String whiteboardTooLargeMessage = 'Bảng trắng đã quá lớn, hãy xoá bớt';

final class WhiteboardPoint {
  const WhiteboardPoint(this.x, this.y);

  final double x;
  final double y;

  WhiteboardPoint translate(double dx, double dy) =>
      WhiteboardPoint(x + dx, y + dy);

  double distanceTo(WhiteboardPoint other) =>
      math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2));

  /// Kẹp điểm vào trong khung 800×420.
  WhiteboardPoint clamped() => WhiteboardPoint(
    x.clamp(0, whiteboardWidth).toDouble(),
    y.clamp(0, whiteboardHeight).toDouble(),
  );

  Map<String, Object?> toJson() => {'x': _round(x), 'y': _round(y)};

  @override
  bool operator ==(Object other) =>
      other is WhiteboardPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'WhiteboardPoint($x, $y)';
}

/// Hình chữ nhật bao (đơn vị khung).
final class WhiteboardBounds {
  const WhiteboardBounds(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  bool contains(WhiteboardPoint point, {double inflate = 0}) =>
      point.x >= left - inflate &&
      point.x <= right + inflate &&
      point.y >= top - inflate &&
      point.y <= bottom + inflate;
}

final class WhiteboardStroke {
  const WhiteboardStroke({
    required this.id,
    required this.color,
    required this.points,
    this.width = whiteboardDefaultStrokeWidth,
    this.extra = const {},
  });

  final String id;
  final String color;
  final double width;
  final List<WhiteboardPoint> points;

  /// Khoá lạ của nét (bản mới hơn thêm vào), giữ nguyên khi lưu.
  final Map<String, Object?> extra;

  WhiteboardStroke copyWith({String? id, List<WhiteboardPoint>? points}) {
    return WhiteboardStroke(
      id: id ?? this.id,
      color: color,
      width: width,
      points: points ?? this.points,
      extra: extra,
    );
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'color': color,
    'width': _round(width),
    'points': [
      for (final point in simplifyWhiteboardPoints(points)) point.toJson(),
    ],
  };
}

/// Phần tử vẽ được: hình chữ nhật, ellipse, mũi tên, chữ, biểu tượng.
sealed class WhiteboardElement {
  const WhiteboardElement({required this.id, this.extra = const {}});

  final String id;

  /// Khoá lạ của phần tử, giữ nguyên khi lưu.
  final Map<String, Object?> extra;

  String get type;

  WhiteboardBounds get bounds;

  WhiteboardElement withId(String id);

  WhiteboardElement moveBy(double dx, double dy);

  Map<String, Object?> toJson();

  /// Di chuyển nhưng giữ cả phần tử nằm trong khung (nếu nó vừa khung).
  WhiteboardElement moveWithin(double dx, double dy) {
    final box = bounds;
    return moveBy(
      _clampDelta(dx, box.left, box.right, whiteboardWidth),
      _clampDelta(dy, box.top, box.bottom, whiteboardHeight),
    );
  }
}

enum WhiteboardShapeKind {
  rect('rect'),
  ellipse('ellipse');

  const WhiteboardShapeKind(this.apiValue);

  final String apiValue;
}

final class WhiteboardShape extends WhiteboardElement {
  const WhiteboardShape({
    required super.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.color,
    this.width = whiteboardDefaultStrokeWidth,
    super.extra,
  });

  /// Hình từ hai góc bất kỳ (kéo ngược vẫn ra w, h ≥ 0).
  factory WhiteboardShape.fromCorners({
    required String id,
    required WhiteboardShapeKind kind,
    required WhiteboardPoint start,
    required WhiteboardPoint end,
    required String color,
    double width = whiteboardDefaultStrokeWidth,
  }) {
    return WhiteboardShape(
      id: id,
      kind: kind,
      x: math.min(start.x, end.x),
      y: math.min(start.y, end.y),
      w: (end.x - start.x).abs(),
      h: (end.y - start.y).abs(),
      color: color,
      width: width,
    );
  }

  final WhiteboardShapeKind kind;
  final double x;
  final double y;
  final double w;
  final double h;
  final String color;
  final double width;

  @override
  String get type => kind.apiValue;

  @override
  WhiteboardBounds get bounds => WhiteboardBounds(x, y, x + w, y + h);

  @override
  WhiteboardShape withId(String id) => WhiteboardShape(
    id: id,
    kind: kind,
    x: x,
    y: y,
    w: w,
    h: h,
    color: color,
    width: width,
    extra: extra,
  );

  @override
  WhiteboardShape moveBy(double dx, double dy) => WhiteboardShape(
    id: id,
    kind: kind,
    x: x + dx,
    y: y + dy,
    w: w,
    h: h,
    color: color,
    width: width,
    extra: extra,
  );

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'x': _round(x),
    'y': _round(y),
    'w': _round(w),
    'h': _round(h),
    'color': color,
    'width': _round(width),
  };
}

final class WhiteboardArrow extends WhiteboardElement {
  const WhiteboardArrow({
    required super.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.color,
    this.width = whiteboardDefaultStrokeWidth,
    super.extra,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String color;
  final double width;

  double get length => math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));

  @override
  String get type => 'arrow';

  @override
  WhiteboardBounds get bounds => WhiteboardBounds(
    math.min(x1, x2),
    math.min(y1, y2),
    math.max(x1, x2),
    math.max(y1, y2),
  );

  @override
  WhiteboardArrow withId(String id) => WhiteboardArrow(
    id: id,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    color: color,
    width: width,
    extra: extra,
  );

  @override
  WhiteboardArrow moveBy(double dx, double dy) => WhiteboardArrow(
    id: id,
    x1: x1 + dx,
    y1: y1 + dy,
    x2: x2 + dx,
    y2: y2 + dy,
    color: color,
    width: width,
    extra: extra,
  );

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'x1': _round(x1),
    'y1': _round(y1),
    'x2': _round(x2),
    'y2': _round(y2),
    'color': color,
    'width': _round(width),
  };
}

final class WhiteboardText extends WhiteboardElement {
  const WhiteboardText({
    required super.id,
    required this.x,
    required this.y,
    required this.text,
    required this.color,
    this.size = whiteboardDefaultTextSize,
    super.extra,
  });

  /// (x, y): góc trên trái hộp chữ.
  final double x;
  final double y;
  final String text;
  final String color;

  /// Cỡ chữ theo đơn vị khung.
  final double size;

  @override
  String get type => 'text';

  /// Hộp chữ ước lượng (không đo phông) — đủ cho chạm chọn / tẩy.
  @override
  WhiteboardBounds get bounds {
    final lines = text.split('\n');
    final longest = lines.fold<int>(
      0,
      (current, line) => math.max(current, line.runes.length),
    );
    return WhiteboardBounds(
      x,
      y,
      x + math.max(1, longest) * size * 0.6,
      y + lines.length * size * whiteboardTextLineHeight,
    );
  }

  @override
  WhiteboardText withId(String id) => WhiteboardText(
    id: id,
    x: x,
    y: y,
    text: text,
    color: color,
    size: size,
    extra: extra,
  );

  @override
  WhiteboardText moveBy(double dx, double dy) => WhiteboardText(
    id: id,
    x: x + dx,
    y: y + dy,
    text: text,
    color: color,
    size: size,
    extra: extra,
  );

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'x': _round(x),
    'y': _round(y),
    'text': text,
    'color': color,
    'size': _round(size),
  };
}

final class WhiteboardIcon extends WhiteboardElement {
  const WhiteboardIcon({
    required super.id,
    required this.x,
    required this.y,
    required this.icon,
    this.size = whiteboardDefaultIconSize,
    super.extra,
  });

  /// (x, y): tâm biểu tượng.
  final double x;
  final double y;
  final String icon;

  /// Cạnh ô vuông chứa biểu tượng.
  final double size;

  @override
  String get type => 'icon';

  @override
  WhiteboardBounds get bounds =>
      WhiteboardBounds(x - size / 2, y - size / 2, x + size / 2, y + size / 2);

  @override
  WhiteboardIcon withId(String id) =>
      WhiteboardIcon(id: id, x: x, y: y, icon: icon, size: size, extra: extra);

  @override
  WhiteboardIcon moveBy(double dx, double dy) => WhiteboardIcon(
    id: id,
    x: x + dx,
    y: y + dy,
    icon: icon,
    size: size,
    extra: extra,
  );

  @override
  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'type': type,
    'x': _round(x),
    'y': _round(y),
    'size': _round(size),
    'icon': icon,
  };
}

/// Chiều cao một dòng chữ so với cỡ chữ (web và app dùng cùng hệ số).
const double whiteboardTextLineHeight = 1.25;

/// Độ dài đầu mũi tên theo độ dày nét (đơn vị khung), web và app vẽ giống nhau.
double whiteboardArrowHeadLength(double width) => math.max(12, width * 4);

final class WhiteboardDocument {
  const WhiteboardDocument({
    this.base = const {},
    this.strokes = const [],
    this.elements = const [],
    this.unknownStrokes = const [],
    this.unknownElements = const [],
  });

  factory WhiteboardDocument.parse(Map<String, Object?> content) {
    final base = <String, Object?>{
      for (final entry in content.entries)
        if (!_documentKeys.contains(entry.key)) entry.key: entry.value,
    };
    final strokes = <WhiteboardStroke>[];
    final strokeIndexes = <int>[];
    final unknownStrokes = <Object?>[];
    final rawStrokes = content['strokes'];
    if (rawStrokes is List) {
      for (var index = 0; index < rawStrokes.length; index++) {
        final stroke = _parseStroke(rawStrokes[index]);
        if (stroke == null) {
          unknownStrokes.add(rawStrokes[index]);
        } else {
          strokes.add(stroke);
          strokeIndexes.add(index);
        }
      }
    }
    // Bản app cũ lưu toạ độ chuẩn hoá 0–1, không có `schema`.
    final legacy = !content.containsKey('schema') && _isNormalized(strokes);
    final elements = <WhiteboardElement>[];
    final elementIndexes = <int>[];
    final unknownElements = <Object?>[];
    final rawElements = content['elements'];
    if (rawElements is List) {
      for (var index = 0; index < rawElements.length; index++) {
        final element = _parseElement(rawElements[index]);
        if (element == null) {
          unknownElements.add(rawElements[index]);
        } else {
          elements.add(element);
          elementIndexes.add(index);
        }
      }
    }
    // Id thiếu / trùng sinh theo vị trí: đọc lại cùng dữ liệu ra cùng id.
    final usedIds = <String>{};
    return WhiteboardDocument(
      base: base,
      strokes: [
        for (var index = 0; index < strokes.length; index++)
          WhiteboardStroke(
            id: _uniqueId(
              strokes[index].id,
              's-n${strokeIndexes[index]}',
              usedIds,
            ),
            color: strokes[index].color,
            width: strokes[index].width,
            points: legacy
                ? [
                    for (final point in strokes[index].points)
                      WhiteboardPoint(
                        point.x * whiteboardWidth,
                        point.y * whiteboardHeight,
                      ),
                  ]
                : strokes[index].points,
            extra: strokes[index].extra,
          ),
      ],
      elements: [
        for (var index = 0; index < elements.length; index++)
          elements[index].withId(
            _uniqueId(
              elements[index].id,
              'e-n${elementIndexes[index]}',
              usedIds,
            ),
          ),
      ],
      unknownStrokes: unknownStrokes,
      unknownElements: unknownElements,
    );
  }

  /// Khoá cấp trên khác `schema`, `strokes`, `elements`.
  final Map<String, Object?> base;
  final List<WhiteboardStroke> strokes;
  final List<WhiteboardElement> elements;

  /// Nét / phần tử sai trường hoặc `type` lạ: không vẽ, ghi lại y nguyên.
  final List<Object?> unknownStrokes;
  final List<Object?> unknownElements;

  bool get isEmpty =>
      strokes.isEmpty &&
      elements.isEmpty &&
      unknownStrokes.isEmpty &&
      unknownElements.isEmpty;

  Map<String, Object?> toJson() => {
    ...base,
    'schema': whiteboardSchema,
    'strokes': [
      for (final stroke in strokes) stroke.toJson(),
      ...unknownStrokes,
    ],
    'elements': [
      for (final element in elements) element.toJson(),
      ...unknownElements,
    ],
  };

  /// Số byte UTF-8 của nội dung khi gửi lên máy chủ.
  int get encodedBytes => whiteboardContentBytes(toJson());

  bool get isTooLarge => encodedBytes > whiteboardMaxBytes;

  WhiteboardStroke? strokeById(String id) {
    for (final stroke in strokes) {
      if (stroke.id == id) return stroke;
    }
    return null;
  }

  WhiteboardElement? elementById(String id) {
    for (final element in elements) {
      if (element.id == id) return element;
    }
    return null;
  }

  bool containsId(String id) =>
      strokeById(id) != null || elementById(id) != null;

  /// Thêm nét / phần tử; trùng id thì thay chỗ cũ (áp lại nhiều lần vẫn đúng).
  WhiteboardDocument add({
    List<WhiteboardStroke> strokes = const [],
    List<WhiteboardElement> elements = const [],
    List<Object?> unknownStrokes = const [],
    List<Object?> unknownElements = const [],
  }) {
    var next = this;
    for (final stroke in strokes) {
      final index = next.strokes.indexWhere((item) => item.id == stroke.id);
      next = next._copy(
        strokes: index < 0
            ? [...next.strokes, stroke]
            : ([...next.strokes]..[index] = stroke),
      );
    }
    for (final element in elements) {
      final index = next.elements.indexWhere((item) => item.id == element.id);
      next = next._copy(
        elements: index < 0
            ? [...next.elements, element]
            : ([...next.elements]..[index] = element),
      );
    }
    if (unknownStrokes.isEmpty && unknownElements.isEmpty) return next;
    return next._copy(
      unknownStrokes: [...next.unknownStrokes, ...unknownStrokes],
      unknownElements: [...next.unknownElements, ...unknownElements],
    );
  }

  /// Xoá nét / phần tử theo id; `clearUnknown` bỏ luôn phần tử không hiểu được.
  WhiteboardDocument remove(Set<String> ids, {bool clearUnknown = false}) {
    return _copy(
      strokes: [
        for (final stroke in strokes)
          if (!ids.contains(stroke.id)) stroke,
      ],
      elements: [
        for (final element in elements)
          if (!ids.contains(element.id)) element,
      ],
      unknownStrokes: clearUnknown ? const [] : unknownStrokes,
      unknownElements: clearUnknown ? const [] : unknownElements,
    );
  }

  /// Thay phần tử cùng id (vd. sau khi di chuyển); không còn thì bỏ qua.
  WhiteboardDocument replaceElement(WhiteboardElement element) {
    final index = elements.indexWhere((item) => item.id == element.id);
    if (index < 0) return this;
    return _copy(elements: [...elements]..[index] = element);
  }

  WhiteboardDocument moveElement(String id, double dx, double dy) {
    final element = elementById(id);
    if (element == null) return this;
    return replaceElement(element.moveWithin(dx, dy));
  }

  /// Xoá mọi nét, phần tử (cả phần tử lạ); giữ khoá cấp trên khác.
  WhiteboardDocument clear() => _copy(
    strokes: const [],
    elements: const [],
    unknownStrokes: const [],
    unknownElements: const [],
  );

  /// Id của nét / phần tử trên cùng ở điểm chạm, hoặc `null`.
  ///
  /// `tolerance` theo đơn vị khung. `includeStrokes: false` chỉ tìm phần tử
  /// (công cụ Chọn). `shapeInteriors: true` coi cả lòng hình chữ nhật / ellipse
  /// là chạm trúng; mặc định chỉ tính đường viền để tẩy không xoá nhầm hình
  /// bao quanh nét bên trong.
  String? hitTest(
    WhiteboardPoint point, {
    double tolerance = 8,
    bool includeStrokes = true,
    bool shapeInteriors = false,
  }) {
    for (final element in elements.reversed) {
      if (_elementHit(element, point, tolerance, shapeInteriors)) {
        return element.id;
      }
    }
    if (!includeStrokes) return null;
    for (final stroke in strokes.reversed) {
      if (_strokeHit(stroke, point, tolerance)) return stroke.id;
    }
    return null;
  }

  WhiteboardDocument _copy({
    List<WhiteboardStroke>? strokes,
    List<WhiteboardElement>? elements,
    List<Object?>? unknownStrokes,
    List<Object?>? unknownElements,
  }) {
    return WhiteboardDocument(
      base: base,
      strokes: strokes ?? this.strokes,
      elements: elements ?? this.elements,
      unknownStrokes: unknownStrokes ?? this.unknownStrokes,
      unknownElements: unknownElements ?? this.unknownElements,
    );
  }
}

/// Thao tác cục bộ trên bảng trắng. Ghi lại để áp lại lên bản mới nhất khi
/// lưu bị xung đột version, và để hoàn tác / làm lại.
sealed class WhiteboardOp {
  const WhiteboardOp();

  WhiteboardDocument applyTo(WhiteboardDocument document);
}

final class WhiteboardAddOp extends WhiteboardOp {
  const WhiteboardAddOp({
    this.strokes = const [],
    this.elements = const [],
    this.unknownStrokes = const [],
    this.unknownElements = const [],
  });

  final List<WhiteboardStroke> strokes;
  final List<WhiteboardElement> elements;
  final List<Object?> unknownStrokes;
  final List<Object?> unknownElements;

  @override
  WhiteboardDocument applyTo(WhiteboardDocument document) => document.add(
    strokes: strokes,
    elements: elements,
    unknownStrokes: unknownStrokes,
    unknownElements: unknownElements,
  );
}

final class WhiteboardRemoveOp extends WhiteboardOp {
  const WhiteboardRemoveOp(this.ids, {this.clearUnknown = false});

  final Set<String> ids;
  final bool clearUnknown;

  @override
  WhiteboardDocument applyTo(WhiteboardDocument document) =>
      document.remove(ids, clearUnknown: clearUnknown);
}

final class WhiteboardReplaceOp extends WhiteboardOp {
  const WhiteboardReplaceOp(this.element);

  final WhiteboardElement element;

  @override
  WhiteboardDocument applyTo(WhiteboardDocument document) =>
      document.replaceElement(element);
}

/// Bỏ điểm cách điểm giữ lại trước đó dưới `minDistance`; luôn giữ điểm đầu,
/// điểm cuối.
List<WhiteboardPoint> simplifyWhiteboardPoints(
  List<WhiteboardPoint> points, {
  double minDistance = whiteboardMinPointDistance,
}) {
  if (points.length <= 2) return List.of(points);
  final kept = [points.first];
  for (var index = 1; index < points.length - 1; index++) {
    if (points[index].distanceTo(kept.last) >= minDistance) {
      kept.add(points[index]);
    }
  }
  final last = points.last;
  if (kept.length > 1 && last.distanceTo(kept.last) < minDistance) {
    kept[kept.length - 1] = last;
  } else {
    kept.add(last);
  }
  return kept;
}

/// Số byte UTF-8 của nội dung JSON.
int whiteboardContentBytes(Map<String, Object?> content) =>
    utf8.encode(jsonEncode(content)).length;

final _idRandom = math.Random();

/// Id mới dạng `s-...` (nét) / `e-...` (phần tử).
String createWhiteboardId(String prefix) {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = _idRandom
      .nextInt(0x7fffffff)
      .toRadixString(36)
      .padLeft(6, '0');
  return '$prefix-${time.substring(time.length - 4)}'
      '${random.substring(random.length - 6)}';
}

const _documentKeys = {'schema', 'strokes', 'elements'};
const _strokeKeys = {'id', 'color', 'width', 'points'};
const _shapeKeys = {'id', 'type', 'x', 'y', 'w', 'h', 'color', 'width'};
const _arrowKeys = {'id', 'type', 'x1', 'y1', 'x2', 'y2', 'color', 'width'};
const _textKeys = {'id', 'type', 'x', 'y', 'text', 'color', 'size'};
const _iconKeys = {'id', 'type', 'x', 'y', 'size', 'icon'};

WhiteboardStroke? _parseStroke(Object? value) {
  if (value is! Map) return null;
  final rawPoints = value['points'];
  if (rawPoints is! List) return null;
  final points = <WhiteboardPoint>[
    for (final point in rawPoints)
      if (point is Map && _isFinite(point['x']) && _isFinite(point['y']))
        WhiteboardPoint(
          (point['x']! as num).toDouble(),
          (point['y']! as num).toDouble(),
        ),
  ];
  if (points.isEmpty) return null;
  return WhiteboardStroke(
    id: _string(value['id']),
    color: _color(value['color']),
    width: _positive(value['width'], whiteboardDefaultStrokeWidth),
    points: points,
    extra: _extra(value, _strokeKeys),
  );
}

WhiteboardElement? _parseElement(Object? value) {
  if (value is! Map) return null;
  final type = value['type'];
  final id = _string(value['id']);
  switch (type) {
    case 'rect' || 'ellipse':
      final x = _number(value['x']);
      final y = _number(value['y']);
      final w = _number(value['w']);
      final h = _number(value['h']);
      if (x == null || y == null || w == null || h == null) return null;
      return WhiteboardShape(
        id: id,
        kind: type == 'rect'
            ? WhiteboardShapeKind.rect
            : WhiteboardShapeKind.ellipse,
        x: math.min(x, x + w),
        y: math.min(y, y + h),
        w: w.abs(),
        h: h.abs(),
        color: _color(value['color']),
        width: _positive(value['width'], whiteboardDefaultStrokeWidth),
        extra: _extra(value, _shapeKeys),
      );
    case 'arrow':
      final x1 = _number(value['x1']);
      final y1 = _number(value['y1']);
      final x2 = _number(value['x2']);
      final y2 = _number(value['y2']);
      if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
      return WhiteboardArrow(
        id: id,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: _color(value['color']),
        width: _positive(value['width'], whiteboardDefaultStrokeWidth),
        extra: _extra(value, _arrowKeys),
      );
    case 'text':
      final x = _number(value['x']);
      final y = _number(value['y']);
      final text = value['text'];
      if (x == null || y == null || text is! String || text.trim().isEmpty) {
        return null;
      }
      return WhiteboardText(
        id: id,
        x: x,
        y: y,
        text: text,
        color: _color(value['color']),
        size: _positive(value['size'], whiteboardDefaultTextSize),
        extra: _extra(value, _textKeys),
      );
    case 'icon':
      final x = _number(value['x']);
      final y = _number(value['y']);
      final icon = value['icon'];
      if (x == null || y == null || icon is! String || icon.trim().isEmpty) {
        return null;
      }
      return WhiteboardIcon(
        id: id,
        x: x,
        y: y,
        icon: icon,
        size: _positive(value['size'], whiteboardDefaultIconSize),
        extra: _extra(value, _iconKeys),
      );
  }
  return null;
}

bool _isNormalized(List<WhiteboardStroke> strokes) {
  return strokes.isNotEmpty &&
      strokes.every(
        (stroke) => stroke.points.every(
          (point) =>
              point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1,
        ),
      );
}

String _uniqueId(String candidate, String fallback, Set<String> usedIds) {
  var id = candidate.trim().isNotEmpty && !usedIds.contains(candidate)
      ? candidate
      : fallback;
  var suffix = 1;
  while (usedIds.contains(id)) {
    id = '$fallback-$suffix';
    suffix++;
  }
  usedIds.add(id);
  return id;
}

Map<String, Object?> _extra(Map<dynamic, dynamic> value, Set<String> known) {
  return {
    for (final entry in value.entries)
      if (!known.contains(entry.key)) entry.key.toString(): entry.value,
  };
}

bool _isFinite(Object? value) => value is num && value.isFinite;

double? _number(Object? value) =>
    _isFinite(value) ? (value! as num).toDouble() : null;

double _positive(Object? value, double fallback) {
  final number = _number(value);
  return number != null && number > 0 ? number : fallback;
}

String _string(Object? value) => value is String ? value : '';

String _color(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : whiteboardDefaultColor;

/// Làm tròn 1 chữ số thập phân; số nguyên ghi không có `.0` (giống web).
num _round(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.truncateToDouble() ? rounded.toInt() : rounded;
}

double _clampDelta(double delta, double start, double end, double limit) {
  if (end - start > limit) return delta;
  return delta.clamp(-start, limit - end).toDouble();
}

bool _elementHit(
  WhiteboardElement element,
  WhiteboardPoint point,
  double tolerance,
  bool shapeInteriors,
) {
  switch (element) {
    case WhiteboardShape():
      final reach = tolerance + element.width / 2;
      if (element.kind == WhiteboardShapeKind.rect) {
        final box = element.bounds;
        if (!box.contains(point, inflate: reach)) return false;
        if (shapeInteriors) return true;
        final inside =
            point.x > box.left + reach &&
            point.x < box.right - reach &&
            point.y > box.top + reach &&
            point.y < box.bottom - reach;
        return !inside;
      }
      final rx = math.max(element.w / 2, 0.5);
      final ry = math.max(element.h / 2, 0.5);
      final dx = point.x - (element.x + rx);
      final dy = point.y - (element.y + ry);
      final radial = math.sqrt(math.pow(dx / rx, 2) + math.pow(dy / ry, 2));
      if (shapeInteriors && radial <= 1) return true;
      // Khoảng cách tới viền đo dọc tia từ tâm (ước lượng đủ cho chạm).
      final distance = radial == 0
          ? math.min(rx, ry)
          : math.sqrt(dx * dx + dy * dy) * (1 - 1 / radial).abs();
      return distance <= reach;
    case WhiteboardArrow():
      return _distanceToSegment(
            point,
            WhiteboardPoint(element.x1, element.y1),
            WhiteboardPoint(element.x2, element.y2),
          ) <=
          tolerance + element.width / 2;
    case WhiteboardText() || WhiteboardIcon():
      return element.bounds.contains(point, inflate: tolerance);
  }
}

bool _strokeHit(
  WhiteboardStroke stroke,
  WhiteboardPoint point,
  double tolerance,
) {
  final reach = tolerance + stroke.width / 2;
  if (stroke.points.length == 1) {
    return stroke.points.first.distanceTo(point) <= reach;
  }
  for (var index = 1; index < stroke.points.length; index++) {
    if (_distanceToSegment(
          point,
          stroke.points[index - 1],
          stroke.points[index],
        ) <=
        reach) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(
  WhiteboardPoint point,
  WhiteboardPoint start,
  WhiteboardPoint end,
) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return point.distanceTo(start);
  final t =
      (((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
          .clamp(0, 1)
          .toDouble();
  return point.distanceTo(WhiteboardPoint(start.x + t * dx, start.y + t * dy));
}
