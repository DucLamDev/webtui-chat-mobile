import 'dart:io';
import 'dart:typed_data';

/// Streams an HTTP response to a private file without ever following a
/// redirect. Authentication may only be attached to the exact URI selected by
/// the caller; a 3xx response is rejected before its Location is contacted.
final class RedirectSafeFileDownloader {
  const RedirectSafeFileDownloader({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final HttpClient Function() _clientFactory;

  Future<File> download({
    required Uri uri,
    required File target,
    required int maxBytes,
    required Future<bool> Function() isStillCurrent,
    String accept = 'application/octet-stream',
    String? bearerToken,
    int? expectedBytes,
  }) async {
    _validateRequest(
      uri: uri,
      maxBytes: maxBytes,
      expectedBytes: expectedBytes,
    );
    if (!await isStillCurrent()) {
      throw const RedirectSafeDownloadException('instance binding changed');
    }

    await target.parent.create(recursive: true);
    final part = File(
      '${target.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    final client = _clientFactory()
      ..autoUncompress = false
      ..idleTimeout = const Duration(seconds: 30)
      ..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      request.headers
        ..set(
          HttpHeaders.acceptHeader,
          accept.trim().isEmpty ? 'application/octet-stream' : accept.trim(),
        )
        ..set(HttpHeaders.acceptEncodingHeader, 'identity');
      final token = bearerToken?.trim();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (!await isStillCurrent()) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (!await isStillCurrent()) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }
      if (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        throw const RedirectSafeDownloadException('redirect rejected');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw RedirectSafeDownloadException(
          'unexpected HTTP status ${response.statusCode}',
        );
      }
      final contentLength = response.contentLength;
      if (contentLength > maxBytes ||
          (expectedBytes != null &&
              contentLength >= 0 &&
              contentLength != expectedBytes)) {
        throw const RedirectSafeDownloadException('response length is invalid');
      }

      sink = part.openWrite(mode: FileMode.writeOnly);
      var written = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (!await isStillCurrent()) {
          throw const RedirectSafeDownloadException('instance binding changed');
        }
        written += chunk.length;
        if (written > maxBytes) {
          throw const RedirectSafeDownloadException('response is too large');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (written <= 0 ||
          (expectedBytes != null && written != expectedBytes) ||
          !await isStillCurrent()) {
        throw const RedirectSafeDownloadException(
          'download did not complete for the active instance',
        );
      }
      if (await target.exists()) {
        await target.delete();
      }
      return part.rename(target.path);
    } on RedirectSafeDownloadException {
      rethrow;
    } on Object catch (error) {
      throw RedirectSafeDownloadException('download failed', cause: error);
    } finally {
      try {
        await sink?.close();
      } on Object {
        // Best-effort close; the partial file is removed below.
      }
      client.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } on Object {
          // A later scoped-cache cleanup can remove an abandoned partial.
        }
      }
    }
  }

  /// Bounded in-memory variant for small decoded assets such as avatars and
  /// image previews. Large media must use [download] instead.
  Future<Uint8List> downloadBytes({
    required Uri uri,
    required int maxBytes,
    required Future<bool> Function() isStillCurrent,
    String accept = 'application/octet-stream',
    String? bearerToken,
  }) async {
    _validateRequest(uri: uri, maxBytes: maxBytes, expectedBytes: null);
    if (!await isStillCurrent()) {
      throw const RedirectSafeDownloadException('instance binding changed');
    }

    final client = _clientFactory()
      ..autoUncompress = false
      ..idleTimeout = const Duration(seconds: 30)
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      request.headers
        ..set(
          HttpHeaders.acceptHeader,
          accept.trim().isEmpty ? 'application/octet-stream' : accept.trim(),
        )
        ..set(HttpHeaders.acceptEncodingHeader, 'identity');
      final token = bearerToken?.trim();
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (!await isStillCurrent()) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (!await isStillCurrent()) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }
      if (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        throw const RedirectSafeDownloadException('redirect rejected');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw RedirectSafeDownloadException(
          'unexpected HTTP status ${response.statusCode}',
        );
      }
      if (response.contentLength > maxBytes) {
        throw const RedirectSafeDownloadException('response is too large');
      }

      final builder = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (!await isStillCurrent()) {
          throw const RedirectSafeDownloadException('instance binding changed');
        }
        length += chunk.length;
        if (length > maxBytes) {
          throw const RedirectSafeDownloadException('response is too large');
        }
        builder.add(chunk);
      }
      if (length <= 0 || !await isStillCurrent()) {
        throw const RedirectSafeDownloadException(
          'download did not complete for the active instance',
        );
      }
      return builder.takeBytes();
    } on RedirectSafeDownloadException {
      rethrow;
    } on Object catch (error) {
      throw RedirectSafeDownloadException('download failed', cause: error);
    } finally {
      client.close(force: true);
    }
  }
}

final class RedirectSafeDownloadException implements Exception {
  const RedirectSafeDownloadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'RedirectSafeDownloadException: $message';
}

HttpClient _defaultClientFactory() => HttpClient();

void _validateRequest({
  required Uri uri,
  required int maxBytes,
  required int? expectedBytes,
}) {
  if (!redirectSafeHttpUriAllowed(uri) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw const RedirectSafeDownloadException('download URI is invalid');
  }
  if (maxBytes <= 0 ||
      expectedBytes != null &&
          (expectedBytes <= 0 || expectedBytes > maxBytes)) {
    throw const RedirectSafeDownloadException('download size is invalid');
  }
}

bool redirectSafeHttpUriAllowed(Uri uri) {
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
