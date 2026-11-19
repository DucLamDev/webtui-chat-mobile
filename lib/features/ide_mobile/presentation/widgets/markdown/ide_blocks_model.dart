import 'dart:convert';

import '../../../../../l10n/app_strings.dart';

/// Giới hạn khớp IDE web (`chatblocks.js`): JSON quá lớn / quá nhiều phần tử thì
/// hiện khối mã thường.
const ideBlockJsonLimit = 256 * 1024;
const _maxLabels = 200;
const _maxSeries = 6;
const _maxPoints = 2000;
const _maxPie = 40;
const _maxSlices = 8;
const _maxFields = 30;
const _maxOptions = 30;
const _maxNodes = 200;

Map<String, Object?>? _parseObject(String code) {
  if (code.length > ideBlockJsonLimit) return null;
  try {
    final v = jsonDecode(code);
    if (v is Map) return Map<String, Object?>.from(v);
  } on FormatException {
    // JSON sai: người gọi hiện khối mã thường.
  }
  return null;
}

String _str(Object? v, [int max = 200]) {
  final s = v is String ? v : (v == null ? '' : '$v');
  return s.length > max ? s.substring(0, max) : s;
}

// ---------------------------------------------------------------- biểu đồ

enum IdeChartType { bar, line, pie }

final class IdeChartSeries {
  const IdeChartSeries(this.name, this.values);
  final String name;

  /// Cùng độ dài `labels`; `null` = thiếu số.
  final List<double?> values;
}

final class IdeChartSpec {
  const IdeChartSpec({
    required this.type,
    required this.labels,
    required this.series,
    required this.title,
    required this.unit,
  });

  final IdeChartType type;
  final List<String> labels;
  final List<IdeChartSeries> series;
  final String title;
  final String unit;

  /// Biểu đồ tròn quá [_maxSlices] phần: giữ phần lớn nhất, gom phần còn lại
  /// vào "Khác" (như IDE web).
  IdeChartSpec get collapsedPie {
    if (type != IdeChartType.pie || labels.length <= _maxSlices) return this;
    final vals = series.first.values;
    final order = List<int>.generate(vals.length, (i) => i)
      ..sort((a, b) => (vals[b] ?? 0).compareTo(vals[a] ?? 0));
    final keep = order.take(_maxSlices - 1).toSet();
    final newLabels = <String>[];
    final newVals = <double?>[];
    var other = 0.0;
    for (var i = 0; i < vals.length; i++) {
      if (keep.contains(i)) {
        newLabels.add(labels[i]);
        newVals.add(vals[i]);
      } else {
        other += vals[i] ?? 0;
      }
    }
    newLabels.add(tr('Khác', 'Other'));
    newVals.add(other);
    return IdeChartSpec(
      type: type,
      labels: newLabels,
      series: [IdeChartSeries(series.first.name, newVals)],
      title: title,
      unit: unit,
    );
  }
}

IdeChartType? _chartType(String v) => switch (v.toLowerCase()) {
  'bar' || 'cot' => IdeChartType.bar,
  'line' || 'duong' => IdeChartType.line,
  'pie' || 'tron' => IdeChartType.pie,
  _ => null,
};

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

/// Đọc khối ` ```bieudo `; `null` khi JSON sai / thiếu dữ liệu.
IdeChartSpec? parseIdeChart(String code) {
  final raw = _parseObject(code);
  if (raw == null) return null;
  final type = _chartType(_str(raw['type'], 10));
  final rawLabels = raw['labels'];
  final labels = rawLabels is List
      ? [for (final x in rawLabels.take(_maxLabels)) _str(x, 60)]
      : <String>[];
  final rawSeries = raw['series'];
  final series = <IdeChartSeries>[];
  if (rawSeries is List) {
    for (final x in rawSeries.take(_maxSeries)) {
      if (x is! Map) continue;
      final vs = x['values'];
      series.add(
        IdeChartSeries(_str(x['name'], 60), [
          for (var i = 0; i < labels.length; i++)
            _num(vs is List && i < vs.length ? vs[i] : null),
        ]),
      );
    }
  }
  if (type == null || labels.isEmpty || series.isEmpty) return null;
  if (labels.length * series.length > _maxPoints) return null;
  if (series.every((s) => s.values.every((v) => v == null))) return null;
  if (type == IdeChartType.pie &&
      (series.length != 1 ||
          labels.length > _maxPie ||
          series.first.values.any((v) => v != null && v < 0))) {
    return null;
  }
  return IdeChartSpec(
    type: type,
    labels: labels,
    series: series,
    title: _str(raw['title'], 120),
    unit: _str(raw['unit'], 20),
  );
}

// ---------------------------------------------------------------- biểu mẫu

enum IdeFieldType { text, number, select, date, textarea, checkbox }

final class IdeFormField {
  const IdeFormField({
    required this.id,
    required this.label,
    required this.type,
    required this.options,
    required this.required,
    required this.placeholder,
  });

  final String id;
  final String label;
  final IdeFieldType type;
  final List<String> options;
  final bool required;
  final String placeholder;
}

