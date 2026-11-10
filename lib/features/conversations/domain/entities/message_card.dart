import 'dart:convert';

/// Thẻ có cấu trúc của tin bot / sự kiện (`message.metadata.card`).
///
/// Đọc cả bản 1 (section suy theo trường có mặt) và bản 2 (mỗi section có
/// `type`: biểu đồ, sơ đồ, kế hoạch, bảng, biểu mẫu...). Dữ liệu từ máy chủ đã
/// được kiểm, nhưng client vẫn phòng thủ: phần nào sai thì bỏ đúng phần đó,
/// mảng dài thì cắt theo giới hạn, chuỗi dài thì cắt bớt; không bao giờ ném lỗi.
/// Thẻ không đọc được (sai phiên bản, thiếu tiêu đề, quá 64 KB) trả `null` để
/// màn hình hiện `body` như tin thường.
final class MessageCard {
  const MessageCard({
    required this.version,
    required this.title,
    this.subtitle,
    this.tone = MessageCardTone.info,
    this.statusLabel,
    this.summary,
    this.facts = const [],
    this.sections = const [],
    this.actions = const [],
  });

  final int version;
  final String title;
  final String? subtitle;
  final MessageCardTone tone;
  final String? statusLabel;
  final String? summary;
  final List<MessageCardFact> facts;
  final List<MessageCardSection> sections;
  final List<MessageCardAction> actions;

  List<MessageCardForm> get forms => [
    for (final section in sections)
      if (section is MessageCardFormSection) section.form,
  ];

  /// Thẻ có nút gọi máy chủ hoặc biểu mẫu (cần tải trạng thái "đã bấm / đã gửi").
  bool get hasServerInteractions =>
      forms.isNotEmpty ||
      actions.any((action) => action is MessageCardCallbackAction);
}

enum MessageCardTone {
  success('success'),
  error('error'),
  warning('warning'),
  pending('pending'),
  info('info');

  const MessageCardTone(this.apiValue);

  final String apiValue;

  static MessageCardTone fromApi(String value) {
    for (final tone in values) {
      if (tone.apiValue == value) return tone;
    }
    return MessageCardTone.info;
  }
}

