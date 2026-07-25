enum AvatarPickerSource { camera, gallery }

final class PickedAvatar {
  const PickedAvatar({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;
}

final class UploadedAvatar {
  const UploadedAvatar({required this.fileId, required this.downloadPath});

  final String fileId;
  final String downloadPath;
}