final class IdeFormSpec {
  const IdeFormSpec({
    required this.title,
    required this.submit,
    required this.fields,
  });

  final String title;
  final String submit;
  final List<IdeFormField> fields;
}

IdeFieldType _fieldType(Object? v) {
  for (final t in IdeFieldType.values) {
    if (t.name == v) return t;
  }
  return IdeFieldType.text;
}

/// Đọc khối ` ```form `; `null` khi sai.
IdeFormSpec? parseIdeForm(String code) {
  final raw = _parseObject(code);
  if (raw == null) return null;
  final rawFields = raw['fields'];
  if (rawFields is! List) return null;
  final fields = <IdeFormField>[];
  for (final f in rawFields.take(_maxFields)) {
    if (f is! Map) continue;
    final index = fields.length;
    final idRaw = _str(f['id'], 40);
    final label = _str(f['label'] ?? f['id'] ?? '', 120);
    final opts = f['options'];
    fields.add(
      IdeFormField(
        id: idRaw.isEmpty ? 'f$index' : idRaw,
        label: label,
        type: _fieldType(f['type']),
        options: opts is List
            ? [
                for (final o in opts.take(_maxOptions))
                  if (_str(o, 80).isNotEmpty) _str(o, 80),
              ]
            : const [],
        required: f['required'] == true,
        placeholder: _str(f['placeholder'], 120),
      ),
    );
  }
  if (fields.isEmpty ||
      fields.any((f) => f.label.isEmpty) ||
      fields.any((f) => f.type == IdeFieldType.select && f.options.isEmpty)) {
    return null;
  }
  return IdeFormSpec(
    title: _str(raw['title'], 120),
    submit: _str(raw['submit'], 40),
    fields: fields,
  );
}

/// Gộp về một dòng: ký tự điều khiển / xuống dòng / định dạng Unicode thành
/// dấu cách, cắt còn [max] ký tự.
String ideOneLine(String raw, int max) {
  final s = raw
      .replaceAll(
        RegExp(
          r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]|\p{Cf}',
          unicode: true,
        ),
        ' ',
      )
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
  final runes = s.runes.toList();
  return runes.length <= max ? s : String.fromCharCodes(runes.take(max));
}

/// Chuỗi trả lời khi gửi biểu mẫu: GIỐNG HỆT IDE web (`chatblocks.js`):
/// mở đầu "Trả lời biểu mẫu[: tiêu đề]" (không bao giờ bắt đầu bằng "/"), mỗi
/// ô có giá trị một dòng `- nhãn: giá trị`, ô tích là Có / Không, ô trống bỏ.
/// Trả `null` khi không có ô nào được điền (không gửi).
String? ideFormAnswer(
  IdeFormSpec spec,
  Map<String, Object?> values, {
  bool english = false,
}) {
  final lines = <String>[];
  for (final f in spec.fields) {
    final v = values[f.id];
    final String text;
    if (f.type == IdeFieldType.checkbox) {
      text = v == true ? (english ? 'Yes' : 'Có') : (english ? 'No' : 'Không');
    } else {
      text = v is String ? v.trim() : '';
    }
    // Nhãn do AI viết: một dòng, không ký tự điều khiển, ≤ 60 ký tự.
    if (text.isNotEmpty) lines.add('- ${ideOneLine(f.label, 60)}: $text');
  }
  if (lines.isEmpty) return null;
  final head = english ? 'Form answer' : 'Trả lời biểu mẫu';
  final title = ideOneLine(spec.title, 120);
  return '$head${title.isEmpty ? '' : ': $title'}\n'
      '${lines.join('\n')}';
}

// ---------------------------------------------------------------- sơ đồ

final class IdeDiagramZone {
  const IdeDiagramZone(this.id, this.name, this.trust);
  final String id;
  final String name;
  final String trust;
}

final class IdeDiagramNode {
  const IdeDiagramNode(this.id, this.name, this.type, this.zone);
  final String id;
  final String name;
  final String type;
  final String zone;
}

final class IdeDiagramEdge {
  const IdeDiagramEdge(this.from, this.to, this.proto, this.data);
  final String from;
  final String to;
  final String proto;
  final String data;
}

final class IdeDiagramSpec {
  const IdeDiagramSpec({
    required this.zones,
    required this.nodes,
    required this.edges,
  });
  final List<IdeDiagramZone> zones;
  final List<IdeDiagramNode> nodes;
  final List<IdeDiagramEdge> edges;
}

const _trusts = ['internet', 'ben-ngoai', 'bien', 'noi-bo', 'rieng'];

/// Thứ tự lớp: vùng ít tin cậy (internet) ở trên, vùng riêng ở dưới.
int ideTrustRank(String trust) {
  final i = _trusts.indexOf(trust);
  return i < 0 ? _trusts.indexOf('noi-bo') : i;
}

