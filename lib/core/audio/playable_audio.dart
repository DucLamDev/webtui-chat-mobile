import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'opus_container.dart';
import 'opus_to_wav.dart';

/// iPhone / iPad / Mac: AVPlayer không đọc được WebM / Ogg / Opus.
bool platformNeedsOpusTranscode([TargetPlatform? platform]) {
  final p = platform ?? defaultTargetPlatform;
  return p == TargetPlatform.iOS || p == TargetPlatform.macOS;
}

/// Ghi âm này cần đổi sang WAV trước khi phát trên máy hiện tại không
/// (theo tên / mime; byte đầu được kiểm lại khi đổi).
bool audioNeedsTranscode({
  String? name,
  String? mimeType,
  TargetPlatform? platform,
}) {
  return platformNeedsOpusTranscode(platform) &&
      looksLikeOpusContainer(name: name, mimeType: mimeType);
}

final _inFlight = <String, Future<File>>{};

String _safeKey(String key) {
  final cleaned = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final hash = key.hashCode.toUnsigned(32).toRadixString(16);
  final head = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  return '$head-$hash';
}

/// Trả tệp phát được cho [source]. WebM / Ogg (nhận diện bằng byte đầu) được
/// giải mã thành WAV và lưu trong bộ nhớ đệm theo [cacheKey] (dùng lại lần
/// sau); các định dạng khác trả nguyên [source]. Ném lỗi nếu giải mã hỏng.
Future<File> playableAudioFile({
  required File source,
  required String cacheKey,
  Directory? cacheDirectory,
}) {
  final inFlightKey = '${cacheDirectory?.path ?? ''}|$cacheKey';
  return _inFlight[inFlightKey] ??= _playable(source, cacheKey, cacheDirectory)
      .whenComplete(() {
        _inFlight.remove(inFlightKey);
      });
}

Future<File> _playable(
  File source,
  String cacheKey,
  Directory? cacheDirectory,
) async {
  final raf = await source.open();
  final Uint8List head;
  try {
    head = await raf.read(4);
  } finally {
    await raf.close();
  }
  if (sniffAudioContainer(head) == AudioContainer.other) return source;

  final base = cacheDirectory ?? await getTemporaryDirectory();
  final dir = cacheDirectory != null
      ? base
      : Directory('${base.path}${Platform.pathSeparator}playable_audio');
  await dir.create(recursive: true);
  final target = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_safeKey(cacheKey)}.wav',
  );
  if (await target.exists() && await target.length() > 44) return target;

  final partial = File('${target.path}.part');
  try {
    await opusFileToWavFile(source, partial);
    await partial.rename(target.path);
  } on Object {
    if (await partial.exists()) await partial.delete();
    rethrow;
  }
  return target;
}
