import 'dart:io';

// Gói thay thế của bản Linux chạy thử được nạp qua dependency_overrides.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_linux/flutter_secure_storage_linux.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewDir = 'tool/linux_preview';
const _otherPlatforms = ['android:', 'ios:', 'macos:', 'windows:', 'web:'];

/// Đọc các mục con của khối `dependency_overrides:` trong pubspec.yaml.
Map<String, String> _dependencyOverrides(String pubspec) {
  final lines = pubspec.split('\n');
  final start = lines.indexOf('dependency_overrides:');
  if (start < 0) {
    return const {};
  }
  final overrides = <String, String>{};
  String? current;
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) {
      continue;
    }
    if (!line.startsWith(' ')) {
      break;
    }
    final entry = RegExp(r'^  ([a-z0-9_]+):\s*(.*)$').firstMatch(line);
    if (entry != null) {
      current = entry.group(1);
      overrides[current!] = entry.group(2)!;
      continue;
    }
    final path = RegExp(r'^    path:\s*(\S+)$').firstMatch(line);
    if (path != null && current != null) {
      overrides[current] = path.group(1)!;
    }
  }
  return overrides;
}

void main() {
  test('dependency_overrides chỉ thay phần Linux bằng gói chạy thử', () {
    final overrides = _dependencyOverrides(
      File('pubspec.yaml').readAsStringSync(),
    );

    expect(overrides, isNotEmpty);
    for (final entry in overrides.entries) {
      expect(
        entry.key,
        endsWith('_linux'),
        reason: 'không được ghi đè gói dùng cho Android / iOS',
      );
      expect(entry.value, '$_previewDir/${entry.key}');
    }
  });

  test('có bản Linux cho vpsttt-app và không dựng gói Linux bị thay', () {
    final overrides = _dependencyOverrides(
      File('pubspec.yaml').readAsStringSync(),
    );

    expect(
      File('linux/CMakeLists.txt').existsSync(),
      isTrue,
      reason: 'thiếu linux/ thì báo "No Linux desktop project configured"',
    );
    final plugins = File(
      'linux/flutter/generated_plugins.cmake',
    ).readAsStringSync();
    for (final name in overrides.keys) {
      expect(
        plugins,
        isNot(contains(name)),
        reason: '$name thật cần thư viện mà máy dev không có',
      );
    }
  });

  test('gói chạy thử chỉ khai nền tảng Linux', () {
    final packages = Directory(
      _previewDir,
    ).listSync().whereType<Directory>().toList();

    expect(packages, isNotEmpty);
    for (final package in packages) {
      final pubspec = File('${package.path}/pubspec.yaml').readAsStringSync();
      final platforms = pubspec.substring(pubspec.indexOf('platforms:'));

      expect(pubspec, contains('publish_to: none'));
      expect(platforms, contains('linux:'));
      for (final platform in _otherPlatforms) {
        expect(
          platforms,
          isNot(contains(platform)),
          reason: '${package.path} không được thay gói của $platform',
        );
      }
    }
  });

  test('kho khoá chạy thử giữ giá trị trong bộ nhớ', () async {
    FlutterSecureStorageLinuxPreview.registerWith();
    final storage = FlutterSecureStoragePlatform.instance;
    const options = <String, String>{};

    expect(storage, isA<FlutterSecureStorageLinuxPreview>());
    expect(await storage.read(key: 'token', options: options), isNull);

    await storage.write(key: 'token', value: 'a', options: options);
    await storage.write(key: 'server', value: 'b', options: options);
    expect(await storage.read(key: 'token', options: options), 'a');
    expect(await storage.containsKey(key: 'token', options: options), isTrue);
    expect(await storage.readAll(options: options), {
      'token': 'a',
      'server': 'b',
    });

    await storage.delete(key: 'token', options: options);
    expect(await storage.containsKey(key: 'token', options: options), isFalse);

    await storage.deleteAll(options: options);
    expect(await storage.readAll(options: options), isEmpty);

    FlutterSecureStorageLinuxPreview.registerWith();
    await storage.write(key: 'token', value: 'a', options: options);
    expect(
      await FlutterSecureStoragePlatform.instance.read(
        key: 'token',
        options: options,
      ),
      isNull,
      reason: 'khởi động lại app thì kho khoá chạy thử phải trống',
    );
  });
}
