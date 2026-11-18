import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/recent_download_failures.dart';
import 'package:webtui_chat/core/network/redirect_safe_file_downloader.dart';

void main() {
  test('403 / 404 / 410 được nhớ 10 phút rồi cho thử lại', () {
    var now = DateTime(2026, 11, 18, 9);
    final failures = RecentDownloadFailures(now: () => now);
    for (final status in const [403, 404, 410]) {
      final key = 'avatar-$status';
      expect(
        failures.record(
          key,
          RedirectSafeDownloadException('denied', statusCode: status),
        ),
        isTrue,
      );
      expect(failures.isBlocked(key), isTrue);
    }

    now = now.add(const Duration(minutes: 9));
    expect(failures.isBlocked('avatar-403'), isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(failures.isBlocked('avatar-403'), isFalse);
  });

  test('lỗi mạng, 401 (token hết hạn), 5xx không bị nhớ', () {
    final failures = RecentDownloadFailures();
    final errors = <Object>[
      const RedirectSafeDownloadException('expired', statusCode: 401),
      const RedirectSafeDownloadException('busy', statusCode: 503),
      const RedirectSafeDownloadException('download failed'),
      const SocketException('offline'),
    ];
    for (final error in errors) {
      expect(failures.record('uri', error), isFalse);
      expect(failures.isBlocked('uri'), isFalse);
    }
  });

  test('giữ tối đa maxEntries địa chỉ, bỏ địa chỉ cũ nhất', () {
    final failures = RecentDownloadFailures(maxEntries: 2);
    const denied = RedirectSafeDownloadException('denied', statusCode: 403);
    failures
      ..record('a', denied)
      ..record('b', denied)
      ..record('c', denied);
    expect(failures.isBlocked('a'), isFalse);
    expect(failures.isBlocked('b'), isTrue);
    expect(failures.isBlocked('c'), isTrue);
  });
}
