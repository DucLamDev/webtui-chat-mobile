import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';
import '../data/ide_rpc_client.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_media_models.dart';

/// Gọi `appscreen.*` và `video.*` (Phụ lục C3) và trả mô hình đã kiểm.
/// Đường dẫn máy chủ không bao giờ đi qua đây: app chỉ gửi tên dự án.
class IdeMediaService {
  IdeMediaService(this._rpc);

  final IdeRpcClient _rpc;

  // --- Màn hình app
  Future<IdeAppCheck> appCheck() async =>
      IdeAppCheck.parse(await _rpc.call('appscreen.check', const {}));

  Future<IdeAppStatus> appStatus() async =>
      IdeAppStatus.parse(await _rpc.call('appscreen.status', const {}));

  /// Trả mã việc nền (`jobs.tail`).
  Future<String> appRun(String project, {String? device, bool? dark}) async {
    final data = await _rpc.call('appscreen.run', {
      'project': project,
      if (device != null && device.isNotEmpty) 'device': device,
      'dark': ?dark,
    });
    final job = data is Map ? data['job'] : null;
    if (job is! String || job.isEmpty) {
      throw const IdeError('ide_error', 'IDE không trả mã việc.');
    }
    return job;
  }

  Future<void> appStop(String project) =>
      _rpc.call('appscreen.stop', {'project': project});

  /// `null` khi khung hỏng / vô lý (người gọi giữ khung cũ).
  Future<IdeAppFrame?> appFrame(String project) async => IdeAppFrame.tryParse(
    await _rpc.call('appscreen.frame', {'project': project}),
  );

  // --- Studio video
  Future<List<IdeVideoRow>> videoList(String project) async =>
      ideParseVideoList(await _rpc.call('video.list', {'project': project}));

  /// `video.list {sync:true}`: trả mã việc; kết quả việc có dạng như `videoList`.
  Future<String> videoSync(String project) async {
    final data = await _rpc.call('video.list', {
      'project': project,
      'sync': true,
    });
    final job = data is Map ? data['job'] : null;
    if (job is! String || job.isEmpty) {
      throw const IdeError('ide_error', 'IDE không trả mã việc.');
    }
    return job;
  }

  Future<IdeVideoDetail> videoGet(String project, String slug) async {
    final d = IdeVideoDetail.tryParse(
      await _rpc.call('video.get', {'project': project, 'slug': slug}),
    );
    if (d == null) throw const IdeNotFound('Không tìm thấy video này.');
    return d;
  }
}

final ideMediaServiceProvider = Provider<IdeMediaService>(
  (ref) => IdeMediaService(ref.watch(ideRpcClientProvider)),
);

/// Hỏi lặp theo chu kỳ: tối đa 1 lượt đang bay, bỏ qua nhịp khi [shouldRun]
/// trả `false` (nền / màn bị che / đã tắt), [poke] chạy ngay một lượt.
class IdePoller {
  IdePoller({
    required this.interval,
    required this.shouldRun,
    required this.task,
  });

  final Duration interval;
  final bool Function() shouldRun;
  final Future<void> Function() task;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  bool get running => _timer != null;

  void start() {
    if (_disposed) return;
    _timer ??= Timer.periodic(interval, (_) => unawaited(poke()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poke() async {
    if (_disposed || _busy || !shouldRun()) return;
    _busy = true;
    try {
      await task();
    } on Object {
      // task tự xử lý lỗi; không để lỗi lạ làm vỡ vòng hỏi.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    stop();
  }
}
