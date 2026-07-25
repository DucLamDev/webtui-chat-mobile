final class ChannelFile {
  const ChannelFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String mimeType;
  final int byteSize;
  final DateTime createdAt;
}
