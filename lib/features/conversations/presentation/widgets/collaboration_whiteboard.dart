import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../data/datasources/conversation_remote_data_source.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/entities/whiteboard_document.dart';

/// Bảng trắng cộng tác của một phòng: tự tải tài liệu `whiteboard`, tự lưu
/// (kèm `expected_version`) sau mỗi thao tác và tải bản mới định kỳ khi đang
/// hiện. Định dạng dữ liệu dùng chung với web: xem `whiteboard_document.dart`.
class CollaborationWhiteboard extends ConsumerStatefulWidget {
  const CollaborationWhiteboard({
    required this.workspaceId,
    required this.channelId,
    this.active = true,
    this.pollInterval = const Duration(seconds: 5),
    this.saveDelay = const Duration(milliseconds: 600),
    super.key,
  });

  final String workspaceId;
  final String channelId;

  /// Tab Bảng trắng đang hiện: chỉ khi đó mới tải bản mới định kỳ.
  final bool active;
  final Duration pollInterval;
  final Duration saveDelay;

  @override
  ConsumerState<CollaborationWhiteboard> createState() =>
      _CollaborationWhiteboardState();
}

enum _Tool {
  pen(Icons.edit_outlined, 'Bút', 'Vẽ bằng một ngón tay · tự lưu sau mỗi nét'),
  eraser(
    Icons.cleaning_services_outlined,
    'Tẩy',
    'Chạm hoặc kéo qua nét, hình để xoá',
  ),
  select(
    Icons.pan_tool_alt_outlined,
    'Chọn và di chuyển',
    'Chạm vào hình, chữ, biểu tượng rồi kéo để di chuyển',
  ),
  rect(Icons.crop_square_rounded, 'Hình chữ nhật', 'Kéo trên bảng để vẽ hình'),
  ellipse(Icons.circle_outlined, 'Hình tròn', 'Kéo trên bảng để vẽ hình'),
  arrow(Icons.north_east_rounded, 'Mũi tên', 'Kéo trên bảng để vẽ mũi tên'),
  text(Icons.text_fields_rounded, 'Chữ', 'Chạm vào chỗ muốn đặt chữ'),
  icon(
    Icons.emoji_emotions_outlined,
    'Biểu tượng',
    'Chọn biểu tượng rồi chạm vào chỗ muốn đặt',
  );

  const _Tool(this.glyph, this.label, this.hint);

  final IconData glyph;
  final String label;
  final String hint;

  bool get isShape =>
      this == _Tool.rect || this == _Tool.ellipse || this == _Tool.arrow;
}

const _colors = [
  ('#111827', 'Màu đen'),
  ('#2563eb', 'Màu xanh dương'),
  ('#16a34a', 'Màu xanh lá'),
  ('#ea580c', 'Màu cam'),
  ('#dc2626', 'Màu đỏ'),
  ('#9333ea', 'Màu tím'),
];

const _strokeWidths = [(2.0, 'Nét mảnh'), (4.0, 'Nét vừa'), (8.0, 'Nét đậm')];

const _textSizes = [(20.0, 'Chữ nhỏ'), (28.0, 'Chữ vừa'), (40.0, 'Chữ lớn')];

const _icons = [
  ('✅', 'Đã xong'),
  ('❌', 'Không được'),
  ('⭐', 'Nổi bật'),
  ('❗', 'Chú ý'),
  ('❓', 'Câu hỏi'),
  ('👍', 'Đồng ý'),
  ('👎', 'Không đồng ý'),
  ('💡', 'Ý tưởng'),
  ('📌', 'Ghim'),
  ('🔥', 'Gấp'),
  ('➡️', 'Sang phải'),
  ('⬅️', 'Sang trái'),
  ('⬆️', 'Lên trên'),
  ('⬇️', 'Xuống dưới'),
  ('⚠️', 'Cảnh báo'),
  ('🎯', 'Mục tiêu'),
  ('📅', 'Lịch hẹn'),
  ('💬', 'Trao đổi'),
  ('✏️', 'Cần sửa'),
  ('🚀', 'Triển khai'),
];

/// Bán kính chạm (điểm ảnh màn hình) cho tẩy và chọn.
const double _touchSlopPx = 12;

/// Hình kéo ngắn hơn ngưỡng này (đơn vị khung) coi như chạm nhầm, bỏ qua.
const double _minShapeSize = 4;

/// Một thao tác của người dùng: các bước áp vào và các bước hoàn tác.
final class _Command {
  const _Command(this.forward, this.backward);

