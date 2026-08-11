final class LegalDocumentVersions {
  const LegalDocumentVersions({
    required this.termsVersion,
    required this.privacyVersion,
  });

  final String termsVersion;
  final String privacyVersion;

  bool get isComplete =>
      termsVersion.trim().isNotEmpty && privacyVersion.trim().isNotEmpty;
}
