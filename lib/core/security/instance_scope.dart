import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Immutable boundary for all state owned by one self-hosted installation.
///
/// The backend's stable UUID prevents workspace/channel UUID collisions across
/// installations. Binding that UUID to the canonical origin also prevents a
/// different host from claiming an existing local instance namespace.
final class InstanceScope {
  InstanceScope._({required this.instanceId, required this.origin})
    : storageId = sha256
          .convert(utf8.encode('$instanceId|${origin.toString()}'))
          .toString();

  factory InstanceScope({
    required String instanceId,
    required Uri serverOrigin,
  }) {
    final normalizedInstanceId = instanceId.trim().toLowerCase();
    if (!_uuidPattern.hasMatch(normalizedInstanceId)) {
      throw const FormatException('Instance ID must be a UUID.');
    }
    return InstanceScope._(
      instanceId: normalizedInstanceId,
      origin: canonicalServerOrigin(serverOrigin),
    );
  }

  final String instanceId;
  final Uri origin;
  final String storageId;

  String get storagePrefix => 'instance_v2:$storageId:';

  String localScope(String namespace) {
    final normalized = namespace.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'must not be empty');
    }
    return '$storagePrefix$normalized';
  }

  bool matches({required String instanceId, required Uri serverOrigin}) {
    try {
      final candidate = InstanceScope(
        instanceId: instanceId,
        serverOrigin: serverOrigin,
      );
      return candidate == this;
    } on FormatException {
      return false;
    }
  }

  @override
  bool operator ==(Object other) {
    return other is InstanceScope &&
        other.instanceId == instanceId &&
        other.origin == origin;
  }

  @override
  int get hashCode => Object.hash(instanceId, origin);
}

Uri canonicalServerOrigin(Uri value) {
  final scheme = value.scheme.toLowerCase();
  final host = value.host.toLowerCase();
  if ((scheme != 'https' && scheme != 'http') ||
      host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.query.isNotEmpty ||
      value.fragment.isNotEmpty ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw const FormatException('Invalid server origin.');
  }
  final defaultPort =
      (scheme == 'https' && value.port == 443) ||
      (scheme == 'http' && value.port == 80);
  return Uri(
    scheme: scheme,
    host: host,
    port: value.hasPort && !defaultPort ? value.port : null,
  );
}

bool serverOriginsMatch(Uri candidate, Uri expected) {
  if (candidate.userInfo.isNotEmpty ||
      expected.userInfo.isNotEmpty ||
      candidate.host.isEmpty ||
      expected.host.isEmpty) {
    return false;
  }
  try {
    return canonicalServerOrigin(
          Uri(
            scheme: candidate.scheme,
            host: candidate.host,
            port: candidate.hasPort ? candidate.port : null,
          ),
        ) ==
        canonicalServerOrigin(
          Uri(
            scheme: expected.scheme,
            host: expected.host,
            port: expected.hasPort ? expected.port : null,
          ),
        );
  } on FormatException {
    return false;
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
