import '../data/ide_rpc_client.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_more_time.dart';
import '../domain/ide_talk_models.dart';
import 'ide_download_service.dart' show ideSafeFileName;

/// Giới hạn tải lên theo hợp đồng (C2): ảnh ≤ 20 MB (≤ 8), tệp ≤ 50 MB (≤ 10).
const ideTalkMaxImages = 8;
const ideTalkMaxFiles = 10;
const ideTalkMaxImageBytes = 20 * 1024 * 1024;
const ideTalkMaxFileBytes = 50 * 1024 * 1024;
const ideTalkMaxText = 200000;

String _s(Object? v) => v is String ? v : '';

/// Gọi các `op` `talk.*`. Thao tác ★ (`talk.share`) do [IdeRpcClient] tự xử lý
/// `need_step`. App không bao giờ gửi đường dẫn: tệp / ảnh gửi bằng `ref`.
class IdeTalkService {
  IdeTalkService(this._rpc);

  final IdeRpcClient _rpc;

  Future<IdeTalkModels> models({bool refresh = false}) async =>
      IdeTalkModels.parse(
        await _rpc.call('talk.models', {if (refresh) 'refresh': true}),
      );

  Future<List<IdeTalkSummary>> list() async =>
      IdeTalkSummary.parseList(await _rpc.call('talk.list', const {}));

  /// Tải cuộc một lần (dự phòng khi stream chưa mở).
  Future<IdeTalkConversation> get(String id) async {
    final c = IdeTalkConversation.tryParse(
      await _rpc.call('talk.get', {'id': id}),
    );
    if (c == null) throw const IdeNotFound('Không tìm thấy cuộc chat này.');
    return c;
  }

  /// [id] = `new` để tạo cuộc mới. `images` / `files` là các `ref` đã cấp.
  Future<IdeTalkSendResult> send({
    required String id,
    required String text,
    String? model,
    String? effort,
    bool queue = false,
    List<String> images = const [],
    List<String> files = const [],
  }) async {
    if (id != 'new' && !ideTalkIdOk(id)) {
      throw const IdeBadRequest('Mã cuộc chat không hợp lệ.');
    }
    final data = await _rpc.call('talk.send', {
      'id': id,
      'text': text,
      if (model != null && model.isNotEmpty) 'model': model,
      if (effort != null && effort.isNotEmpty) 'effort': effort,
      if (queue) 'queue': true,
      if (images.isNotEmpty) 'images': images,
      if (files.isNotEmpty) 'files': files,
    }, timeout: const Duration(seconds: 60));
    final m = data is Map ? data : const <Object?, Object?>{};
    final rid = _s(m['id']);
    if (!ideTalkIdOk(rid)) throw const IdeError('bad_response', 'Phản hồi lạ.');
    return IdeTalkSendResult(
      id: rid,
      queued: m['queued'] != null && m['queued'] != false,
      note: _s(m['note']),
    );
  }

  Future<void> stop(String id) => _rpc.call('talk.stop', {'id': id});

  Future<void> queueRun(String id) => _rpc.call('talk.queue_run', {'id': id});

  Future<void> unqueue(String id, String item) =>
      _rpc.call('talk.unqueue', {'id': id, 'item': item});

  /// Tạo link chia sẻ (★). Trả `link` và `url` (có thể `null`).
  Future<({String link, String? url})> share(String id) async {
    final d = await _rpc.call('talk.share', {'id': id});
    final m = d is Map ? d : const <Object?, Object?>{};
    final url = m['url'];
    return (
      link: _s(m['link']),
      url: url is String && url.isNotEmpty ? url : null,
    );
  }

  /// Dừng chia sẻ (không ★).
  Future<void> stopShare(String id) =>
      _rpc.call('talk.share', {'id': id, 'stop': true});

  Future<IdeTalkAgentSaved> agentSave({
    required String id,
    String? name,
    String? task,
    String? schedule,
    String? scheduleLabel,
    String? model,
    String? effort,
    bool? enabled,
  }) async {
    final d = await _rpc.call('talk.agent_save', {
      'id': id,
      'name': ?name,
      'task': ?task,
      'schedule': ?schedule,
      'scheduleLabel': ?scheduleLabel,
      if (model != null && model.isNotEmpty) 'model': model,
      if (effort != null && effort.isNotEmpty) 'effort': effort,
      'enabled': ?enabled,
    });
    final m = d is Map ? d : const <Object?, Object?>{};
    return IdeTalkAgentSaved(
      id: _s(m['id']),
      scheduled: m['scheduled'] == true,
      warning: _s(m['warning']),
      next: _s(m['next']),
      nextAt: ideTimeFromSeconds(m['next_at']),
    );
  }

