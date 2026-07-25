import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/repositories/avatar_repository.dart';

final class ImagePickerAvatarRepository implements AvatarPickerRepository {
  ImagePickerAvatarRepository({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _avatarSize = 1024;

  @override
  Future<Result<PickedAvatar?>> pick(AvatarPickerSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source == AvatarPickerSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
      );
      if (image == null) {
        return const Success(null);
      }

      return Success(await _cropToSquareAvatar(image));
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể chọn ảnh đại diện.',
          code: 'AVATAR_PICK_FAILED',
          cause: error,
        ),
      );
    }
  }

  Future<PickedAvatar> _cropToSquareAvatar(XFile image) async {
    final bytes = await image.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final side = math.min(sourceImage.width, sourceImage.height).toDouble();
    final sourceRect = ui.Rect.fromLTWH(
      (sourceImage.width - side) / 2,
      (sourceImage.height - side) / 2,
      side,
      side,
    );
    final destinationRect = ui.Rect.fromLTWH(
      0,
      0,
      _avatarSize.toDouble(),
      _avatarSize.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      sourceImage,
      sourceRect,
      destinationRect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(_avatarSize, _avatarSize);
    final data = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    sourceImage.dispose();
    croppedImage.dispose();
    picture.dispose();
    if (data == null) {
      throw StateError('Cannot encode cropped avatar.');
    }

    final directory = await getTemporaryDirectory();
    final fileName = 'avatar_${DateTime.now().microsecondsSinceEpoch}.png';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return PickedAvatar(
      path: file.path,
      fileName: fileName,
      mimeType: 'image/png',
    );
  }
}
