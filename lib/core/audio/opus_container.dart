import 'dart:convert';
import 'dart:typed_data';

/// Lỗi khi tách gói Opus (tệp hỏng, không phải Opus, kiểu chưa hỗ trợ).
final class OpusContainerException implements Exception {
  const OpusContainerException(this.message);
  final String message;

  @override
  String toString() => 'OpusContainerException: $message';
}

/// Các gói Opus tách từ một tệp WebM / Ogg.
final class OpusStream {
  const OpusStream({
    required this.channels,
    required this.preSkip,
    required this.packets,
  });

  final int channels;

  /// Số mẫu (ở 48 kHz, mỗi kênh) phải bỏ ở đầu.
  final int preSkip;
  final List<Uint8List> packets;
}

enum AudioContainer { webm, ogg, other }

/// Nhận diện vỏ tệp theo vài byte đầu.
AudioContainer sniffAudioContainer(List<int> head) {
  if (head.length >= 4 &&
      head[0] == 0x1A &&
      head[1] == 0x45 &&
      head[2] == 0xDF &&
      head[3] == 0xA3) {
    return AudioContainer.webm;
  }
  if (head.length >= 4 &&
      head[0] == 0x4F &&
      head[1] == 0x67 &&
      head[2] == 0x67 &&
      head[3] == 0x53) {
    return AudioContainer.ogg;
  }
  return AudioContainer.other;
}

const _extensions = {'webm', 'ogg', 'oga', 'opus', 'weba', 'mka'};

/// Tên / mime gợi ý đây là WebM / Ogg / Opus (chưa chắc, cần kiểm byte đầu).
bool looksLikeOpusContainer({String? name, String? mimeType}) {
  final lowerName = (name ?? '').trim().toLowerCase();
  final dot = lowerName.lastIndexOf('.');
  if (dot >= 0 && _extensions.contains(lowerName.substring(dot + 1))) {
    return true;
  }
  final mime = (mimeType ?? '').trim().toLowerCase();
  return mime.contains('webm') ||
      mime.contains('ogg') ||
      mime.contains('opus') ||
      mime.contains('matroska');
}

/// Tách gói Opus theo vỏ tệp (tự nhận diện bằng byte đầu).
OpusStream parseOpusContainer(Uint8List bytes) {
  return switch (sniffAudioContainer(bytes)) {
    AudioContainer.webm => parseWebmOpus(bytes),
    AudioContainer.ogg => parseOggOpus(bytes),
    AudioContainer.other => throw const OpusContainerException(
      'Không phải WebM hoặc Ogg',
    ),
  };
}

// ---------------------------------------------------------------- WebM

const _idSegment = 0x18538067;
const _idTracks = 0x1654AE6B;
const _idTrackEntry = 0xAE;
const _idTrackNumber = 0xD7;
const _idCodecId = 0x86;
const _idCodecPrivate = 0x63A2;
const _idCluster = 0x1F43B675;
const _idBlockGroup = 0xA0;
const _idBlock = 0xA1;
const _idSimpleBlock = 0xA3;

class _Track {
  int number = -1;
  String codec = '';
  Uint8List? codecPrivate;
}

/// Tách gói Opus từ WebM (Matroska). Không dựa vào kích thước của phần tử
/// bao ngoài (Segment, Cluster...) nên đọc được cả khi ghi dạng "unknown size"
/// như MediaRecorder của Chrome.
OpusStream parseWebmOpus(Uint8List bytes) {
  const containers = {
    _idSegment,
    _idTracks,
    _idTrackEntry,
    _idCluster,
    _idBlockGroup,
  };
  final tracks = <_Track>[];
  final blocks = <(int, Uint8List)>[];
  var pos = 0;
  final end = bytes.length;
  while (pos < end) {
    final id = _readId(bytes, pos);
    if (id == null) break;
    pos += id.$2;
    final size = _readVint(bytes, pos);
    if (size == null) break;
    pos += size.$2;
    final isContainer = containers.contains(id.$1);
    if (isContainer) {
      // Đi vào bên trong, bỏ qua kích thước (có thể là "unknown").
      if (id.$1 == _idTrackEntry) tracks.add(_Track());
      continue;
    }
    final unknown = size.$3;
    if (unknown) {
      throw const OpusContainerException(
        'Phần tử WebM không rõ kích thước ở chỗ không hỗ trợ',
      );
    }
    final length = size.$1;
    final dataEnd = pos + length;
    final truncated = dataEnd > end;
    final available = truncated ? end - pos : length;
    switch (id.$1) {
      case _idTrackNumber when tracks.isNotEmpty && !truncated:
        tracks.last.number = _readUint(bytes, pos, length);
      case _idCodecId when tracks.isNotEmpty && !truncated:
        tracks.last.codec = latin1.decode(
          bytes.sublist(pos, dataEnd).takeWhile((b) => b != 0).toList(),
        );
      case _idCodecPrivate when tracks.isNotEmpty && !truncated:
        tracks.last.codecPrivate = Uint8List.sublistView(bytes, pos, dataEnd);
      case _idSimpleBlock || _idBlock:
        if (truncated) {
          // Tệp bị cắt giữa chừng: bỏ khối dở dang, giữ phần đã đọc.
          pos = end;
          continue;
        }
        final block = _readBlock(bytes, pos, dataEnd);
        blocks.add(block);
    }
    pos += truncated ? available : length;
  }

  final track = tracks.where((t) => t.codec == 'A_OPUS').firstOrNull;
  if (track == null) {
    throw const OpusContainerException('WebM không chứa Opus');
  }
  var channels = 1;
  var preSkip = 0;
  final head = track.codecPrivate;
  if (head != null && head.length >= 12 && _isOpusHead(head)) {
    channels = head[9];
    preSkip = head[10] | (head[11] << 8);
  }
  final packets = [
    for (final b in blocks)
      if (b.$1 == track.number || track.number < 0) b.$2,
  ];
  if (packets.isEmpty) {
    throw const OpusContainerException('WebM không có gói âm thanh');
  }
  return OpusStream(channels: channels, preSkip: preSkip, packets: packets);
}

