import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('media credentials never enter redirect-following platform players', () {
    final media = source(
      'lib/features/conversations/presentation/widgets/'
      'message_media_widgets.dart',
    );
    final avatar = source('lib/design_system/components/webtui_avatar.dart');
    final downloader = source(
      'lib/core/network/redirect_safe_file_downloader.dart',
    );
    final ownedImage = source(
      'lib/design_system/components/webtui_owned_decoded_image.dart',
    );

    expect(media, isNot(contains('VideoPlayerController.networkUrl')));
    expect(media, contains('VideoPlayerController.file'));
    expect(media, isNot(contains('BytesSource(')));
    expect(avatar, isNot(contains('Image.network(')));
    expect(avatar, isNot(contains('Image.memory(')));
    expect(media, isNot(contains('Image.memory(')));
    expect(media, contains('WebTuiOwnedDecodedImage('));
    expect(ownedImage, contains('ImageDescriptor.encoded'));
    expect(ownedImage, contains('RawImage('));
    expect(ownedImage, contains('image.dispose()'));
    expect(downloader, contains('followRedirects = false'));
    expect(downloader, contains('redirect rejected'));
  });

  test('eager media work is bounded and video remains user initiated', () {
    final media = source(
      'lib/features/conversations/presentation/widgets/'
      'message_media_widgets.dart',
    );
    final room = source(
      'lib/features/conversations/presentation/screens/chat_room_screen.dart',
    );

    expect(media, contains('maxImagePreviewBytes = 5 * 1024 * 1024'));
    expect(media, contains('maxVoicePlaybackBytes = 100 * 1024 * 1024'));
    // Rà soát 18/11/2026: iPhone luôn tải cả video rồi mới phát, mức 250 MB làm video lớn hơn (gửi được tới mức
    // tải lên tối đa) không bao giờ xem được. Vẫn có giới hạn: bằng mức tải lên tối đa, và chỉ tải khi người dùng bấm.
    expect(
      media,
      contains(
        'maxVideoPlaybackBytes = UploadMessageAttachmentUseCase.maxBytes',
      ),
    );
    expect(media, contains('_requestDownload'));
    expect(
      media,
      isNot(contains('super.initState();\n    unawaited(_initialize());')),
      reason: 'video downloads must remain user initiated',
    );
    expect(media, contains('_videoDownloadGate.run'));
    expect(media, contains('generation == _initializationGeneration'));
    expect(room, contains('maxRenderedAttachmentsPerMessage = 20'));
    expect(room, contains('maxEagerImagePreviewsPerMessage = 4'));
  });
}