  final List<WhiteboardOp> forward;
  final List<WhiteboardOp> backward;
}

class _CollaborationWhiteboardState
    extends ConsumerState<CollaborationWhiteboard> {
  late final ConversationRemoteDataSource _remote;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ScaffoldMessengerState? _outerMessenger;

  WhiteboardDocument _document = const WhiteboardDocument();
  int? _version;
  bool _loading = true;
  String? _loadError;

  /// Thao tác đã áp vào `_document` nhưng máy chủ chưa nhận.
  final List<WhiteboardOp> _pending = [];
  bool _saving = false;
  String? _saveError;
  bool _retrySaveOnTick = false;
  String? _lastNotice;
  Timer? _saveTimer;
  Timer? _pollTimer;
  bool _polling = false;
  bool _disposed = false;

  final List<_Command> _undoStack = [];
  final List<_Command> _redoStack = [];

  _Tool _tool = _Tool.pen;
  String _color = _colors[1].$1;
  double _strokeWidth = 4;
  double _textSize = 28;
  String _icon = '👍';
  String? _selectedId;

  int? _pointer;
  WhiteboardPoint? _downPoint;
  WhiteboardPoint? _lastPoint;
  WhiteboardStroke? _draftStroke;
  WhiteboardElement? _draftElement;
  WhiteboardElement? _moveOrigin;
  WhiteboardElement? _moveCurrent;
  final List<WhiteboardStroke> _erasedStrokes = [];
  final List<WhiteboardElement> _erasedElements = [];

  bool get _ready => _version != null;

  bool get _hasUnsaved => _pending.isNotEmpty || _saveTimer != null;

  @override
  void initState() {
    super.initState();
    _remote = ref.read(conversationRemoteDataSourceProvider);
    _syncPolling();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _outerMessenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant CollaborationWhiteboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncPolling();
      if (widget.active && _ready) unawaited(_poll());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _saveTimer?.cancel();
    _saveTimer = null;
    // Đóng bảng khi còn thay đổi chưa lưu: vẫn gửi nốt, lỗi thì báo ra ngoài.
    if (_pending.isNotEmpty && !_saving) unawaited(_flush());
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted && !_disposed) {
      setState(change);
    } else {
      change();
    }
  }

  void _syncPolling() {
    if (widget.active) {
      _pollTimer ??= Timer.periodic(
        widget.pollInterval,
        (_) => unawaited(_poll()),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<CollaborationDocument> _fetch() => _remote.getCollaborationDocument(
    workspaceId: widget.workspaceId,
    channelId: widget.channelId,
    kind: 'whiteboard',
  );

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await guardResult(_fetch);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(:final value):
          _adopt(value);
        case FailureResult(:final failure):
          _loadError = userFacingErrorMessage(failure);
      }
    });
  }

  /// Nhận bản trên máy chủ làm bản đang xem (chỉ gọi khi không còn gì chờ lưu).
  void _adopt(CollaborationDocument document) {
    _document = WhiteboardDocument.parse(document.content);
    _version = document.version;
    if (_selectedId != null && _document.elementById(_selectedId!) == null) {
      _selectedId = null;
    }
  }

  Future<void> _poll() async {
    if (!mounted || !_ready || _polling || _saving || _pointer != null) return;
    if (_hasUnsaved) {
      // Lần lưu trước hỏng vì mạng: thử gửi lại theo nhịp tải định kỳ.
      if (_retrySaveOnTick && _saveTimer == null) unawaited(_flush());
      return;
    }
    _polling = true;
    final result = await guardResult(_fetch);
    _polling = false;
    if (!mounted || _hasUnsaved || _saving || _pointer != null) return;
    if (result case Success(:final value) when value.version != _version) {
      setState(() => _adopt(value));
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    if (_disposed) {
      _saveTimer = null;
      unawaited(_flush());
      return;
    }
    _saveTimer = Timer(widget.saveDelay, () {
      _saveTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final version = _version;
    if (_saving || _pending.isEmpty || version == null) return;
    var content = _document.toJson();
    if (whiteboardContentBytes(content) > whiteboardMaxBytes) {
      _failSave(whiteboardTooLargeMessage, retryOnTick: false);
      return;
    }
    _update(() => _saving = true);
    var sentOps = _pending.length;
    var result = await guardResult(() => _put(content, version));
    if (result case FailureResult(
      :final failure,
    ) when failure.kind == FailureKind.conflict) {
      // Có người vừa lưu trước: lấy bản mới nhất, áp lại các thao tác chưa
      // lưu (thêm nét / phần tử mới, xoá theo id) rồi lưu lại một lần.
      final latest = await guardResult(_fetch);
      switch (latest) {
        case Success(value: final fresh):
          var rebased = WhiteboardDocument.parse(fresh.content);
          for (final op in _pending) {
            rebased = op.applyTo(rebased);
          }
          _update(() {
            _document = rebased;
            _version = fresh.version;
            if (_selectedId != null &&
                rebased.elementById(_selectedId!) == null) {
              _selectedId = null;
            }
          });
          content = rebased.toJson();
          if (whiteboardContentBytes(content) > whiteboardMaxBytes) {
            _update(() => _saving = false);
            _failSave(whiteboardTooLargeMessage, retryOnTick: false);
            return;
          }
          sentOps = _pending.length;
          result = await guardResult(() => _put(content, fresh.version));
        case FailureResult(:final failure):
          result = FailureResult(failure);
      }
    }
    switch (result) {
      case Success(:final value):
        _update(() {
          _saving = false;
          _version = value.version;
          _pending.removeRange(0, math.min(sentOps, _pending.length));
          _saveError = null;
          _retrySaveOnTick = false;
          _lastNotice = null;
        });
        if (_pending.isNotEmpty) _scheduleSave();
      case FailureResult(:final failure):
        _update(() => _saving = false);
        final offline =
            failure.kind == FailureKind.network ||
            failure.kind == FailureKind.timeout;
        _failSave(
          failure.kind == FailureKind.conflict
              ? 'Bảng trắng vừa có người khác sửa nên chưa lưu được. '
                    'Bấm Thử lại để lưu.'
              : offline
              ? 'Mất kết nối: thay đổi trên bảng trắng chưa được lưu, '
                    'sẽ thử lưu lại.'
              : 'Chưa lưu được bảng trắng: ${userFacingErrorMessage(failure)}',
          retryOnTick: offline,
        );
    }
  }

  Future<CollaborationDocument> _put(
    Map<String, Object?> content,
    int version,
  ) {
    return _remote.updateCollaborationDocument(
      workspaceId: widget.workspaceId,
      channelId: widget.channelId,
      kind: 'whiteboard',
      content: content,
      expectedVersion: version,
    );
  }

  void _failSave(String message, {required bool retryOnTick}) {
    _update(() {
      _saveError = message;
      _retrySaveOnTick = retryOnTick;
    });
    // Lỗi lặp lại giống hệt (thử lại theo nhịp) thì không báo dồn dập.
    if (message == _lastNotice) return;
    _lastNotice = message;
    _notice(message, retry: message != whiteboardTooLargeMessage);
  }

  void _notice(String message, {bool retry = false}) {
    final messenger = _disposed ? null : _messengerKey.currentState;
    final target = messenger ?? _outerMessenger;
    if (target == null || !target.mounted) return;
    target
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          // Tự ẩn để không che chân bảng; nút "Lưu lại" ở chân bảng vẫn còn.
          persist: false,
          duration: const Duration(seconds: 6),
          action: retry && messenger != null
              ? SnackBarAction(label: 'Thử lại', onPressed: _retrySave)
              : null,
        ),
      );
  }

  void _retrySave() {
    _lastNotice = null;
    unawaited(_flush());
  }

  // ---------------------------------------------------------------- thao tác

  void _commit(_Command command) {
    var next = _document;
    for (final op in command.forward) {
      next = op.applyTo(next);
    }
    if (command.forward.any((op) => op is WhiteboardAddOp) && next.isTooLarge) {
      _notice(whiteboardTooLargeMessage);
      return;
    }
    setState(() {
      _document = next;
      _pending.addAll(command.forward);
      _pushUndo(command);
    });
    _scheduleSave();
  }

  void _pushUndo(_Command command) {
    _undoStack.add(command);
    if (_undoStack.length > 100) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _replay(List<WhiteboardOp> ops) {
    for (final op in ops) {
      _document = op.applyTo(_document);
      _pending.add(op);
    }
    if (_selectedId != null && _document.elementById(_selectedId!) == null) {
      _selectedId = null;
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      final command = _undoStack.removeLast();
      _replay(command.backward);
      _redoStack.add(command);
    });
    _scheduleSave();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      final command = _redoStack.removeLast();
      _replay(command.forward);
      _undoStack.add(command);
    });
    _scheduleSave();
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá toàn bộ bảng trắng?'),
        content: const Text(
          'Mọi nét vẽ, hình, chữ và biểu tượng sẽ bị xoá với cả phòng. '
          'Có thể bấm Hoàn tác ngay sau đó.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: WebTuiColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá tất cả'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final current = _document;
    _commit(
      _Command(
        [
          WhiteboardRemoveOp({
            for (final stroke in current.strokes) stroke.id,
            for (final element in current.elements) element.id,
          }, clearUnknown: true),
        ],
        [
          WhiteboardAddOp(
            strokes: current.strokes,
            elements: current.elements,
            unknownStrokes: current.unknownStrokes,
            unknownElements: current.unknownElements,
          ),
        ],
      ),
    );
    setState(() => _selectedId = null);
  }

  void _deleteSelected() {
    final id = _selectedId;
    final element = id == null ? null : _document.elementById(id);
    if (element == null) return;
    _commit(
      _Command(
        [
          WhiteboardRemoveOp({element.id}),
        ],
        [
          WhiteboardAddOp(elements: [element]),
        ],
      ),
    );
    setState(() => _selectedId = null);
  }

  // ------------------------------------------------------------------ cử chỉ

  WhiteboardPoint _toBoard(Offset position, Size size) => WhiteboardPoint(
    position.dx / size.width * whiteboardWidth,
    position.dy / size.height * whiteboardHeight,
  ).clamped();

  double _tolerance(Size size) => _touchSlopPx * whiteboardWidth / size.width;

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (_pointer != null || !_ready || size.isEmpty) return;
    _pointer = event.pointer;
    final point = _toBoard(event.localPosition, size);
    _downPoint = point;
    _lastPoint = point;
    setState(() {
      switch (_tool) {
        case _Tool.pen:
          _draftStroke = WhiteboardStroke(
            id: createWhiteboardId('s'),
            color: _color,
            width: _strokeWidth,
            points: [point],
          );
        case _Tool.eraser:
          _erasedStrokes.clear();
          _erasedElements.clear();
          _eraseAt(point, _tolerance(size));
        case _Tool.select:
          _selectedId = _document.hitTest(
            point,
            tolerance: _tolerance(size),
            includeStrokes: false,
            shapeInteriors: true,
          );
          _moveOrigin = _selectedId == null
              ? null
              : _document.elementById(_selectedId!);
          _moveCurrent = _moveOrigin;
        case _Tool.rect || _Tool.ellipse || _Tool.arrow:
          _draftElement = _shapeBetween(point, point);
        case _Tool.text || _Tool.icon:
          break;
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _pointer) return;
    final point = _toBoard(event.localPosition, size);
    final previous = _lastPoint ?? point;
    switch (_tool) {
      case _Tool.pen:
        final stroke = _draftStroke;
        if (stroke == null ||
            point.distanceTo(stroke.points.last) < whiteboardMinPointDistance) {
          return;
        }
        setState(
          () =>
              _draftStroke = stroke.copyWith(points: [...stroke.points, point]),
        );
      case _Tool.eraser:
        // Lấy mẫu dọc đoạn vừa kéo để vuốt nhanh vẫn trúng nét mảnh.
        final tolerance = _tolerance(size);
        final steps = math.max(
          1,
          (previous.distanceTo(point) / (tolerance / 2)).ceil(),
        );
        setState(() {
          for (var step = 1; step <= steps; step++) {
            final t = step / steps;
            _eraseAt(
              WhiteboardPoint(
                previous.x + (point.x - previous.x) * t,
                previous.y + (point.y - previous.y) * t,
              ),
              tolerance,
            );
          }
        });
      case _Tool.select:
        final origin = _moveOrigin;
        final down = _downPoint;
        if (origin == null || down == null) return;
        setState(
          () => _moveCurrent = origin.moveWithin(
            point.x - down.x,
            point.y - down.y,
          ),
        );
      case _Tool.rect || _Tool.ellipse || _Tool.arrow:
        final down = _downPoint;
        if (down == null) return;
        setState(() => _draftElement = _shapeBetween(down, point));
      case _Tool.text || _Tool.icon:
        break;
    }
    _lastPoint = point;
  }

  void _onPointerUp(PointerEvent event, Size size, {bool cancelled = false}) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final point = cancelled
        ? (_lastPoint ?? _downPoint)
        : _toBoard(event.localPosition, size);
    final stroke = _draftStroke;
    final draftElement = _draftElement;
    final origin = _moveOrigin;
    final moved = _moveCurrent;
    setState(() {
      _draftStroke = null;
      _draftElement = null;
      _moveOrigin = null;
      _moveCurrent = null;
    });
    switch (_tool) {
      case _Tool.pen:
        if (stroke == null) return;
        final finished = stroke.copyWith(
          points: simplifyWhiteboardPoints(stroke.points),
        );
        _commit(
          _Command(
            [
              WhiteboardAddOp(strokes: [finished]),
            ],
            [
              WhiteboardRemoveOp({finished.id}),
            ],
          ),
        );
      case _Tool.eraser:
        if (_erasedStrokes.isEmpty && _erasedElements.isEmpty) return;
        final erased = _Command(
          [
            WhiteboardRemoveOp({
              for (final item in _erasedStrokes) item.id,
              for (final item in _erasedElements) item.id,
            }),
          ],
          [
            WhiteboardAddOp(
              strokes: List.of(_erasedStrokes),
              elements: List.of(_erasedElements),
            ),
          ],
        );
        _erasedStrokes.clear();
        _erasedElements.clear();
        // Các bước xoá đã áp và chờ lưu ngay khi kéo; chỉ cần ghi hoàn tác.
        setState(() => _pushUndo(erased));
        _scheduleSave();
      case _Tool.select:
        if (origin == null || moved == null || cancelled) return;
        if (_samePosition(origin.bounds, moved.bounds)) return;
        _commit(
          _Command([WhiteboardReplaceOp(moved)], [WhiteboardReplaceOp(origin)]),
        );
      case _Tool.rect || _Tool.ellipse || _Tool.arrow:
        if (draftElement == null || cancelled || !_bigEnough(draftElement)) {
          return;
        }
        final element = draftElement.withId(createWhiteboardId('e'));
        _commit(
          _Command(
            [
              WhiteboardAddOp(elements: [element]),
            ],
            [
              WhiteboardRemoveOp({element.id}),
            ],
          ),
        );
      case _Tool.text:
        if (cancelled || point == null) return;
        unawaited(_placeText(point));
      case _Tool.icon:
        if (cancelled || point == null) return;
        _addElement(
          WhiteboardIcon(
            id: createWhiteboardId('e'),
            x: point.x,
            y: point.y,
            icon: _icon,
          ).moveWithin(0, 0),
        );
    }
  }

  void _eraseAt(WhiteboardPoint point, double tolerance) {
    final id = _document.hitTest(point, tolerance: tolerance);
    if (id == null) return;
    final stroke = _document.strokeById(id);
    final element = _document.elementById(id);
    if (stroke != null) _erasedStrokes.add(stroke);
    if (element != null) _erasedElements.add(element);
    final op = WhiteboardRemoveOp({id});
    _document = op.applyTo(_document);
    _pending.add(op);
    if (_selectedId == id) _selectedId = null;
  }

  WhiteboardElement _shapeBetween(WhiteboardPoint start, WhiteboardPoint end) {
    if (_tool == _Tool.arrow) {
      return WhiteboardArrow(
        id: 'draft',
        x1: start.x,
        y1: start.y,
        x2: end.x,
        y2: end.y,
        color: _color,
        width: _strokeWidth,
      );
    }
    return WhiteboardShape.fromCorners(
      id: 'draft',
      kind: _tool == _Tool.ellipse
          ? WhiteboardShapeKind.ellipse
          : WhiteboardShapeKind.rect,
      start: start,
      end: end,
      color: _color,
      width: _strokeWidth,
    );
  }

  bool _bigEnough(WhiteboardElement element) => switch (element) {
    WhiteboardArrow() => element.length >= _minShapeSize,
    _ =>
      element.bounds.width >= _minShapeSize ||
          element.bounds.height >= _minShapeSize,
  };

  bool _samePosition(WhiteboardBounds a, WhiteboardBounds b) =>
      a.left == b.left && a.top == b.top;

  void _addElement(WhiteboardElement element) {
    _commit(
      _Command(
        [
          WhiteboardAddOp(elements: [element]),
        ],
        [
          WhiteboardRemoveOp({element.id}),
        ],
      ),
    );
  }

  Future<void> _placeText(WhiteboardPoint point) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _TextInputDialog(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    _addElement(
      WhiteboardText(
        id: createWhiteboardId('e'),
        x: point.x,
        y: point.y,
        text: text.trim(),
        color: _color,
        size: _textSize,
      ).moveWithin(0, 0),
    );
  }

  void _selectTool(_Tool tool) {
    setState(() {
      _tool = tool;
      if (tool != _Tool.select) _selectedId = null;
    });
  }

  // --------------------------------------------------------------- giao diện

  @override
  Widget build(BuildContext context) {
    // ScaffoldMessenger riêng: SnackBar hiện ngay trong bảng (bảng nằm trong
    // bottom sheet che mất SnackBar của màn hình bên dưới).
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Container(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          decoration: BoxDecoration(
            color: WebTuiColors.surface,
            border: Border.all(color: WebTuiColors.border),
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // Thẻ ôm vừa nội dung: khung vẽ giữ tỉ lệ 800:420 nên trên điện
          // thoại dọc bị giới hạn theo chiều ngang; chỉ co lại khi thiếu chỗ.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              if (_loading && !_ready)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!_ready)
                _buildLoadError()
              else ...[
                const SizedBox(height: WebTuiSpacing.xs),
                _buildTools(),
                const SizedBox(height: WebTuiSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: _buildOptions(),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                Flexible(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1,
                    child: AspectRatio(
                      aspectRatio: whiteboardWidth / whiteboardHeight,
                      child: _buildCanvas(),
                    ),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                _buildFooter(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.draw_outlined, color: WebTuiColors.primary, size: 20),
        const SizedBox(width: WebTuiSpacing.sm),
        Expanded(
          child: Text(
            _version == null ? 'Bảng trắng' : 'Bảng trắng · v$_version',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _ToolButton(
          label: 'Hoàn tác',
          icon: Icons.undo_rounded,
          onPressed: _ready && _undoStack.isNotEmpty ? _undo : null,
        ),
        _ToolButton(
          label: 'Làm lại',
          icon: Icons.redo_rounded,
          onPressed: _ready && _redoStack.isNotEmpty ? _redo : null,
        ),
        _ToolButton(
          label: 'Xoá tất cả',
          icon: Icons.delete_sweep_outlined,
          onPressed: _ready && !_document.isEmpty ? _confirmClear : null,
        ),
      ],
    );
  }

  Widget _buildLoadError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: WebTuiColors.textMuted,
            size: 34,
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            _loadError ?? 'Không tải được bảng trắng.',
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall,
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          FilledButton(onPressed: _retryLoad, child: const Text('Thử lại')),
        ],
      ),
    );
  }

  Widget _buildTools() {
    final shapeTool = _tool.isShape ? _tool : _Tool.rect;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tool in const [_Tool.pen, _Tool.eraser, _Tool.select])
            _ToolButton(
              label: tool.label,
              icon: tool.glyph,
              selected: _tool == tool,
              onPressed: () => _selectTool(tool),
            ),
          _ToolButton(
            label: 'Hình',
            icon: Icons.shape_line_outlined,
            selected: _tool.isShape,
            onPressed: () => _selectTool(shapeTool),
          ),
          for (final tool in const [_Tool.text, _Tool.icon])
            _ToolButton(
              label: tool.label,
              icon: tool.glyph,
              selected: _tool == tool,
              onPressed: () => _selectTool(tool),
            ),
        ],
      ),
    );
  }

  Widget _buildOptions() {
    final groups = switch (_tool) {
      _Tool.pen => [_widthGroup(), _colorGroup()],
      _Tool.rect ||
      _Tool.ellipse ||
      _Tool.arrow => [_shapeGroup(), _widthGroup(), _colorGroup()],
      _Tool.text => [_textSizeGroup(), _colorGroup()],
      _Tool.icon => [_iconGroup()],
      _Tool.select => [_selectionGroup()],
      _Tool.eraser => <Widget>[],
    };
    return Wrap(
      spacing: WebTuiSpacing.md,
      runSpacing: WebTuiSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: groups,
    );
  }

  Widget _group(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);

  Widget _shapeGroup() => _group([
    for (final tool in const [_Tool.rect, _Tool.ellipse, _Tool.arrow])
      _ToolButton(
        label: tool.label,
        icon: tool.glyph,
        selected: _tool == tool,
        onPressed: () => _selectTool(tool),
      ),
  ]);

  Widget _widthGroup() => _group([
    for (final (width, label) in _strokeWidths)
      _ToolButton(
        label: label,
        selected: _strokeWidth == width,
        onPressed: () => setState(() => _strokeWidth = width),
        child: Container(
          width: 22,
          height: width + 1,
          decoration: BoxDecoration(
            color: WebTuiColors.textPrimary,
            borderRadius: BorderRadius.circular(width),
          ),
        ),
      ),
  ]);

  Widget _textSizeGroup() => _group([
    for (final (size, label) in _textSizes)
      _ToolButton(
        label: label,
        selected: _textSize == size,
        onPressed: () => setState(() => _textSize = size),
        child: Text(
          'A',
          style: TextStyle(
            color: WebTuiColors.textPrimary,
            fontSize: size / 2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
  ]);

  Widget _colorGroup() => _group([
    for (final (value, label) in _colors)
      _ToolButton(
        label: label,
        selected: _color == value,
        onPressed: () => setState(() => _color = value),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: parseWhiteboardColor(value),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: WebTuiColors.border, spreadRadius: 1),
            ],
          ),
        ),
      ),
  ]);

  Widget _iconGroup() => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final (icon, label) in _icons)
          _ToolButton(
            label: label,
            selected: _icon == icon,
            onPressed: () => setState(() => _icon = icon),
            child: Text(icon, style: const TextStyle(fontSize: 22)),
          ),
      ],
    ),
  );

  Widget _selectionGroup() {
    final selected = _selectedId != null;
    return _group([
      TextButton.icon(
        onPressed: selected ? _deleteSelected : null,
        icon: const Icon(Icons.delete_outline_rounded),
        label: Text(selected ? 'Xoá phần tử đã chọn' : 'Chưa chọn phần tử'),
      ),
    ]);
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final moving = _moveCurrent;
        return Container(
          key: const ValueKey('whiteboard-canvas'),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: WebTuiColors.border),
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            // Chiếm cử chỉ ngay khi chạm để kéo vẽ không bị bottom sheet hiểu
            // nhầm là vuốt đóng bảng.
            child: RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(EagerGestureRecognizer.new, (_) {}),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _onPointerDown(event, size),
                onPointerMove: (event) => _onPointerMove(event, size),
                onPointerUp: (event) => _onPointerUp(event, size),
                onPointerCancel: (event) =>
                    _onPointerUp(event, size, cancelled: true),
                child: Semantics(
                  label: 'Khung vẽ bảng trắng',
                  child: CustomPaint(
                    size: size,
                    painter: WhiteboardPainter(
                      document: moving == null
                          ? _document
                          : _document.replaceElement(moving),
                      textStyle:
                          Theme.of(context).textTheme.bodyMedium ??
                          const TextStyle(),
                      draftStroke: _draftStroke,
                      draftElement: _draftElement,
                      selectedId: _selectedId,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    if (_saveError != null && _pending.isNotEmpty && !_saving) {
      // Lưu hỏng: thay chữ hướng dẫn bằng trạng thái lỗi để người dùng thấy.
      return Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: WebTuiColors.danger,
          ),
          const SizedBox(width: WebTuiSpacing.xs),
          const Expanded(
            child: Text(
              'Chưa lưu được',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: WebTuiColors.danger, fontSize: 12),
            ),
          ),
          TextButton(onPressed: _retrySave, child: const Text('Lưu lại')),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            _tool.hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WebTuiColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: WebTuiSpacing.sm),
        Text(
          _saving
              ? 'Đang lưu…'
              : _hasUnsaved
              ? 'Chờ lưu…'
              : 'Đã lưu',
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Nút công cụ vuông 44×44, có tooltip / nhãn đọc màn hình tiếng Việt.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final Widget? child;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: Material(
          color: selected ? WebTuiColors.primarySoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            side: selected
                ? const BorderSide(color: WebTuiColors.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WebTuiRadii.md),
            ),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Opacity(
                  opacity: enabled ? 1 : 0.38,
                  child:
                      child ??
                      Icon(
                        icon,
                        size: 22,
                        color: selected
                            ? WebTuiColors.primary
                            : WebTuiColors.textSecondary,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog();

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm chữ'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nội dung ghi chú'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Thêm')),
      ],
    );
  }
}

/// Vẽ bảng trắng theo đơn vị khung 800×420, co giãn theo kích thước thật.
class WhiteboardPainter extends CustomPainter {
  const WhiteboardPainter({
    required this.document,
    required this.textStyle,
    this.draftStroke,
    this.draftElement,
    this.selectedId,
  });

  final WhiteboardDocument document;
  final TextStyle textStyle;
  final WhiteboardStroke? draftStroke;
  final WhiteboardElement? draftElement;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grid = Paint()..color = const Color(0xFFE8EDF5);
    for (double x = 0; x < size.width; x += 24) {
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1, grid);
      }
    }
    if (size.width <= 0 || size.height <= 0) return;
    final scale = size.width / whiteboardWidth;
    canvas
      ..save()
      ..scale(scale);
    for (final stroke in document.strokes) {
      _paintStroke(canvas, stroke);
    }
    if (draftStroke case final stroke?) _paintStroke(canvas, stroke);
    for (final element in document.elements) {
      _paintElement(canvas, element);
    }
    if (draftElement case final element?) _paintElement(canvas, element);
    final selected = selectedId == null
        ? null
        : document.elementById(selectedId!);
    if (selected != null) _paintSelection(canvas, selected, scale);
    canvas.restore();
  }

  void _paintStroke(Canvas canvas, WhiteboardStroke stroke) {
    final paint = _linePaint(stroke.color, stroke.width);
    final first = stroke.points.first;
    if (stroke.points.length == 1) {
      canvas.drawCircle(
        Offset(first.x, first.y),
        stroke.width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(first.x, first.y);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(path, paint);
  }

  void _paintElement(Canvas canvas, WhiteboardElement element) {
    switch (element) {
      case WhiteboardShape():
        final rect = Rect.fromLTWH(element.x, element.y, element.w, element.h);
        final paint = _linePaint(element.color, element.width);
        if (element.kind == WhiteboardShapeKind.rect) {
          canvas.drawRect(rect, paint);
        } else {
          canvas.drawOval(rect, paint);
        }
      case WhiteboardArrow():
        _paintArrow(canvas, element);
      case WhiteboardText():
        final painter = TextPainter(
          text: TextSpan(
            text: element.text,
            style: textStyle.copyWith(
              color: parseWhiteboardColor(element.color),
              fontSize: element.size,
              fontWeight: FontWeight.w600,
              height: whiteboardTextLineHeight,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(element.x, element.y));
        painter.dispose();
      case WhiteboardIcon():
        final painter = TextPainter(
          text: TextSpan(
            text: element.icon,
            style: textStyle.copyWith(
              color: WebTuiColors.textPrimary,
              fontSize: element.size * 0.8,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(element.x - painter.width / 2, element.y - painter.height / 2),
        );
        painter.dispose();
    }
  }

  /// Giống web: thân dừng ở giữa đầu tam giác, mũi nhọn nằm đúng (x2, y2).
  void _paintArrow(Canvas canvas, WhiteboardArrow arrow) {
    final paint = _linePaint(arrow.color, arrow.width);
    final length = arrow.length;
    if (length == 0) {
      canvas.drawCircle(
        Offset(arrow.x1, arrow.y1),
        arrow.width / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final head = whiteboardArrowHeadLength(arrow.width);
    final ux = (arrow.x2 - arrow.x1) / length;
    final uy = (arrow.y2 - arrow.y1) / length;
    canvas.drawLine(
      Offset(arrow.x1, arrow.y1),
      Offset(arrow.x2 - ux * head / 2, arrow.y2 - uy * head / 2),
      paint,
    );
    final baseX = arrow.x2 - ux * head;
    final baseY = arrow.y2 - uy * head;
    final half = head * 0.45;
    canvas.drawPath(
      Path()
        ..moveTo(arrow.x2, arrow.y2)
        ..lineTo(baseX - uy * half, baseY + ux * half)
        ..lineTo(baseX + uy * half, baseY - ux * half)
        ..close(),
      Paint()
        ..color = parseWhiteboardColor(arrow.color)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  void _paintSelection(Canvas canvas, WhiteboardElement element, double scale) {
    final box = element.bounds;
    final pad = 6 / scale;
    final rect = RRect.fromLTRBR(
      box.left - pad,
      box.top - pad,
      box.right + pad,
      box.bottom + pad,
      Radius.circular(4 / scale),
    );
    canvas
      ..drawRRect(
        rect,
        Paint()..color = WebTuiColors.primary.withValues(alpha: 0.08),
      )
      ..drawRRect(
        rect,
        Paint()
          ..color = WebTuiColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale,
      );
  }

  Paint _linePaint(String color, double width) => Paint()
    ..color = parseWhiteboardColor(color)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.draftStroke != draftStroke ||
      oldDelegate.draftElement != draftElement ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.textStyle != textStyle;
}

/// Màu CSS `#rgb`, `#rrggbb`, `#rrggbbaa` → `Color`; sai thì dùng màu mặc định.
Color parseWhiteboardColor(String value) {
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  final rgb = hex.length >= 6
      ? int.tryParse(hex.substring(0, 6), radix: 16)
      : null;
  final alpha = hex.length == 8
      ? int.tryParse(hex.substring(6), radix: 16)
      : hex.length == 6
      ? 0xFF
      : null;
  if (rgb == null || alpha == null) return const Color(0xFF111827);
  return Color((alpha << 24) | rgb);
}