/// Đọc khối ` ```sodo `; `null` khi sai / không có nút nào.
IdeDiagramSpec? parseIdeDiagram(String code) {
  final raw = _parseObject(code);
  if (raw == null) return null;
  final rawNodes = raw['nodes'];
  if (rawNodes is! List || rawNodes.isEmpty || rawNodes.length > _maxNodes) {
    return null;
  }
  final zones = <IdeDiagramZone>[];
  final rawZones = raw['zones'];
  if (rawZones is List) {
    for (final z in rawZones) {
      if (z is! Map) continue;
      final id = _str(z['id'], 60);
      if (id.isEmpty) continue;
      final trust = _str(z['trust'], 20);
      zones.add(
        IdeDiagramZone(
          id,
          _str(z['name'], 60).isEmpty ? id : _str(z['name'], 60),
          _trusts.contains(trust) ? trust : 'noi-bo',
        ),
      );
    }
  }
  final nodes = <IdeDiagramNode>[];
  final seen = <String>{};
  for (final n in rawNodes) {
    if (n is! Map) continue;
    final id = _str(n['id'], 60);
    if (id.isEmpty || !seen.add(id)) continue;
    final name = _str(n['name'], 60);
    nodes.add(
      IdeDiagramNode(
        id,
        name.isEmpty ? id : name,
        _str(n['type'], 30),
        _str(n['zone'], 60),
      ),
    );
  }
  if (nodes.isEmpty) return null;
  final edges = <IdeDiagramEdge>[];
  final rawEdges = raw['edges'];
  if (rawEdges is List) {
    for (final e in rawEdges.take(400)) {
      if (e is! Map) continue;
      final from = _str(e['from'], 60);
      final to = _str(e['to'], 60);
      if (!seen.contains(from) || !seen.contains(to)) continue;
      edges.add(
        IdeDiagramEdge(from, to, _str(e['proto'], 30), _str(e['data'], 60)),
      );
    }
  }
  return IdeDiagramSpec(zones: zones, nodes: nodes, edges: edges);
}

// ---------------------------------------------------------------- bố cục sơ đồ

const ideDiagramNodeW = 124.0;
const ideDiagramNodeH = 48.0;
const _gapX = 18.0;
const _gapY = 46.0;
const _bandPad = 14.0;
const _bandHead = 22.0;
const _perRow = 3;

final class IdeDiagramBand {
  const IdeDiagramBand(this.zone, this.rect);
  final IdeDiagramZone zone;
  final ({double x, double y, double w, double h}) rect;
}

final class IdeDiagramLayout {
  const IdeDiagramLayout({
    required this.width,
    required this.height,
    required this.bands,
    required this.nodeRects,
  });
  final double width;
  final double height;
  final List<IdeDiagramBand> bands;

  /// id nút → (x, y) góc trên trái; kích thước [ideDiagramNodeW] × [ideDiagramNodeH].
  final Map<String, ({double x, double y})> nodeRects;
}

/// Xếp theo lớp: mỗi vùng là một dải ngang (vùng ít tin cậy ở trên), nút trong
/// vùng xếp tối đa 3 cột rồi xuống hàng. Nút không thuộc vùng nào vào dải "Khác".
IdeDiagramLayout layoutIdeDiagram(IdeDiagramSpec spec) {
  final zoneIds = {for (final z in spec.zones) z.id};
  final zones = [...spec.zones];
  final loose = spec.nodes.where((n) => !zoneIds.contains(n.zone)).toList();
  if (loose.isNotEmpty) {
    zones.add(IdeDiagramZone('', tr('Khác', 'Other'), 'noi-bo'));
  }
  final indexed = [for (var i = 0; i < zones.length; i++) (i, zones[i])]
    ..sort((a, b) {
      final r = ideTrustRank(a.$2.trust).compareTo(ideTrustRank(b.$2.trust));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
  final bands = <IdeDiagramBand>[];
  final nodeRects = <String, ({double x, double y})>{};
  const innerW = _perRow * ideDiagramNodeW + (_perRow - 1) * _gapX;
  const width = innerW + _bandPad * 2;
  var y = 0.0;
  for (final (_, zone) in indexed) {
    final members = zone.id.isEmpty
        ? loose
        : spec.nodes.where((n) => n.zone == zone.id).toList();
    if (members.isEmpty) continue;
    final rows = (members.length / _perRow).ceil();
    final bandH =
        _bandHead + rows * ideDiagramNodeH + (rows - 1) * 14 + _bandPad;
    bands.add(IdeDiagramBand(zone, (x: 0, y: y, w: width, h: bandH)));
    for (var i = 0; i < members.length; i++) {
      final row = i ~/ _perRow;
      final col = i % _perRow;
      final inRow = row == rows - 1 ? members.length - row * _perRow : _perRow;
      final rowW = inRow * ideDiagramNodeW + (inRow - 1) * _gapX;
      final x0 = _bandPad + (innerW - rowW) / 2;
      nodeRects[members[i].id] = (
        x: x0 + col * (ideDiagramNodeW + _gapX),
        y: y + _bandHead + row * (ideDiagramNodeH + 14),
      );
    }
    y += bandH + _gapY;
  }
  return IdeDiagramLayout(
    width: width,
    height: y <= 0 ? 0 : y - _gapY,
    bands: bands,
    nodeRects: nodeRects,
  );
}
