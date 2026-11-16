import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

import 'opus_container.dart';

const opusSampleRate = 48000;

/// Header WAV (PCM 16-bit little-endian) cho [dataBytes] byte dữ liệu.
Uint8List wavHeader({
  required int dataBytes,
  int sampleRate = opusSampleRate,
  int channels = 1,
}) {
  final header = ByteData(44);
  void tag(int offset, String text) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  return header.buffer.asUint8List();
}

/// Ghép PCM 16-bit xen kênh thành một tệp WAV hoàn chỉnh.
Uint8List buildWav(
  Int16List pcm, {
  int sampleRate = opusSampleRate,
  int channels = 1,
}) {
  final dataBytes = pcm.length * 2;
  final out = Uint8List(44 + dataBytes);
  out.setAll(
    0,
    wavHeader(dataBytes: dataBytes, sampleRate: sampleRate, channels: channels),
  );
  final view = ByteData.sublistView(out);
  for (var i = 0; i < pcm.length; i++) {
    view.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return out;
}

bool _opusReady = false;

// opus_dart phân tích kiểu theo web_ffi; trên máy thật đó chính là dart:ffi.
void _init(Object library) => initOpus(library as dynamic);

/// Nạp libopus: ưu tiên bản đóng gói theo ứng dụng (iOS / Android), lùi về
/// thư viện hệ thống (Linux, macOS khi chạy thử).
Future<void> ensureOpusLoaded({DynamicLibrary? library}) async {
  if (_opusReady) return;
  if (library != null) {
    _init(library);
    _opusReady = true;
    return;
  }
  Object? firstError;
  try {
    final lib = await opus_flutter.load();
    _init(lib);
    _opusReady = true;
    return;
  } on Object catch (error) {
    firstError = error;
  }
  for (final name in const [
    'libopus.so.0',
    'libopus.so',
    'libopus.dylib',
    'opus.dll',
  ]) {
    try {
      _init(DynamicLibrary.open(name));
      _opusReady = true;
      return;
    } on Object {
      continue;
    }
  }
  throw StateError('Không nạp được libopus: $firstError');
}

/// Giải mã các gói Opus thành PCM 16-bit 48 kHz, đã bỏ pre-skip.
/// Cần gọi [ensureOpusLoaded] trước.
Int16List decodeOpusPackets(OpusStream stream) {
  final channels = stream.channels;
  if (channels < 1 || channels > 2) {
    throw OpusContainerException('Số kênh $channels chưa hỗ trợ');
  }
  final decoder = SimpleOpusDecoder(
    sampleRate: opusSampleRate,
    channels: channels,
  );
  try {
    final chunks = <Int16List>[];
    var total = 0;
    for (final packet in stream.packets) {
      final pcm = decoder.decode(input: packet);
      chunks.add(pcm);
      total += pcm.length;
    }
    final skip = (stream.preSkip * channels).clamp(0, total);
    final out = Int16List(total - skip);
    var written = 0;
    var toSkip = skip;
    for (final chunk in chunks) {
      var start = 0;
      if (toSkip > 0) {
        start = toSkip < chunk.length ? toSkip : chunk.length;
        toSkip -= start;
      }
      out.setRange(written, written + chunk.length - start, chunk, start);
      written += chunk.length - start;
    }
    return out;
  } finally {
    decoder.destroy();
  }
}

/// Tệp WebM / Ogg (Opus) → nội dung WAV. Ném lỗi nếu không giải mã được.
Uint8List opusFileBytesToWav(Uint8List bytes) {
  final stream = parseOpusContainer(bytes);
  final pcm = decodeOpusPackets(stream);
  if (pcm.isEmpty) throw const OpusContainerException('Ghi âm rỗng');
  return buildWav(pcm, channels: stream.channels);
}

/// Đọc tệp, giải mã, ghi WAV ra [target]. Chạy được trong isolate khi truyền
/// [library] đã mở (hoặc để mặc định nạp lại trong isolate).
Future<void> opusFileToWavFile(File source, File target) async {
  await ensureOpusLoaded();
  final wav = opusFileBytesToWav(await source.readAsBytes());
  await target.writeAsBytes(wav, flush: true);
}
