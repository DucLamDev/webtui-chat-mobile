import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Cặp PKCE (RFC 7636) gắn mã đăng nhập một lần OIDC với đúng lượt đăng nhập của app.
///
/// Verifier chỉ giữ trong bộ nhớ của lượt đang chờ; không ghi đĩa, không log.
final class OidcPkcePair {
  const OidcPkcePair({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;

  @override
  String toString() => 'OidcPkcePair(<redacted>)';
}

/// Sinh verifier = base64url không đệm của 32 byte ngẫu nhiên an toàn (43 ký tự)
/// và challenge S256 tương ứng.
OidcPkcePair generateOidcPkcePair({Random? random}) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  final verifier = _base64UrlNoPadding(bytes);
  return OidcPkcePair(
    verifier: verifier,
    challenge: oidcPkceChallengeS256(verifier),
  );
}

/// BASE64URL_NOPAD(SHA256(ASCII(verifier))) theo RFC 7636 mục 4.2.
String oidcPkceChallengeS256(String verifier) {
  return _base64UrlNoPadding(sha256.convert(ascii.encode(verifier)).bytes);
}

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
