import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../l10n/app_strings.dart';
import 'ide_ai_json.dart';

/// Một lệnh `/` trong ô gõ.
final class IdeSlashCommand {
  const IdeSlashCommand(this.name, this.description, {this.takesValue = false});

  /// Có dấu `/` ở đầu.
  final String name;
  final String description;

  /// Cần gõ thêm giá trị (vd `/model tên`): chọn xong chỉ chèn tên + dấu cách.
  final bool takesValue;
}

/// Lệnh có sẵn như IDE web (`IDE_SLASH` của chat.py) rồi tới `state.commands`.
List<IdeSlashCommand> ideSlashCommands(List<Map<String, Object?>> extra) {
  final base = <IdeSlashCommand>[
    IdeSlashCommand(
      '/status',
      tr('Xem trạng thái phiên', 'Show session status'),
    ),
    IdeSlashCommand('/used', tr('Mức dùng của tài khoản', 'Account usage')),
    IdeSlashCommand('/fast', tr('Bật / tắt chế độ nhanh', 'Toggle fast mode')),
    IdeSlashCommand('/new', tr('Cuộc trò chuyện mới', 'New conversation')),
    IdeSlashCommand('/clear', tr('Xoá cuộc trò chuyện', 'Clear conversation')),
    IdeSlashCommand('/compact', tr('Thu gọn ngữ cảnh', 'Compact context')),
    IdeSlashCommand(
      '/model',
      tr('Đổi model', 'Change model'),
      takesValue: true,
    ),
    IdeSlashCommand(
      '/effort',
      tr('Đổi mức nghĩ', 'Change effort'),
      takesValue: true,
    ),
    IdeSlashCommand(
      '/permissions',
      tr('Đổi quyền của AI', 'Change permissions'),
      takesValue: true,
    ),
  ];
  final seen = {for (final c in base) c.name};
  for (final item in extra) {
    var name = aiStr(item['name']).trim();
    if (name.isEmpty) continue;
    if (!name.startsWith('/')) name = '/$name';
    if (!RegExp(r'^/[A-Za-z0-9_:.-]{1,60}$').hasMatch(name)) continue;
    if (!seen.add(name)) continue;
    base.add(IdeSlashCommand(name, aiStr(item['description'])));
  }
  return base;
}

/// Tệp người dùng vừa chọn, chờ tải lên.
final class IdePickedFile {
  const IdePickedFile({
    required this.name,
    required this.mime,
    required this.size,
    required this.read,
    required this.isImage,
  });

  final String name;
  final String mime;
  final int size;
  final bool isImage;
  final Stream<List<int>> Function() read;
}

/// Chọn ảnh / camera / tệp (bản thật dùng `image_picker`, `file_picker`).
abstract interface class IdeAttachmentPicker {
  Future<IdePickedFile?> pickImage({required bool camera});
  Future<IdePickedFile?> pickFile();
}

String ideMimeOf(String name) {
  final lower = name.toLowerCase();
  const map = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'log': 'text/plain',
    'md': 'text/markdown',
    'json': 'application/json',
    'zip': 'application/zip',
    'mp4': 'video/mp4',
  };
  final dot = lower.lastIndexOf('.');
  return dot < 0
      ? 'application/octet-stream'
      : map[lower.substring(dot + 1)] ?? 'application/octet-stream';
}

final class PlatformIdeAttachmentPicker implements IdeAttachmentPicker {
  PlatformIdeAttachmentPicker({ImagePicker? images})
    : _images = images ?? ImagePicker();

  final ImagePicker _images;

  @override
  Future<IdePickedFile?> pickImage({required bool camera}) async {
    final shot = await _images.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2560,
      maxHeight: 2560,
    );
    if (shot == null) return null;
    final name = shot.name.isEmpty ? 'anh.jpg' : shot.name;
    final size = await shot.length();
    return IdePickedFile(
      name: name,
      mime: ideMimeOf(name),
      size: size,
      isImage: true,
      read: shot.openRead,
    );
  }

  @override
  Future<IdePickedFile?> pickFile() async {
    final result = await FilePicker.pickFiles(withReadStream: true);
    final file = result?.files.single;
    if (file == null || file.readStream == null) return null;
    return IdePickedFile(
      name: file.name,
      mime: ideMimeOf(file.name),
      size: file.size,
      isImage: ideMimeOf(file.name).startsWith('image/'),
      read: () => file.readStream!,
    );
  }
}