(int, Uint8List) _readBlock(Uint8List bytes, int start, int end) {
  final track = _readVint(bytes, start);
  if (track == null) throw const OpusContainerException('Khối WebM hỏng');
  var p = start + track.$2;
  if (p + 3 > end) throw const OpusContainerException('Khối WebM hỏng');
  final flags = bytes[p + 2];
  p += 3;
  if (((flags >> 1) & 3) != 0) {
    throw const OpusContainerException('WebM dùng lacing, chưa hỗ trợ');
  }
  return (track.$1, Uint8List.sublistView(bytes, p, end));
}

bool _isOpusHead(Uint8List b) =>
    b.length >= 8 && latin1.decode(b.sublist(0, 8)) == 'OpusHead';

/// Đọc ID phần tử (giữ bit đánh dấu độ dài). Trả (id, số byte).
(int, int)? _readId(Uint8List b, int pos) {
  if (pos >= b.length) return null;
  final first = b[pos];
  var len = 1;
  var mask = 0x80;
  while (len <= 4 && (first & mask) == 0) {
    len++;
    mask >>= 1;
  }
  if (len > 4 || pos + len > b.length) return null;
  var value = 0;
  for (var i = 0; i < len; i++) {
    value = (value << 8) | b[pos + i];
  }
  return (value, len);
}

/// Đọc vint (kích thước / số track). Trả (giá trị, số byte, unknown?).
(int, int, bool)? _readVint(Uint8List b, int pos) {
  if (pos >= b.length) return null;
  final first = b[pos];
  var len = 1;
  var mask = 0x80;
  while (len <= 8 && (first & mask) == 0) {
    len++;
    mask >>= 1;
  }
  if (len > 8 || pos + len > b.length) return null;
  var value = first & (mask - 1);
  var allOnes = value == mask - 1;
  for (var i = 1; i < len; i++) {
    final byte = b[pos + i];
    if (byte != 0xFF) allOnes = false;
    value = (value << 8) | byte;
  }
  return (value, len, allOnes);
}

int _readUint(Uint8List b, int pos, int length) {
  var value = 0;
  for (var i = 0; i < length; i++) {
    value = (value << 8) | b[pos + i];
  }
  return value;
}

// ----------------------------------------------------------------- Ogg

/// Tách gói Opus từ Ogg: ghép bảng segment thành gói, bỏ OpusHead / OpusTags.
OpusStream parseOggOpus(Uint8List bytes) {
  var pos = 0;
  int? serial;
  var channels = 1;
  var preSkip = 0;
  var sawHead = false;
  final packets = <Uint8List>[];
  final pending = BytesBuilder(copy: false);
  var hasPending = false;

  void emit(Uint8List packet) {
    if (!sawHead) {
      if (!_isOpusHead(packet) || packet.length < 12) {
        throw const OpusContainerException('Ogg không chứa Opus');
      }
      sawHead = true;
      channels = packet[9];
      preSkip = packet[10] | (packet[11] << 8);
      return;
    }
    if (packet.length >= 8 &&
        latin1.decode(packet.sublist(0, 8)) == 'OpusTags') {
      return;
    }
    packets.add(packet);
  }

  while (pos + 27 <= bytes.length) {
    if (bytes[pos] != 0x4F ||
        bytes[pos + 1] != 0x67 ||
        bytes[pos + 2] != 0x67 ||
        bytes[pos + 3] != 0x53) {
      throw const OpusContainerException('Trang Ogg hỏng');
    }
    final pageSerial = ByteData.sublistView(
      bytes,
      pos + 14,
      pos + 18,
    ).getUint32(0, Endian.little);
    final segments = bytes[pos + 26];
    final tableEnd = pos + 27 + segments;
    if (tableEnd > bytes.length) break;
    var dataLength = 0;
    for (var i = 0; i < segments; i++) {
      dataLength += bytes[pos + 27 + i];
    }
    final dataEnd = tableEnd + dataLength;
    if (dataEnd > bytes.length) break;
    serial ??= pageSerial;
    if (pageSerial == serial) {
      var offset = tableEnd;
      for (var i = 0; i < segments; i++) {
        final len = bytes[pos + 27 + i];
        pending.add(Uint8List.sublistView(bytes, offset, offset + len));
        hasPending = true;
        offset += len;
        if (len < 255) {
          emit(pending.takeBytes());
          hasPending = false;
        }
      }
    }
    pos = dataEnd;
  }
  if (hasPending && sawHead) {
    // Gói cuối dở dang (tệp bị cắt): bỏ.
    pending.clear();
  }
  if (!sawHead) throw const OpusContainerException('Ogg không chứa Opus');
  if (packets.isEmpty) {
    throw const OpusContainerException('Ogg không có gói âm thanh');
  }
  return OpusStream(channels: channels, preSkip: preSkip, packets: packets);
}
