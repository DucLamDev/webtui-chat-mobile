/// `POST /integrations/vpsttt-ide/launch` (không có tên, email, quyền).
final class IdeWebLaunchRequest {
  const IdeWebLaunchRequest({
    required this.platform,
    required this.appVersion,
    required this.codeChallenge,
    this.possessionKeyId,
    this.biometricKeyId,
  });

  final String platform;
  final String appVersion;
  final String codeChallenge;
  final String? possessionKeyId;
  final String? biometricKeyId;

  Map<String, Object?> toJson() => {
    'platform': platform,
    'app_version': appVersion,
    'bridge_version': ideWebBridgeVersion,
    'callback': 'custom_scheme',
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
    'device': {
      'possession_key_id': possessionKeyId,
      'biometric_key_id': biometricKeyId,
    },
  };
}

const ideWebBridgeVersion = 1;
const ideWebCallbackScheme = 'webtui';

/// Hạn một lượt đăng nhập (giờ máy; máy chủ là nguồn đúng).
const ideWebLaunchTtl = Duration(minutes: 10);

/// Hạn chờ mỗi lần gọi mạng phía app.
const ideWebNetworkTimeout = Duration(seconds: 20);

sealed class IdeWebLaunch {
  const IdeWebLaunch({required this.launchId});

  final String launchId;
}

/// Cần đăng nhập bằng trình duyệt hệ thống.
final class IdeWebBrowserLaunch extends IdeWebLaunch {
  const IdeWebBrowserLaunch({
    required super.launchId,
    required this.state,
    required this.browserUrl,
    required this.expiresAt,
  });

  final String state;
  final Uri browserUrl;
  final DateTime expiresAt;

  @override
  String toString() => 'IdeWebBrowserLaunch(<redacted>)';
}

/// Thiết bị đã đăng ký: vào thẳng WebView.
final class IdeWebDirectLaunch extends IdeWebLaunch {
  const IdeWebDirectLaunch({required super.launchId, required this.entry});

  final IdeWebEntry entry;
}

/// Dữ liệu một lần để mở WebView (gửi bằng thân POST, không nằm trong URL).
final class IdeWebEntry {
  const IdeWebEntry({
    required this.enterUrl,
    required this.gateToken,
    required this.openCode,
    required this.expiresAt,
    required this.bridgeEnabled,
  });

  final Uri enterUrl;
  final String gateToken;
  final String openCode;
  final DateTime expiresAt;
  final bool bridgeEnabled;

  @override
  String toString() => 'IdeWebEntry(<redacted>)';
}

/// Lượt đang chờ trình duyệt; giữ qua việc app bị hệ điều hành tắt. Không ghi
/// thế hệ phiên: mỗi lần mở lạnh app sinh thế hệ mới. Phiên khác thì bản ghi đã
/// bị `clearSession` xoá hoặc lệch [scopeId] / [userId].
final class PendingIdeWebLaunch {
  const PendingIdeWebLaunch({
    required this.launchId,
    required this.state,
    required this.codeVerifier,
    required this.scopeId,
    required this.userId,
    required this.expiresAt,
  });

  static PendingIdeWebLaunch? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    String? text(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final launchId = text('launch_id');
    final state = text('state');
    final verifier = text('verifier');
    final scopeId = text('scope');
    final userId = text('user');
    final expiresAt = DateTime.tryParse(text('expires_at') ?? '');
    if (launchId == null ||
        state == null ||
        verifier == null ||
        scopeId == null ||
        userId == null ||
        expiresAt == null) {
      return null;
    }
    return PendingIdeWebLaunch(
      launchId: launchId,
      state: state,
      codeVerifier: verifier,
      scopeId: scopeId,
      userId: userId,
      expiresAt: expiresAt,
    );
  }

  final String launchId;
  final String state;
  final String codeVerifier;
  final String scopeId;
  final String userId;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => {
    'v': 1,
    'launch_id': launchId,
    'state': state,
    'verifier': codeVerifier,
    'scope': scopeId,
    'user': userId,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'PendingIdeWebLaunch(<redacted>)';
}

/// `state` + `code` trong callback; `null` khi không đúng dạng.
({String state, String code})? parseIdeWebCallback(Uri uri) {
  if (uri.scheme.toLowerCase() != ideWebCallbackScheme ||
      uri.host.toLowerCase() != 'ide-web' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.path != '/callback' ||
      uri.hasFragment) {
    return null;
  }
  final Map<String, List<String>> query;
  try {
    query = uri.queryParametersAll;
  } on Object {
    return null;
  }
  final states = query['state'] ?? const [];
  final codes = query['code'] ?? const [];
  // Tham số lặp là dấu hiệu chèn: bỏ cả callback.
  if (states.length != 1 || codes.length != 1) return null;
  final state = states.single;
  final code = codes.single;
  if (state.isEmpty ||
      state.length > 512 ||
      code.isEmpty ||
      code.length > 2048) {
    return null;
  }
  return (state: state, code: code);
}

/// So chuỗi không dừng sớm ở ký tự khác đầu tiên.
bool ideWebConstantTimeEquals(String a, String b) {
  final left = a.codeUnits;
  final right = b.codeUnits;
  var diff = left.length ^ right.length;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ (i < right.length ? right[i] : 0);
  }
  return diff == 0;
}
