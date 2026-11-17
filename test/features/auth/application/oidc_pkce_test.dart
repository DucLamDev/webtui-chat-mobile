import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/auth/application/oidc_pkce.dart';

void main() {
  test('S256 challenge matches the RFC 7636 appendix B vector', () {
    expect(
      oidcPkceChallengeS256('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('verifier is 43 unpadded base64url characters from 32 bytes', () {
    final pair = generateOidcPkcePair();
    expect(pair.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(pair.challenge, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(pair.challenge, oidcPkceChallengeS256(pair.verifier));
  });

  test('every pair is fresh and toString never exposes the verifier', () {
    final first = generateOidcPkcePair();
    final second = generateOidcPkcePair();
    expect(second.verifier, isNot(first.verifier));
    expect(first.toString(), isNot(contains(first.verifier)));
    expect(first.toString(), isNot(contains(first.challenge)));
  });

  test('verifier encodes exactly the 32 random bytes', () {
    final pair = generateOidcPkcePair(random: _ConstantRandom(0xff));
    // 32 byte 0xff = 42 ký tự '_' và ký tự cuối '8' (4 bit dữ liệu, không đệm).
    expect(pair.verifier, '${'_' * 42}8');
  });
}

final class _ConstantRandom implements Random {
  _ConstantRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
