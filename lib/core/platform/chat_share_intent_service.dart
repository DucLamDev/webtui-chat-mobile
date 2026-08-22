import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

final class ChatSharePayload {
  const ChatSharePayload({this.text, this.files = const []});

  final String? text;
  final List<SharedChatFile> files;

  bool get isEmpty => (text?.trim().isNotEmpty != true) && files.isEmpty;

  String get summary {
    final textPart = text?.trim();
    if (files.isEmpty) {
      return textPart?.isNotEmpty == true ? '1 nội dung văn bản' : '';
    }
    final fileLabel = files.length == 1
        ? files.first.name
        : '${files.length} tệp';
    if (textPart?.isNotEmpty == true) {
      return '$fileLabel kèm văn bản';
    }
    return fileLabel;
  }
}

final class SharedChatFile {
  const SharedChatFile({
    required this.path,
    required this.name,
    required this.mimeType,
  });

  final String path;
  final String name;
  final String mimeType;
}

final class ChatShareIntentService {
  final StreamController<ChatSharePayload> _controller =
      StreamController<ChatSharePayload>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _subscription;
  bool _started = false;

  Stream<ChatSharePayload> get payloads => _controller.stream;

  Future<void> start() async {
    if (_started || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    _started = true;
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _emit,
      onError: (_) {},
    );
    try {
      _emit(await ReceiveSharingIntent.instance.getInitialMedia());
    } on Object {
      // Share intents are opportunistic; the normal chat flow must continue.
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }

  void _emit(List<SharedMediaFile> media) {
    final payload = _payloadFromMedia(media);
    if (payload.isEmpty) {
      return;
    }
    _controller.add(payload);
    unawaited(ReceiveSharingIntent.instance.reset());
  }
}

ChatSharePayload _payloadFromMedia(List<SharedMediaFile> media) {
  final textParts = <String>[];
  final files = <SharedChatFile>[];
  for (final item in media) {
    final path = item.path.trim();
    final message = item.message?.trim();
    switch (item.type) {
      case SharedMediaType.text:
      case SharedMediaType.url:
        if (path.isNotEmpty) {
          textParts.add(path);
        }
        if (message != null && message.isNotEmpty && message != path) {
          textParts.add(message);
        }
        break;
      case SharedMediaType.image:
      case SharedMediaType.video:
      case SharedMediaType.file:
        if (path.isEmpty) {
          continue;
        }
        files.add(
          SharedChatFile(
            path: path,
            name: _fileNameFromPath(path),
            mimeType: _mimeTypeForSharedFile(item),
          ),
        );
        if (message != null && message.isNotEmpty) {
          textParts.add(message);
        }
        break;
    }
  }
  return ChatSharePayload(
    text: textParts.isEmpty ? null : textParts.join('\n').trim(),
    files: files,
  );
}

String _mimeTypeForSharedFile(SharedMediaFile item) {
  final declared = item.mimeType?.trim().toLowerCase();
  if (declared != null && declared.isNotEmpty) {
    return declared;
  }
  final inferred = _mimeFromPath(item.path);
  if (inferred != 'application/octet-stream') {
    return inferred;
  }
  return switch (item.type) {
    SharedMediaType.image => 'image/jpeg',
    SharedMediaType.video => 'video/mp4',
    SharedMediaType.text => 'text/plain',
    SharedMediaType.url => 'text/plain',
    SharedMediaType.file => _mimeFromPath(item.path),
  };
}

String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  return name.isEmpty ? 'shared_file' : name;
}

String _mimeFromPath(String path) {
  final extension = _extensionFromPath(path);
  return switch (extension) {
    'aac' => 'audio/aac',
    'csv' => 'text/csv',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'gif' => 'image/gif',
    'heic' || 'heif' => 'image/heic',
    'jpg' || 'jpeg' => 'image/jpeg',
    'json' => 'application/json',
    'm4a' => 'audio/mp4',
    'm4v' => 'video/x-m4v',
    'md' || 'markdown' => 'text/markdown',
    'mkv' => 'video/x-matroska',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'mp4' => 'video/mp4',
    'ogg' => 'audio/ogg',
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    'wav' => 'audio/wav',
    'webm' => 'video/webm',
    'webp' => 'image/webp',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

String _extensionFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}
