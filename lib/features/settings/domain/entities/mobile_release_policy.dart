final class MobileReleasePolicy {
  const MobileReleasePolicy({
    required this.platform,
    required this.channel,
    required this.currentVersion,
    this.minimumVersion,
    this.recommendedVersion,
    this.downloadUrl,
    this.storeUrl,
    this.releaseNotes,
    this.isRequired = false,
  });

  final String platform;
  final String channel;
  final String currentVersion;
  final String? minimumVersion;
  final String? recommendedVersion;
  final String? downloadUrl;
  final String? storeUrl;
  final String? releaseNotes;
  final bool isRequired;

  bool get requiresUpdate =>
      isRequired || _isVersionOlder(currentVersion, minimumVersion);

  bool get recommendsUpdate =>
      requiresUpdate || _isVersionOlder(currentVersion, recommendedVersion);
}

bool _isVersionOlder(String current, String? target) {
  final currentParts = _versionParts(current);
  final targetParts = _versionParts(target);
  if (targetParts.isEmpty) {
    return false;
  }
  for (var index = 0; index < 3; index++) {
    final currentPart = index < currentParts.length ? currentParts[index] : 0;
    final targetPart = index < targetParts.length ? targetParts[index] : 0;
    if (currentPart < targetPart) {
      return true;
    }
    if (currentPart > targetPart) {
      return false;
    }
  }
  return false;
}

List<int> _versionParts(String? value) {
  final version = value?.split('+').first.trim();
  if (version == null || version.isEmpty) {
    return const [];
  }
  return version
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
}
