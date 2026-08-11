import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_android_elf_alignment.dart <release.apk>',
    );
    exitCode = 64;
    return;
  }

  final apk = File(arguments.single);
  if (!apk.existsSync() || apk.statSync().type != FileSystemEntityType.file) {
    stderr.writeln('APK not found: ${apk.path}');
    exitCode = 66;
    return;
  }

  final ndk = _findNdk();
  if (ndk == null) {
    stderr.writeln(
      'Android NDK not found. Set ANDROID_NDK_ROOT or ANDROID_HOME.',
    );
    exitCode = 69;
    return;
  }
  final objdump = _findExecutable(
    ndk,
    Platform.isWindows ? 'llvm-objdump.exe' : 'llvm-objdump',
  );
  if (objdump == null) {
    stderr.writeln('llvm-objdump not found below ${ndk.path}.');
    exitCode = 69;
    return;
  }

  final temporary = await Directory.systemTemp.createTemp('webtui-elf-check-');
  try {
    final extraction = await Process.run('jar', [
      'xf',
      apk.absolute.path,
    ], workingDirectory: temporary.path);
    if (extraction.exitCode != 0) {
      stderr.writeln('Could not extract APK with jar: ${extraction.stderr}');
      exitCode = extraction.exitCode;
      return;
    }

    final libraries = <File>[];
    for (final abi in const ['arm64-v8a', 'x86_64']) {
      final directory = Directory(
        '${temporary.path}${Platform.pathSeparator}lib${Platform.pathSeparator}$abi',
      );
      if (!directory.existsSync()) continue;
      libraries.addAll(
        directory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.so'),
        ),
      );
    }
    if (libraries.isEmpty) {
      stderr.writeln('No 64-bit native libraries found in ${apk.path}.');
      exitCode = 1;
      return;
    }

    final failures = <String>[];
    for (final library in libraries) {
      final result = await Process.run(objdump.path, ['-p', library.path]);
      if (result.exitCode != 0) {
        failures.add('${library.uri.pathSegments.last}: llvm-objdump failed');
        continue;
      }
      final exponents =
          RegExp(r'^\s*LOAD\s+.*align 2\*\*(\d+)\s*$', multiLine: true)
              .allMatches('${result.stdout}')
              .map((match) => int.parse(match.group(1)!))
              .toList();
      if (exponents.isEmpty) {
        failures.add(
          '${library.uri.pathSegments.last}: no ELF LOAD segment found',
        );
      } else if (exponents.any((exponent) => exponent < 14)) {
        failures.add(
          '${library.uri.pathSegments.last}: LOAD alignment below 2**14 '
          '(${exponents.join(', ')})',
        );
      }
    }

    if (failures.isNotEmpty) {
      stderr.writeln('Android 16 KB ELF alignment check failed:');
      for (final failure in failures) {
        stderr.writeln('- $failure');
      }
      exitCode = 1;
      return;
    }

    stdout.writeln(
      'Verified 16 KB ELF alignment for ${libraries.length} 64-bit libraries.',
    );
  } finally {
    if (temporary.existsSync()) {
      await temporary.delete(recursive: true);
    }
  }
}

Directory? _findNdk() {
  for (final name in const ['ANDROID_NDK_ROOT', 'ANDROID_NDK_HOME']) {
    final value = Platform.environment[name]?.trim() ?? '';
    if (value.isNotEmpty) {
      final candidate = Directory(value);
      if (candidate.existsSync()) return candidate;
    }
  }
  final sdkRoot =
      Platform.environment['ANDROID_HOME']?.trim().isNotEmpty == true
      ? Platform.environment['ANDROID_HOME']!.trim()
      : Platform.environment['ANDROID_SDK_ROOT']?.trim() ?? '';
  if (sdkRoot.isEmpty) return null;
  final ndkParent = Directory('$sdkRoot${Platform.pathSeparator}ndk');
  if (!ndkParent.existsSync()) return null;
  final candidates = ndkParent.listSync().whereType<Directory>().toList()
    ..sort(
      (left, right) =>
          _versionKey(right.path).compareTo(_versionKey(left.path)),
    );
  return candidates.isEmpty ? null : candidates.first;
}

File? _findExecutable(Directory root, String name) {
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.uri.pathSegments.last == name) return entity;
  }
  return null;
}

String _versionKey(String path) {
  final name = path.split(Platform.pathSeparator).last;
  return name
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .map((part) => part.toString().padLeft(10, '0'))
      .join();
}