  /// Chạy agent ngay; trả mã cuộc mở ra (`id`).
  Future<String> agentRun(String id) async {
    final d = await _rpc.call('talk.agent_run', {'id': id});
    return d is Map ? _s(d['id']) : '';
  }

  Future<IdeTalkAgentDraft> agentDraft(String text, {String? model}) async {
    final d = await _rpc.call('talk.agent_draft', {
      'text': text,
      if (model != null && model.isNotEmpty) 'model': model,
    }, timeout: const Duration(seconds: 90));
    final m = d is Map ? d : const <Object?, Object?>{};
    return IdeTalkAgentDraft(
      name: _s(m['name']),
      task: _s(m['task']),
      schedule: _s(m['schedule']),
      scheduleLabel: _s(m['scheduleLabel']),
    );
  }

  /// Lấy đường dẫn tệp trong cuộc để tải bằng `files.get`.
  Future<({String path, int size})> file(String id, String name) async {
    if (!ideTalkFileNameOk(name)) {
      throw const IdeBadRequest('Tên tệp không hợp lệ.');
    }
    final d = await _rpc.call('talk.file', {'id': id, 'name': name});
    final m = d is Map ? d : const <Object?, Object?>{};
    final path = _s(m['path']);
    if (!ideTalkPathSafe(path)) throw const IdeNotFound();
    return (path: path, size: ideSafeInt(m['size']));
  }

  /// Xin chỗ (`talk.upload_slot`), tải lên bằng `files.put`, trả `ref` cho
  /// `talk.send`. Không bao giờ gửi đường dẫn trong `talk.send`.
  Future<String> uploadAttachment({
    required bool image,
    required String name,
    required String mime,
    required int size,
    required Stream<List<int>> Function() read,
  }) async {
    final limit = image ? ideTalkMaxImageBytes : ideTalkMaxFileBytes;
    if (size > limit) {
      throw IdeTooLarge(image ? 'Ảnh quá 20 MB.' : 'Tệp quá 50 MB.');
    }
    final safe = ideSafeFileName(name, fallback: image ? 'anh.jpg' : 'tep');
    final slot = await _rpc.call('talk.upload_slot', {
      'kind': image ? 'image' : 'file',
      'name': safe.length > 120 ? safe.substring(0, 120) : safe,
    });
    final m = slot is Map ? slot : const <Object?, Object?>{};
    final ref = _s(m['ref']);
    final path = _s(m['path']);
    final cut = path.lastIndexOf('/');
    if (ref.isEmpty ||
        !ideTalkSlotPathOk(path) ||
        cut <= 0 ||
        cut == path.length - 1) {
      throw const IdeError('bad_response', 'Không xin được chỗ tải lên.');
    }
    await _rpc.upload('files.put', {
      'dir': path.substring(0, cut),
      'name': path.substring(cut + 1),
      'size': size,
      'mime': mime,
    }, read());
    return ref;
  }
}

/// Ô tải lên hợp lệ: `<thư mục>/.cache/vpsttt-ide/<người dùng chat>/(anh|tep)/<tên>`
/// (mỗi người dùng chat một thư mục riêng, theo hợp đồng GĐ4).
final _slotPath = RegExp(
  r'^/[^\x00]+/\.cache/vpsttt-ide/[A-Za-z0-9_-]+/(anh|tep)/[^/]+$',
);

/// Đường dẫn ô tải lên IDE trả về có dùng được không.
bool ideTalkSlotPathOk(String path) =>
    _slotPath.hasMatch(path) && ideTalkPathSafe(path);

/// Đường dẫn IDE trả về chỉ nhận khi tuyệt đối, không có đoạn `..`, không có
/// ký tự điều khiển (chống thoát thư mục / chèn lệnh).
bool ideTalkPathSafe(String path) {
  if (!path.startsWith('/') || path.length > 4096) return false;
  if (RegExp(r'[\u0000-\u001f\u007f-\u009f]').hasMatch(path)) return false;
  return !path.split('/').contains('..');
}
