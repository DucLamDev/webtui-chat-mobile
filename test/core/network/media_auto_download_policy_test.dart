import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/connectivity_network_type_reader.dart';
import 'package:webtui_chat/core/network/media_auto_download_policy.dart';

final class _FakeReader implements NetworkTypeReader {
  _FakeReader(this.type, {this.fail = false});

  final MediaNetworkType type;
  final bool fail;
  int calls = 0;

  @override
  Future<MediaNetworkType> current() async {
    calls += 1;
    if (fail) throw StateError('không đọc được mạng');
    return type;
  }
}

void main() {
  const mb = 1024 * 1024;

  test(
    'tự tải ảnh: chỉ chặn khi tắt công tắc và đang dùng dữ liệu di động',
    () {
      for (final network in MediaNetworkType.values) {
        expect(
          shouldAutoDownloadImage(allowOnCellular: true, network: network),
          isTrue,
          reason: '$network',
        );
        expect(
          shouldAutoDownloadImage(allowOnCellular: false, network: network),
          network != MediaNetworkType.cellular,
          reason: '$network',
        );
      }
    },
  );

  group('tải ngầm video phát dần vào kho', () {
    bool decide({
      int byteSize = 10 * mb,
      bool previewOnly = false,
      bool allowOnCellular = false,
      MediaNetworkType network = MediaNetworkType.wifi,
    }) => shouldBackgroundCacheVideo(
      byteSize: byteSize,
      previewOnly: previewOnly,
      allowOnCellular: allowOnCellular,
      network: network,
    );

    test('cỡ: tới 30 MB thì tải, lớn hơn / không rõ cỡ thì không', () {
      expect(decide(byteSize: 30 * mb), isTrue);
      expect(decide(byteSize: 1), isTrue);
      expect(decide(byteSize: 30 * mb + 1), isFalse);
      expect(decide(byteSize: 0), isFalse);
      expect(decide(byteSize: -1), isFalse);
    });

    test('loại mạng + công tắc: Wi-Fi luôn tải; 4G chỉ khi công tắc bật', () {
      expect(decide(network: MediaNetworkType.wifi), isTrue);
      expect(decide(network: MediaNetworkType.cellular), isFalse);
      expect(
        decide(network: MediaNetworkType.cellular, allowOnCellular: true),
        isTrue,
      );
      for (final network in [
        MediaNetworkType.other,
        MediaNetworkType.offline,
        MediaNetworkType.unknown,
      ]) {
        expect(decide(network: network), isFalse, reason: '$network');
      }
    });

    test('chỉ là khung xem trước thì không tải', () {
      expect(decide(previewOnly: true), isFalse);
      expect(decide(previewOnly: true, allowOnCellular: true), isFalse);
    });
  });

  test('công tắc bật: không cần hỏi loại mạng', () async {
    final reader = _FakeReader(MediaNetworkType.cellular);
    final policy = MediaAutoDownloadPolicy(
      allowOnCellular: true,
      networkTypeReader: reader,
    );
    expect(await policy.canAutoDownloadImage(), isTrue);
    expect(
      await policy.canBackgroundCacheVideo(byteSize: mb, previewOnly: false),
      isTrue,
    );
    expect(reader.calls, 0);
  });

  test(
    'công tắc tắt: theo loại mạng; đọc mạng lỗi thì coi như không rõ',
    () async {
      MediaAutoDownloadPolicy policy(_FakeReader reader) =>
          MediaAutoDownloadPolicy(
            allowOnCellular: false,
            networkTypeReader: reader,
          );
      final cellular = policy(_FakeReader(MediaNetworkType.cellular));
      expect(await cellular.canAutoDownloadImage(), isFalse);
      expect(
        await cellular.canBackgroundCacheVideo(
          byteSize: mb,
          previewOnly: false,
        ),
        isFalse,
      );

      final wifi = policy(_FakeReader(MediaNetworkType.wifi));
      expect(await wifi.canAutoDownloadImage(), isTrue);
      expect(
        await wifi.canBackgroundCacheVideo(byteSize: mb, previewOnly: false),
        isTrue,
      );
      // Video quá lớn: không cần hỏi mạng.
      final big = _FakeReader(MediaNetworkType.wifi);
      expect(
        await policy(
          big,
        ).canBackgroundCacheVideo(byteSize: 31 * mb, previewOnly: false),
        isFalse,
      );
      expect(big.calls, 0);

      final broken = policy(_FakeReader(MediaNetworkType.cellular, fail: true));
      expect(await broken.canAutoDownloadImage(), isTrue);
      expect(
        await broken.canBackgroundCacheVideo(byteSize: mb, previewOnly: false),
        isFalse,
      );
    },
  );

  test('đổi kết quả connectivity_plus về loại mạng', () {
    expect(
      mediaNetworkTypeFrom([ConnectivityResult.wifi]),
      MediaNetworkType.wifi,
    );
    expect(
      mediaNetworkTypeFrom([
        ConnectivityResult.mobile,
        ConnectivityResult.wifi,
      ]),
      MediaNetworkType.wifi,
    );
    expect(
      mediaNetworkTypeFrom([ConnectivityResult.ethernet]),
      MediaNetworkType.wifi,
    );
    expect(
      mediaNetworkTypeFrom([ConnectivityResult.vpn, ConnectivityResult.mobile]),
      MediaNetworkType.cellular,
    );
    expect(
      mediaNetworkTypeFrom([ConnectivityResult.none]),
      MediaNetworkType.offline,
    );
    expect(
      mediaNetworkTypeFrom([ConnectivityResult.vpn]),
      MediaNetworkType.other,
    );
    expect(mediaNetworkTypeFrom(const []), MediaNetworkType.unknown);
  });
}
