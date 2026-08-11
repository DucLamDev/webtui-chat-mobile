import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/flavor/app_config.dart';
import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/legal_acceptance_access_policy.dart';
import '../../domain/entities/legal_acceptance.dart';

enum LegalAcceptanceStatus {
  idle,
  loading,
  required,
  submitting,
  complete,
  error,
  incompatible,
}

final class LegalAcceptanceState {
  const LegalAcceptanceState({
    this.status = LegalAcceptanceStatus.idle,
    this.acceptance,
    this.acceptedBoth = false,
    this.gateVisible = true,
    this.errorMessage,
  });

  final LegalAcceptanceStatus status;
  final LegalAcceptance? acceptance;
  final bool acceptedBoth;
  final bool gateVisible;
  final String? errorMessage;

  bool get canCreateUserContent => status == LegalAcceptanceStatus.complete;
  bool get isBusy =>
      status == LegalAcceptanceStatus.loading ||
      status == LegalAcceptanceStatus.submitting;

  LegalAcceptanceState copyWith({
    LegalAcceptanceStatus? status,
    LegalAcceptance? acceptance,
    bool? acceptedBoth,
    bool? gateVisible,
    String? errorMessage,
    bool clearAcceptance = false,
    bool clearError = false,
  }) {
    return LegalAcceptanceState(
      status: status ?? this.status,
      acceptance: clearAcceptance ? null : acceptance ?? this.acceptance,
      acceptedBoth: acceptedBoth ?? this.acceptedBoth,
      gateVisible: gateVisible ?? this.gateVisible,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

typedef LoadLegalAcceptance =
    Future<Result<LegalAcceptance>> Function({required String workspaceId});
typedef SubmitLegalAcceptance =
    Future<Result<LegalAcceptance>> Function({
      required String workspaceId,
      required String termsVersion,
      required String privacyVersion,
    });

final legalAcceptanceControllerProvider =
    StateNotifierProvider<LegalAcceptanceController, LegalAcceptanceState>((
      ref,
    ) {
      final config = ref.watch(appConfigProvider);
      return LegalAcceptanceController(
        load: ref.watch(loadLegalAcceptanceUseCaseProvider).execute,
        submit: ref.watch(acceptLegalDocumentsUseCaseProvider).execute,
        accessPolicy: ref.watch(legalAcceptanceAccessPolicyProvider),
        expectedTermsVersion: config.termsVersion,
        expectedPrivacyVersion: config.privacyPolicyVersion,
        legalLinksConfigured: config.hasPublicLegalUrls,
      );
    });

/// Updated by the authenticated workspace shell without eagerly creating the
/// workspace controller on the login screen. Workspace changes proactively
/// re-check acceptance instead of carrying a complete policy across scopes.
final legalAcceptanceWorkspaceScopeProvider = StateProvider<String?>((_) {
  return null;
});

final class LegalAcceptanceController
    extends StateNotifier<LegalAcceptanceState> {
  LegalAcceptanceController({
    required LoadLegalAcceptance load,
    required SubmitLegalAcceptance submit,
    required LegalAcceptanceAccessPolicy accessPolicy,
    required String expectedTermsVersion,
    required String expectedPrivacyVersion,
    required bool legalLinksConfigured,
  }) : _load = load,
       _submit = submit,
       _accessPolicy = accessPolicy,
       _expectedTermsVersion = expectedTermsVersion.trim(),
       _expectedPrivacyVersion = expectedPrivacyVersion.trim(),
       _legalLinksConfigured = legalLinksConfigured,
       super(const LegalAcceptanceState()) {
    _requiredSubscription = _accessPolicy.requiredEvents.listen(
      (_) => _handleAcceptanceRequired(),
    );
  }

  final LoadLegalAcceptance _load;
  final SubmitLegalAcceptance _submit;
  final LegalAcceptanceAccessPolicy _accessPolicy;
  final String _expectedTermsVersion;
  final String _expectedPrivacyVersion;
  final bool _legalLinksConfigured;
  late final StreamSubscription<void> _requiredSubscription;
  int _generation = 0;
  bool _sessionActive = false;
  String? _workspaceId;

  Future<void> beginSession({required String workspaceId}) async {
    final normalizedWorkspaceId = workspaceId.trim();
    if (normalizedWorkspaceId.isEmpty) {
      endSession();
      return;
    }
    _sessionActive = true;
    _workspaceId = normalizedWorkspaceId;
    _accessPolicy.reset();
    await _refresh(showGate: true, clearAcceptance: true);
  }

  void endSession() {
    _sessionActive = false;
    _workspaceId = null;
    _generation++;
    _accessPolicy.reset();
    state = const LegalAcceptanceState();
  }

  Future<void> retry() {
    return _refresh(showGate: true, clearAcceptance: true);
  }

  void setAcceptedBoth(bool value) {
    if (state.status != LegalAcceptanceStatus.required) return;
    state = state.copyWith(acceptedBoth: value, clearError: true);
  }

  void dismissToReadOnly() {
    if (state.status == LegalAcceptanceStatus.complete) return;
    state = state.copyWith(gateVisible: false);
  }

  void openGate() {
    if (state.status == LegalAcceptanceStatus.complete) return;
    state = state.copyWith(gateVisible: true);
  }

  Future<void> accept() async {
    final workspaceId = _workspaceId;
    if (!_sessionActive ||
        workspaceId == null ||
        state.status != LegalAcceptanceStatus.required ||
        !state.acceptedBoth) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      status: LegalAcceptanceStatus.submitting,
      gateVisible: true,
      clearError: true,
    );
    final result = await _submit(
      workspaceId: workspaceId,
      termsVersion: _expectedTermsVersion,
      privacyVersion: _expectedPrivacyVersion,
    );
    if (!_sessionActive || generation != _generation) return;
    switch (result) {
      case Success<LegalAcceptance>(value: final acceptance):
        _applyAcceptance(acceptance, fromSubmission: true);
      case FailureResult<LegalAcceptance>(failure: final failure):
        final incompatible =
            failure.code == 'TERMS_VERSION_INVALID' ||
            failure.code == 'PRIVACY_VERSION_INVALID';
        state = state.copyWith(
          status: incompatible
              ? LegalAcceptanceStatus.incompatible
              : LegalAcceptanceStatus.required,
          gateVisible: true,
          errorMessage: incompatible ? _incompatibleMessage : failure.message,
        );
    }
  }

  Future<void> _refresh({
    required bool showGate,
    required bool clearAcceptance,
  }) async {
    final workspaceId = _workspaceId;
    if (!_sessionActive || workspaceId == null) return;
    _accessPolicy.reset();
    if (!_configurationIsSafe) {
      state = LegalAcceptanceState(
        status: LegalAcceptanceStatus.incompatible,
        gateVisible: true,
        errorMessage:
            'Bản ứng dụng chưa cấu hình đầy đủ tài liệu pháp lý HTTPS hoặc phiên bản chính sách.',
      );
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      status: LegalAcceptanceStatus.loading,
      acceptedBoth: false,
      gateVisible: showGate,
      clearAcceptance: clearAcceptance,
      clearError: true,
    );
    final result = await _load(workspaceId: workspaceId);
    if (!_sessionActive || generation != _generation) return;
    switch (result) {
      case Success<LegalAcceptance>(value: final acceptance):
        _applyAcceptance(acceptance);
      case FailureResult<LegalAcceptance>(failure: final failure):
        state = state.copyWith(
          status: LegalAcceptanceStatus.error,
          gateVisible: true,
          errorMessage: failure.message,
        );
    }
  }

  void _applyAcceptance(
    LegalAcceptance acceptance, {
    bool fromSubmission = false,
  }) {
    final workspaceId = _workspaceId;
    if (workspaceId == null || acceptance.workspaceId.trim() != workspaceId) {
      _accessPolicy.reset();
      state = LegalAcceptanceState(
        status: LegalAcceptanceStatus.incompatible,
        acceptance: acceptance,
        gateVisible: true,
        errorMessage:
            'Máy chủ trả trạng thái chính sách cho workspace khác. Không thể mở quyền tạo nội dung an toàn.',
      );
      return;
    }
    if (!acceptance.matchesPublisherVersions(
      termsVersion: _expectedTermsVersion,
      privacyVersion: _expectedPrivacyVersion,
    )) {
      _accessPolicy.reset();
      state = LegalAcceptanceState(
        status: LegalAcceptanceStatus.incompatible,
        acceptance: acceptance,
        gateVisible: true,
        errorMessage: _incompatibleMessage,
      );
      return;
    }
    if (acceptance.isComplete) {
      _accessPolicy.markComplete();
      state = LegalAcceptanceState(
        status: LegalAcceptanceStatus.complete,
        acceptance: acceptance,
        gateVisible: false,
      );
      return;
    }
    _accessPolicy.reset();
    state = LegalAcceptanceState(
      status: LegalAcceptanceStatus.required,
      acceptance: acceptance,
      gateVisible: true,
      errorMessage: fromSubmission
          ? 'Máy chủ chưa xác nhận đầy đủ việc đồng ý. Vui lòng thử lại.'
          : null,
    );
  }

  void _handleAcceptanceRequired() {
    if (!_sessionActive) return;
    if (state.status == LegalAcceptanceStatus.loading ||
        state.status == LegalAcceptanceStatus.submitting) {
      state = state.copyWith(gateVisible: true);
      return;
    }
    unawaited(_refresh(showGate: true, clearAcceptance: true));
  }

  bool get _configurationIsSafe =>
      _legalLinksConfigured &&
      _expectedTermsVersion.isNotEmpty &&
      _expectedPrivacyVersion.isNotEmpty;

  String get _incompatibleMessage =>
      'Phiên bản chính sách của máy chủ không khớp tài liệu do ứng dụng công bố '
      '(Điều khoản $_expectedTermsVersion, Quyền riêng tư '
      '$_expectedPrivacyVersion). Không thể ghi nhận đồng ý an toàn.';

  @override
  void dispose() {
    _requiredSubscription.cancel();
    super.dispose();
  }
}
