import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thư mục con trong thư mục tạm của app mà plugin chia sẻ (bản trong
/// `third_party/receive_sharing_intent`) chép tệp nhận được vào. Phải khớp
/// `SharedFileNames.SHARE_CACHE_DIR` phía Android.
const String sharedIntentCacheDirName = 'receive_sharing_intent';

enum SharedFileRejection {
  empty,
  notAbsolute,
  parentSegment,
  missing,
  notRegularFile,
  emptyFile,
  outsideShareCache,
  privateLocation,
}

final class SharedFileCheck {
  const SharedFileCheck.accepted({required String path, required int byteSize})
    : _path = path,
      _byteSize = byteSize,
      rejection = null;

  const SharedFileCheck.rejected(SharedFileRejection this.rejection)
    : _path = null,
      _byteSize = 0;

  final String? _path;
  final int _byteSize;
  final SharedFileRejection? rejection;

  bool get isAccepted => rejection == null;

  /// Đường dẫn đã resolve symlink; chỉ có khi [isAccepted].
  String get path => _path!;

  int get byteSize => _byteSize;
}

/// Chỉ nhận tệp trong thư mục chia sẻ tạm (sau khi resolve symlink) và từ
/// chối mọi tệp thuộc thư mục dữ liệu riêng của app.
final class SharedFilePathGuard {
  const SharedFilePathGuard({
    required this.allowedRoots,
    this.privateRoots = const [],
  });

  /// Thư mục được nhận (thư mục chia sẻ tạm). Rỗng thì không nhận tệp nào.
  final List<String> allowedRoots;

  /// Thư mục dữ liệu riêng của app, luôn bị từ chối.
  final List<String> privateRoots;

  Future<SharedFileCheck> check(String rawPath) async {
    final raw = rawPath.trim();
    if (raw.isEmpty) {
      return const SharedFileCheck.rejected(SharedFileRejection.empty);
    }
    if (!p.isAbsolute(raw)) {
      return const SharedFileCheck.rejected(SharedFileRejection.notAbsolute);
    }
    final segments = raw.replaceAll('\\', '/').split('/');
    if (segments.any((segment) => segment.trim() == '..')) {
      return const SharedFileCheck.rejected(SharedFileRejection.parentSegment);
    }

    final String resolved;
    try {
      resolved = p.normalize(await File(raw).resolveSymbolicLinks());
    } on FileSystemException {
      return const SharedFileCheck.rejected(SharedFileRejection.missing);
    }

    for (final root in privateRoots) {
      final resolvedRoot = await _resolveRoot(root);
      if (_isSameOrWithin(resolvedRoot, resolved)) {
        return const SharedFileCheck.rejected(
          SharedFileRejection.privateLocation,
        );
      }
    }

    var insideShareCache = false;
    for (final root in allowedRoots) {
      final resolvedRoot = await _resolveRoot(root);
      if (p.isWithin(resolvedRoot, resolved)) {
        insideShareCache = true;
        break;
      }
    }
    if (!insideShareCache) {
      return const SharedFileCheck.rejected(
        SharedFileRejection.outsideShareCache,
      );
    }

    final stat = await File(resolved).stat();
    if (stat.type != FileSystemEntityType.file) {
      return const SharedFileCheck.rejected(SharedFileRejection.notRegularFile);
    }
    if (stat.size <= 0) {
      return const SharedFileCheck.rejected(SharedFileRejection.emptyFile);
    }
    return SharedFileCheck.accepted(path: resolved, byteSize: stat.size);
  }

  static bool _isSameOrWithin(String root, String path) =>
      p.equals(root, path) || p.isWithin(root, path);

  static Future<String> _resolveRoot(String root) async {
    final normalized = p.normalize(p.absolute(root));
    try {
      return p.normalize(await Directory(normalized).resolveSymbolicLinks());
    } on FileSystemException {
      return normalized;
    }
  }
}

/// Guard theo nền tảng đang chạy. Android: chỉ nhận thư mục chia sẻ tạm mà
/// plugin chép vào. Nền tảng khác chưa có luồng nhận tệp chia sẻ nên không
/// nhận tệp nào.
Future<SharedFilePathGuard> createPlatformSharedFilePathGuard() async {
  if (!Platform.isAndroid) {
    return const SharedFilePathGuard(allowedRoots: []);
  }
  final temporary = await getTemporaryDirectory();
  final support = await getApplicationSupportDirectory();
  final documents = await getApplicationDocumentsDirectory();
  final appDataDir = p.dirname(support.path);
  return SharedFilePathGuard(
    allowedRoots: [p.join(temporary.path, sharedIntentCacheDirName)],
    privateRoots: [
      support.path,
      documents.path,
      p.join(appDataDir, 'databases'),
      p.join(appDataDir, 'shared_prefs'),
      p.join(appDataDir, 'no_backup'),
    ],
  );
}
