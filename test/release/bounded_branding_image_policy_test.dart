import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('organization branding never uses raw unbounded network images', () {
    for (final path in const [
      'lib/features/auth/presentation/screens/login_screen.dart',
      'lib/features/home/presentation/screens/home_shell_screen.dart',
      'lib/core/privacy/background_privacy.dart',
    ]) {
      final contents = source(path);
      expect(contents, isNot(contains('Image.network(')), reason: path);
      expect(contents, contains('WebTuiBoundedNetworkImage('), reason: path);
      expect(contents, contains('allowPublicRequest: true'), reason: path);
    }
  });

  test('shared avatar and logo transport has aggregate resource bounds', () {
    final avatar = source('lib/design_system/components/webtui_avatar.dart');
    final app = source('lib/app/app.dart');
    final pool = source('lib/core/network/bounded_image_request_pool.dart');
    final ownedImage = source(
      'lib/design_system/components/webtui_owned_decoded_image.dart',
    );

    expect(avatar, contains('webTuiMaxAvatarImageBytes = 512 * 1024'));
    expect(avatar, contains('webTuiMaxBrandImageBytes = 1024 * 1024'));
    expect(avatar, isNot(contains('Image.memory(')));
    expect(avatar, contains('WebTuiOwnedDecodedImage('));
    expect(ownedImage, contains('ImageDescriptor.encoded'));
    expect(ownedImage, contains('RawImage('));
    expect(ownedImage, contains('descriptor?.dispose()'));
    expect(ownedImage, contains('buffer?.dispose()'));
    expect(app, contains('BoundedImageRequestPool'));
    expect(
      app,
      contains('if (!isSameOrigin && !allowPublicRequest)'),
      reason: 'user avatars cannot trigger arbitrary external tracking loads',
    );
    expect(
      app,
      contains('if (isSameOrigin && !allowPublicRequest)'),
      reason: 'public branding must never receive an account bearer',
    );
    expect(app, contains('_imageCacheEpoch'));
    expect(app, contains('sha256.convert'));
    expect(pool, contains('maxConcurrent = 3'));
    expect(pool, contains('maxCacheBytes = 8 * 1024 * 1024'));
    expect(pool, contains('_inFlight'));
    expect(pool, contains('requestGeneration == _generation'));
  });
}