final class MessageCardFact {
  const MessageCardFact({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;
}

// ------------------------------------------------------------------ section

sealed class MessageCardSection {
  const MessageCardSection({required this.title});

  final String title;
}

final class MessageCardFactsSection extends MessageCardSection {
  const MessageCardFactsSection({required super.title, required this.facts});

  final List<MessageCardFact> facts;
}

/// Hàng dạng `tiêu đề | chi tiết | ...`.
final class MessageCardRowsSection extends MessageCardSection {
  const MessageCardRowsSection({required super.title, required this.rows});

  final List<String> rows;
}

final class MessageCardItemsSection extends MessageCardSection {
  const MessageCardItemsSection({required super.title, required this.items});

  final List<String> items;
}

final class MessageCardCommandsSection extends MessageCardSection {
  const MessageCardCommandsSection({
    required super.title,
    required this.commands,
  });

  final List<String> commands;
}

final class MessageCardChartSection extends MessageCardSection {
  const MessageCardChartSection({required super.title, required this.chart});

  final MessageCardChart chart;
}

final class MessageCardDiagramSection extends MessageCardSection {
  const MessageCardDiagramSection({
    required super.title,
    required this.diagram,
  });

  final MessageCardDiagram diagram;
}

final class MessageCardPlanSection extends MessageCardSection {
  const MessageCardPlanSection({required super.title, required this.plan});

  final MessageCardPlan plan;
}

final class MessageCardTableSection extends MessageCardSection {
  const MessageCardTableSection({required super.title, required this.table});

  final MessageCardTable table;
}

final class MessageCardFormSection extends MessageCardSection {
  const MessageCardFormSection({required super.title, required this.form});

  final MessageCardForm form;
}

// -------------------------------------------------------------------- chart

enum MessageCardChartKind { bar, line, pie }

final class MessageCardChartSeries {
  const MessageCardChartSeries({required this.name, required this.values});

  final String name;

  /// `null` = điểm thiếu / không phải số hữu hạn (không vẽ).
  final List<double?> values;
}

final class MessageCardChart {
  const MessageCardChart({
    required this.kind,
    this.labels = const [],
    this.series = const [],
    this.unit,
  });

  final MessageCardChartKind kind;
  final List<String> labels;
  final List<MessageCardChartSeries> series;
  final String? unit;

  /// Số nhóm trên trục ngang: theo `labels`, thiếu nhãn thì theo dãy dài nhất.
  int get categoryCount {
    var count = labels.length;
    for (final item in series) {
      if (item.values.length > count) count = item.values.length;
    }
    return count;
  }

  String labelAt(int index) => index < labels.length && labels[index].isNotEmpty
      ? labels[index]
      : '${index + 1}';

  bool get hasData =>
      series.any((item) => item.values.any((value) => value != null));
}

// ------------------------------------------------------------------ diagram

enum MessageCardDiagramDirection { leftToRight, topToBottom }

final class MessageCardDiagramNode {
  const MessageCardDiagramNode({
    required this.id,
    required this.label,
    this.group,
  });

  final String id;
  final String label;
  final String? group;
}

final class MessageCardDiagramEdge {
  const MessageCardDiagramEdge({
    required this.from,
    required this.to,
    this.label,
  });

  final String from;
  final String to;
  final String? label;
}

final class MessageCardDiagram {
  const MessageCardDiagram({
    this.direction = MessageCardDiagramDirection.topToBottom,
    this.nodes = const [],
    this.edges = const [],
    this.mermaid,
  });

  final MessageCardDiagramDirection direction;
  final List<MessageCardDiagramNode> nodes;
  final List<MessageCardDiagramEdge> edges;

  /// Mã mermaid chỉ để xem / chép; client không chạy mermaid.
  final String? mermaid;
}

// --------------------------------------------------------------------- plan

enum MessageCardPlanStatus {
  todo('todo'),
  inProgress('in_progress'),
  done('done'),
  blocked('blocked'),
  skipped('skipped');

  const MessageCardPlanStatus(this.apiValue);

  final String apiValue;

  static MessageCardPlanStatus fromApi(String value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return MessageCardPlanStatus.todo;
  }
}

final class MessageCardPlanStep {
  const MessageCardPlanStep({
    required this.id,
    required this.title,
    this.status = MessageCardPlanStatus.todo,
    this.owner,
    this.due,
    this.note,
  });

  final String id;
  final String title;
  final MessageCardPlanStatus status;
  final String? owner;

  /// Ngày hạn đã kiểm dạng `YYYY-MM-DD` (giờ địa phương, không múi giờ).
  final DateTime? due;
  final String? note;
}

final class MessageCardPlan {
  const MessageCardPlan({this.steps = const []});

  final List<MessageCardPlanStep> steps;
}

// -------------------------------------------------------------------- table

final class MessageCardTable {
  const MessageCardTable({this.columns = const [], this.rows = const []});

  final List<String> columns;

  /// Mỗi hàng đã được chỉnh đúng bằng số cột.
  final List<List<String>> rows;
}

// --------------------------------------------------------------------- form

enum MessageCardFieldType {
  text('text'),
  number('number'),
  select('select'),
  date('date'),
  textarea('textarea'),
  checkbox('checkbox');

  const MessageCardFieldType(this.apiValue);

  final String apiValue;

  static MessageCardFieldType? fromApi(String value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

final class MessageCardFieldOption {
  const MessageCardFieldOption({required this.value, required this.label});

  final String value;
  final String label;
}

final class MessageCardFormField {
  const MessageCardFormField({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.options = const [],
    this.min,
    this.max,
    this.maxLength,
  });

  final String id;
  final String label;
  final MessageCardFieldType type;
  final bool required;
  final String? placeholder;
  final List<MessageCardFieldOption> options;
  final double? min;
  final double? max;

  /// Chỉ cho `text` / `textarea` (mặc định 500 / 2000).
  final int? maxLength;

  int get effectiveMaxLength =>
      maxLength ??
      (type == MessageCardFieldType.textarea
          ? messageCardTextareaDefaultMaxLength
          : messageCardTextDefaultMaxLength);
}

final class MessageCardForm {
  const MessageCardForm({
    required this.formId,
    this.submitLabel = 'Gửi',
    this.allowMultiple = false,
    this.fields = const [],
  });

  final String formId;
  final String submitLabel;
  final bool allowMultiple;
  final List<MessageCardFormField> fields;
}

// ------------------------------------------------------------------ actions

enum MessageCardActionTone { primary, danger, neutral }

sealed class MessageCardAction {
  const MessageCardAction({
    required this.label,
    this.tone = MessageCardActionTone.neutral,
  });

  final String label;
  final MessageCardActionTone tone;
}

/// Bấm thì gửi `reply` như tin của người dùng vào cùng kênh.
final class MessageCardReplyAction extends MessageCardAction {
  const MessageCardReplyAction({
    required super.label,
    required this.reply,
    super.tone,
  });

  final String reply;
}

final class MessageCardCopyAction extends MessageCardAction {
  const MessageCardCopyAction({
    required super.label,
    required this.copy,
    super.tone,
  });

  final String copy;
}

/// Bấm gọi `POST .../messages/{id}/actions` với `action_id` (không gửi `value`:
/// máy chủ lấy từ thẻ đã lưu).
final class MessageCardCallbackAction extends MessageCardAction {
  const MessageCardCallbackAction({
    required super.label,
    required this.actionId,
    this.confirm,
    super.tone,
  });

  final String actionId;
  final String? confirm;
}

enum MessageCardApprovalDecision { approve, reject }

final class MessageCardApprovalAction extends MessageCardAction {
  const MessageCardApprovalAction({
    required super.label,
    required this.approvalId,
    required this.decision,
    super.tone,
  });

  final String approvalId;
  final MessageCardApprovalDecision decision;
}

// ------------------------------------------------------------------- giới hạn

const int messageCardMaxBytes = 64 * 1024;
const int messageCardMaxSectionsV1 = 8;
const int messageCardMaxSections = 12;
const int messageCardMaxActionsV1 = 4;
const int messageCardMaxActions = 6;
const int messageCardMaxFacts = 24;
const int messageCardMaxListItems = 30;
const int messageCardMaxChartSeries = 6;
const int messageCardMaxChartPoints = 200;
const int messageCardMaxDiagramNodes = 100;
const int messageCardMaxDiagramEdges = 200;
const int messageCardMaxPlanSteps = 50;
const int messageCardMaxTableColumns = 12;
const int messageCardMaxTableRows = 100;
const int messageCardMaxFormFields = 20;
const int messageCardMaxForms = 5;
const int messageCardMaxShortText = 200;
const int messageCardMaxLongText = 2000;
const int messageCardTextDefaultMaxLength = 500;
const int messageCardTextareaDefaultMaxLength = 2000;

final _formIdPattern = RegExp(r'^[a-z0-9_-]{1,64}$');
final _fieldIdPattern = RegExp(r'^[a-z0-9_]{1,64}$');
final _actionIdPattern = RegExp(r'^[a-z0-9_.-]{1,64}$');
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

// -------------------------------------------------------------------- đọc

final _cardCache = Expando<_CachedCard>('messageCard');

final class _CachedCard {
  const _CachedCard(this.card);

  final MessageCard? card;
}

/// Thẻ của tin (đọc một lần cho mỗi `metadata`, các lần dựng lại dùng lại).
MessageCard? messageCardFromMetadata(Map<String, Object?> metadata) {
  final raw = metadata['card'];
  if (raw is! Map) return null;
  final cached = _cardCache[metadata];
  if (cached != null) return cached.card;
  final card = parseMessageCard(raw);
  _cardCache[metadata] = _CachedCard(card);
  return card;
}

/// Đọc `metadata.card`. `null` khi không phải thẻ bản 1 / 2 hợp lệ.
MessageCard? parseMessageCard(Object? raw) {
  if (raw is! Map) return null;
  final card = _map(raw);
  final version = _int(card['version']);
  if (version != 1 && version != 2) return null;
  if (_jsonBytes(card) > messageCardMaxBytes) return null;
  final title = _text(card['title'], messageCardMaxShortText);
  if (title.isEmpty) return null;
  return MessageCard(
    version: version!,
    title: title,
    subtitle: _optionalText(card['subtitle'], messageCardMaxLongText),
    tone: MessageCardTone.fromApi(_text(card['status'], 32)),
    statusLabel: _optionalText(card['status_label'], messageCardMaxShortText),
    summary: _optionalText(card['summary'], messageCardMaxLongText),
    facts: _facts(card['facts']),
    sections: _sections(card['sections'], version),
    actions: _actions(card['actions'], version),
  );
}

List<MessageCardSection> _sections(Object? raw, int version) {
  if (raw is! List) return const [];
  final limit = version == 1
      ? messageCardMaxSectionsV1
      : messageCardMaxSections;
  final result = <MessageCardSection>[];
  final formIds = <String>{};
  for (final item in raw.take(limit)) {
    if (item is! Map) continue;
    final section = _map(item);
    final title = _text(section['title'], messageCardMaxShortText);
    final parsed = version == 1
        ? _v1Section(section, title.isEmpty ? 'Chi tiết' : title)
        : _v2Section(section, title, formIds);
    if (parsed != null) result.add(parsed);
  }
  return List.unmodifiable(result);
}

/// Bản 1: section không có `type`, loại suy theo trường có dữ liệu.
MessageCardSection? _v1Section(Map<String, Object?> section, String title) {
  final facts = _facts(section['facts']);
  if (facts.isNotEmpty) {
    return MessageCardFactsSection(title: title, facts: facts);
  }
  final commands = _strings(section['commands']);
  if (commands.isNotEmpty) {
    return MessageCardCommandsSection(title: title, commands: commands);
  }
  final rows = _strings(section['rows']);
  if (rows.isNotEmpty) {
    return MessageCardRowsSection(title: title, rows: rows);
  }
  final items = _strings(section['items']);
  if (items.isNotEmpty) {
    return MessageCardItemsSection(title: title, items: items);
  }
  return null;
}

MessageCardSection? _v2Section(
  Map<String, Object?> section,
  String title,
  Set<String> formIds,
) {
  switch (_text(section['type'], 32)) {
    case 'facts':
      return MessageCardFactsSection(
        title: title,
        facts: _facts(section['facts']),
      );
    case 'rows':
      return MessageCardRowsSection(
        title: title,
        rows: _strings(section['rows']),
      );
    case 'items':
      return MessageCardItemsSection(
        title: title,
        items: _strings(section['items']),
      );
    case 'commands':
      return MessageCardCommandsSection(
        title: title,
        commands: _strings(section['commands']),
      );
    case 'chart':
      final chart = _chart(section['chart']);
      return chart == null
          ? null
          : MessageCardChartSection(title: title, chart: chart);
    case 'diagram':
      final diagram = _diagram(section['diagram']);
      return diagram == null
          ? null
          : MessageCardDiagramSection(title: title, diagram: diagram);
    case 'plan':
      final plan = _plan(section['plan']);
      return plan == null
          ? null
          : MessageCardPlanSection(title: title, plan: plan);
    case 'table':
      final table = _table(section['table']);
      return table == null
          ? null
          : MessageCardTableSection(title: title, table: table);
    case 'form':
      if (formIds.length >= messageCardMaxForms) return null;
      final form = _form(section['form']);
      if (form == null || !formIds.add(form.formId)) return null;
      return MessageCardFormSection(title: title, form: form);
    default:
      return null;
  }
}

MessageCardChart? _chart(Object? raw) {
  if (raw is! Map) return null;
  final chart = _map(raw);
  final kind = switch (_text(chart['kind'], 16)) {
    'bar' => MessageCardChartKind.bar,
    'line' => MessageCardChartKind.line,
    'pie' => MessageCardChartKind.pie,
    _ => null,
  };
  if (kind == null) return null;
  final labels = chart['labels'] is List
      ? [
          for (final label in (chart['labels'] as List).take(
            messageCardMaxChartPoints,
          ))
            _text(label, messageCardMaxShortText),
        ]
      : const <String>[];
  final series = <MessageCardChartSeries>[];
  if (chart['series'] is List) {
    for (final item in chart['series'] as List) {
      if (series.length >= messageCardMaxChartSeries) break;
      if (item is! Map) continue;
      final map = _map(item);
      final values = map['values'];
      if (values is! List) continue;
      series.add(
        MessageCardChartSeries(
          name: _text(map['name'], messageCardMaxShortText),
          values: List.unmodifiable([
            for (final value in values.take(messageCardMaxChartPoints))
              _finite(value),
          ]),
        ),
      );
    }
  }
  return MessageCardChart(
    kind: kind,
    labels: List.unmodifiable(labels),
    // Biểu đồ tròn chỉ có một dãy; số âm không có nghĩa nên không vẽ.
    series: kind == MessageCardChartKind.pie
        ? [
            if (series.isNotEmpty)
              MessageCardChartSeries(
                name: series.first.name,
                values: List.unmodifiable([
                  for (final value in series.first.values)
                    value == null || value < 0 ? null : value,
                ]),
              ),
          ]
        : List.unmodifiable(series),
    unit: _optionalText(chart['unit'], messageCardMaxShortText),
  );
}

MessageCardDiagram? _diagram(Object? raw) {
  if (raw is! Map) return null;
  final diagram = _map(raw);
  final nodes = <MessageCardDiagramNode>[];
  final ids = <String>{};
  if (diagram['nodes'] is List) {
    for (final item in diagram['nodes'] as List) {
      if (nodes.length >= messageCardMaxDiagramNodes) break;
      if (item is! Map) continue;
      final map = _map(item);
      final id = _text(map['id'], messageCardMaxShortText);
      if (id.isEmpty || !ids.add(id)) continue;
      final label = _text(map['label'], messageCardMaxShortText);
      nodes.add(
        MessageCardDiagramNode(
          id: id,
          label: label.isEmpty ? id : label,
          group: _optionalText(map['group'], messageCardMaxShortText),
        ),
      );
    }
  }
  final edges = <MessageCardDiagramEdge>[];
  if (diagram['edges'] is List) {
    for (final item in diagram['edges'] as List) {
      if (edges.length >= messageCardMaxDiagramEdges) break;
      if (item is! Map) continue;
      final map = _map(item);
      final from = _text(map['from'], messageCardMaxShortText);
      final to = _text(map['to'], messageCardMaxShortText);
      // Cạnh trỏ tới node không có thật: bỏ riêng cạnh đó.
      if (!ids.contains(from) || !ids.contains(to)) continue;
      edges.add(
        MessageCardDiagramEdge(
          from: from,
          to: to,
          label: _optionalText(map['label'], messageCardMaxShortText),
        ),
      );
    }
  }
  return MessageCardDiagram(
    direction: _text(diagram['direction'], 8) == 'LR'
        ? MessageCardDiagramDirection.leftToRight
        : MessageCardDiagramDirection.topToBottom,
    nodes: List.unmodifiable(nodes),
    edges: List.unmodifiable(edges),
    mermaid: _optionalText(
      diagram['mermaid'],
      messageCardMaxLongText,
      trim: false,
    ),
  );
}

MessageCardPlan? _plan(Object? raw) {
  if (raw is! Map) return null;
  final plan = _map(raw);
  final steps = <MessageCardPlanStep>[];
  if (plan['steps'] is List) {
    for (final item in plan['steps'] as List) {
      if (steps.length >= messageCardMaxPlanSteps) break;
      if (item is! Map) continue;
      final map = _map(item);
      final title = _text(map['title'], messageCardMaxShortText);
      if (title.isEmpty) continue;
      steps.add(
        MessageCardPlanStep(
          id: _text(map['id'], 64),
          title: title,
          status: MessageCardPlanStatus.fromApi(_text(map['status'], 32)),
          owner: _optionalText(map['owner'], messageCardMaxShortText),
          due: parseMessageCardDate(_text(map['due'], 16)),
          note: _optionalText(map['note'], messageCardMaxLongText),
        ),
      );
    }
  }
  return MessageCardPlan(steps: List.unmodifiable(steps));
}

MessageCardTable? _table(Object? raw) {
  if (raw is! Map) return null;
  final table = _map(raw);
  final columns = table['columns'] is List
      ? [
          for (final column in (table['columns'] as List).take(
            messageCardMaxTableColumns,
          ))
            _text(column, messageCardMaxShortText),
        ]
      : <String>[];
  final rawRows = table['rows'] is List
      ? [
          for (final row in (table['rows'] as List).take(
            messageCardMaxTableRows,
          ))
            if (row is List) row,
        ]
      : const <List<dynamic>>[];
  var width = columns.length;
  if (width == 0) {
    for (final row in rawRows) {
      if (row.length > width) width = row.length;
    }
    if (width > messageCardMaxTableColumns) width = messageCardMaxTableColumns;
    columns.addAll(List.filled(width, ''));
  }
  final rows = [
    for (final row in rawRows)
      List<String>.unmodifiable([
        for (var index = 0; index < width; index++)
          index < row.length ? _text(row[index], messageCardMaxLongText) : '',
      ]),
  ];
  return MessageCardTable(
    columns: List.unmodifiable(columns),
    rows: List.unmodifiable(rows),
  );
}

MessageCardForm? _form(Object? raw) {
  if (raw is! Map) return null;
  final form = _map(raw);
  final formId = _text(form['form_id'], 64);
  if (!_formIdPattern.hasMatch(formId)) return null;
  final fields = <MessageCardFormField>[];
  final fieldIds = <String>{};
  if (form['fields'] is List) {
    for (final item in form['fields'] as List) {
      if (fields.length >= messageCardMaxFormFields) break;
      if (item is! Map) continue;
      final field = _formField(_map(item));
      if (field == null || !fieldIds.add(field.id)) continue;
      fields.add(field);
    }
  }
  final submitLabel = _text(form['submit_label'], messageCardMaxShortText);
  return MessageCardForm(
    formId: formId,
    submitLabel: submitLabel.isEmpty ? 'Gửi' : submitLabel,
    allowMultiple: form['allow_multiple'] == true,
    fields: List.unmodifiable(fields),
  );
}

MessageCardFormField? _formField(Map<String, Object?> map) {
  final id = _text(map['id'], 64);
  if (!_fieldIdPattern.hasMatch(id)) return null;
  final type = MessageCardFieldType.fromApi(_text(map['type'], 16));
  if (type == null) return null;
  final options = <MessageCardFieldOption>[];
  if (type == MessageCardFieldType.select && map['options'] is List) {
    final seen = <String>{};
    for (final item in map['options'] as List) {
      if (item is! Map) continue;
      final option = _map(item);
      final value = _text(option['value'], messageCardMaxShortText);
      if (value.isEmpty || !seen.add(value)) continue;
      final label = _text(option['label'], messageCardMaxShortText);
      options.add(
        MessageCardFieldOption(
          value: value,
          label: label.isEmpty ? value : label,
        ),
      );
    }
    // Ô chọn không có lựa chọn nào thì không điền được: bỏ ô đó.
    if (options.isEmpty) return null;
  }
  final label = _text(map['label'], messageCardMaxShortText);
  final isText =
      type == MessageCardFieldType.text ||
      type == MessageCardFieldType.textarea;
  final maxLength = isText ? _int(map['max_length']) : null;
  final isNumber = type == MessageCardFieldType.number;
  return MessageCardFormField(
    id: id,
    label: label.isEmpty ? id : label,
    type: type,
    required: map['required'] == true,
    placeholder: _optionalText(map['placeholder'], messageCardMaxShortText),
    options: List.unmodifiable(options),
    min: isNumber ? _finite(map['min']) : null,
    max: isNumber ? _finite(map['max']) : null,
    maxLength: maxLength != null && maxLength > 0 ? maxLength : null,
  );
}

List<MessageCardAction> _actions(Object? raw, int version) {
  if (raw is! List) return const [];
  final limit = version == 1 ? messageCardMaxActionsV1 : messageCardMaxActions;
  final result = <MessageCardAction>[];
  for (final item in raw) {
    if (result.length >= limit) break;
    if (item is! Map) continue;
    final action = _action(_map(item));
    if (action != null) result.add(action);
  }
  return List.unmodifiable(result);
}

MessageCardAction? _action(Map<String, Object?> map) {
  final label = _text(map['label'], messageCardMaxShortText);
  if (label.isEmpty) return null;
  final tone = switch (_text(map['tone'], 16)) {
    'primary' => MessageCardActionTone.primary,
    'danger' => MessageCardActionTone.danger,
    _ => MessageCardActionTone.neutral,
  };
  final reply = _text(map['reply'], messageCardMaxLongText);
  final copy = _text(map['copy'], messageCardMaxLongText);
  final declared = _text(map['type'], 32);
  final type = declared.isNotEmpty
      ? declared
      : reply.isNotEmpty
      ? 'reply'
      : copy.isNotEmpty
      ? 'copy'
      : '';
  switch (type) {
    case 'reply':
      return reply.isEmpty
          ? null
          : MessageCardReplyAction(label: label, reply: reply, tone: tone);
    case 'copy':
      return copy.isEmpty
          ? null
          : MessageCardCopyAction(label: label, copy: copy, tone: tone);
    case 'callback':
      final actionId = _text(map['action_id'], 64);
      if (!_actionIdPattern.hasMatch(actionId)) return null;
      return MessageCardCallbackAction(
        label: label,
        actionId: actionId,
        confirm: _optionalText(map['confirm'], messageCardMaxLongText),
        tone: tone,
      );
    case 'approval_decision':
      final approvalId = _text(map['approval_id'], 64);
      final decision = switch (_text(map['decision'], 16)) {
        'approve' => MessageCardApprovalDecision.approve,
        'reject' => MessageCardApprovalDecision.reject,
        _ => null,
      };
      if (!_uuidPattern.hasMatch(approvalId) || decision == null) return null;
      return MessageCardApprovalAction(
        label: label,
        approvalId: approvalId,
        decision: decision,
        tone: tone,
      );
    default:
      return null;
  }
}

List<MessageCardFact> _facts(Object? raw) {
  if (raw is! List) return const [];
  final result = <MessageCardFact>[];
  for (final item in raw) {
    if (result.length >= messageCardMaxFacts) break;
    if (item is! Map) continue;
    final map = _map(item);
    final label = _text(map['label'], messageCardMaxShortText);
    final value = _text(map['value'], messageCardMaxLongText);
    if (label.isEmpty || value.isEmpty) continue;
    result.add(
      MessageCardFact(
        label: label,
        value: value,
        emphasis: map['emphasis'] == true,
      ),
    );
  }
  return List.unmodifiable(result);
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const [];
  final result = <String>[];
  for (final item in raw) {
    if (result.length >= messageCardMaxListItems) break;
    final text = _text(item, messageCardMaxLongText);
    if (text.isNotEmpty) result.add(text);
  }
  return List.unmodifiable(result);
}

/// Ngày `YYYY-MM-DD` có thật (không nhận 2026-02-30).
DateTime? parseMessageCardDate(String value) {
  final match = _datePattern.firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

Map<String, Object?> _map(Map<dynamic, dynamic> value) => {
  for (final entry in value.entries) entry.key.toString(): entry.value,
};

String _text(Object? value, int maxLength, {bool trim = true}) {
  final text = switch (value) {
    final String text => trim ? text.trim() : text,
    final num number when number.isFinite => _numberText(number),
    _ => '',
  };
  if (text.length <= maxLength) return text;
  // Cắt theo ký tự (rune) để không làm hỏng chữ có dấu / emoji.
  return String.fromCharCodes(text.runes.take(maxLength));
}

String? _optionalText(Object? value, int maxLength, {bool trim = true}) {
  final text = _text(value, maxLength, trim: trim);
  return text.trim().isEmpty ? null : text;
}

String _numberText(num value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? value.toInt().toString()
    : value.toString();

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

double? _finite(Object? value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite ? number : null;
}

int _jsonBytes(Map<String, Object?> value) {
  try {
    return utf8.encode(jsonEncode(value)).length;
  } on Object {
    return messageCardMaxBytes + 1;
  }
}
