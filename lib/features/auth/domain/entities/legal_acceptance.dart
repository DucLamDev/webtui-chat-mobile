final class LegalDocumentAcceptance {
  const LegalDocumentAcceptance({
    required this.version,
    required this.accepted,
    this.acceptedAt,
  });

  final String version;
  final bool accepted;
  final DateTime? acceptedAt;
}

final class LegalAcceptance {
  const LegalAcceptance({
    required this.workspaceId,
    required this.serverComplete,
    required this.terms,
    required this.privacy,
  });

  final String workspaceId;
  final bool serverComplete;
  final LegalDocumentAcceptance terms;
  final LegalDocumentAcceptance privacy;

  bool get isComplete =>
      serverComplete &&
      terms.accepted &&
      terms.acceptedAt != null &&
      privacy.accepted &&
      privacy.acceptedAt != null;

  bool matchesPublisherVersions({
    required String termsVersion,
    required String privacyVersion,
  }) {
    final expectedTerms = termsVersion.trim();
    final expectedPrivacy = privacyVersion.trim();
    return expectedTerms.isNotEmpty &&
        expectedPrivacy.isNotEmpty &&
        terms.version.trim() == expectedTerms &&
        privacy.version.trim() == expectedPrivacy;
  }
}
