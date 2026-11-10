import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/collaboration_document_history_use_cases.dart';
import '../../domain/entities/collaboration_document_version.dart';
import '../../domain/entities/collaboration_room.dart';

@immutable
final class CollaborationHistoryScope {
  const CollaborationHistoryScope({
    required this.workspaceId,
    required this.channelId,
    required this.kind,
  });

  final String workspaceId;
  final String channelId;

  /// `notes` hoặc `whiteboard`.
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is CollaborationHistoryScope &&
      other.workspaceId == workspaceId &&
      other.channelId == channelId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(workspaceId, channelId, kind);
}

@immutable
final class CollaborationHistoryState {
  const CollaborationHistoryState({
    this.versions = const [],
    this.loading = false,
    this.loaded = false,
    this.errorMessage,
    this.forbidden = false,
    this.selected,
    this.loadingVersion,
    this.previewError,
    this.restoring = false,
    this.restoreError,
  });

  final List<CollaborationDocumentVersion> versions;
  final bool loading;
  final bool loaded;
  final String? errorMessage;

  /// Máy chủ báo không có quyền xem lịch sử.
  final bool forbidden;

  /// Bản đang xem trước (đã tải nội dung).
  final CollaborationDocumentVersionDetail? selected;

  /// Số version đang tải nội dung để xem trước.
  final int? loadingVersion;
  final String? previewError;
  final bool restoring;
  final String? restoreError;

  CollaborationHistoryState copyWith({
    List<CollaborationDocumentVersion>? versions,
    bool? loading,
    bool? loaded,
    String? errorMessage,
    bool? forbidden,
    CollaborationDocumentVersionDetail? selected,
    int? loadingVersion,
    String? previewError,
    bool? restoring,
    String? restoreError,
    bool clearError = false,
    bool clearSelected = false,
    bool clearLoadingVersion = false,
    bool clearPreviewError = false,
    bool clearRestoreError = false,
  }) {
    return CollaborationHistoryState(
      versions: versions ?? this.versions,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      forbidden: forbidden ?? this.forbidden,
      selected: clearSelected ? null : selected ?? this.selected,
      loadingVersion: clearLoadingVersion
          ? null
          : loadingVersion ?? this.loadingVersion,
      previewError: clearPreviewError
          ? null
          : previewError ?? this.previewError,
      restoring: restoring ?? this.restoring,
      restoreError: clearRestoreError
          ? null
          : restoreError ?? this.restoreError,
    );
  }
}

final collaborationHistoryControllerProvider = StateNotifierProvider.autoDispose
    .family<
      CollaborationHistoryController,
      CollaborationHistoryState,
      CollaborationHistoryScope
    >((ref, scope) {
      return CollaborationHistoryController(
        scope: scope,
        listVersions: ref.watch(
          listCollaborationDocumentVersionsUseCaseProvider,
        ),
        loadVersion: ref.watch(loadCollaborationDocumentVersionUseCaseProvider),
        restoreVersion: ref.watch(
          restoreCollaborationDocumentVersionUseCaseProvider,
        ),
      )..load();
    });

/// Lịch sử phiên bản của một tài liệu cộng tác: danh sách, xem trước, khôi phục.
final class CollaborationHistoryController
    extends StateNotifier<CollaborationHistoryState> {
  CollaborationHistoryController({
    required this.scope,
    required ListCollaborationDocumentVersionsUseCase listVersions,
    required LoadCollaborationDocumentVersionUseCase loadVersion,
    required RestoreCollaborationDocumentVersionUseCase restoreVersion,
  }) : _listVersions = listVersions,
       _loadVersion = loadVersion,
       _restoreVersion = restoreVersion,
       super(const CollaborationHistoryState());

  final CollaborationHistoryScope scope;
  final ListCollaborationDocumentVersionsUseCase _listVersions;
  final LoadCollaborationDocumentVersionUseCase _loadVersion;
  final RestoreCollaborationDocumentVersionUseCase _restoreVersion;
  int _previewRequest = 0;

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true, forbidden: false);
    final result = await _listVersions.execute(
      workspaceId: scope.workspaceId,
      channelId: scope.channelId,
      kind: scope.kind,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        state = state.copyWith(versions: value, loading: false, loaded: true);
      case FailureResult(:final failure):
        state = state.copyWith(
          loading: false,
          loaded: true,
          errorMessage: failure.message,
          forbidden: failure.kind == FailureKind.forbidden,
        );
    }
  }

  Future<void> select(int version) async {
    final request = ++_previewRequest;
    state = state.copyWith(
      loadingVersion: version,
      clearSelected: true,
      clearPreviewError: true,
      clearRestoreError: true,
    );
    final result = await _loadVersion.execute(
      workspaceId: scope.workspaceId,
      channelId: scope.channelId,
      kind: scope.kind,
      version: version,
    );
    if (!mounted || request != _previewRequest) return;
    switch (result) {
      case Success(:final value):
        state = state.copyWith(selected: value, clearLoadingVersion: true);
      case FailureResult(:final failure):
        state = state.copyWith(
          previewError: failure.message,
          clearLoadingVersion: true,
        );
    }
  }

  void closePreview() {
    _previewRequest++;
    state = state.copyWith(
      clearSelected: true,
      clearLoadingVersion: true,
      clearPreviewError: true,
      clearRestoreError: true,
    );
  }

  /// Khôi phục bản đang xem; trả tài liệu mới khi thành công.
  Future<CollaborationDocument?> restoreSelected({
    required int expectedVersion,
  }) async {
    final selected = state.selected;
    if (selected == null || state.restoring) return null;
    state = state.copyWith(restoring: true, clearRestoreError: true);
    final result = await _restoreVersion.execute(
      workspaceId: scope.workspaceId,
      channelId: scope.channelId,
      kind: scope.kind,
      version: selected.version,
      expectedVersion: expectedVersion,
    );
    if (!mounted) return null;
    switch (result) {
      case Success(:final value):
        state = state.copyWith(restoring: false);
        return value;
      case FailureResult(:final failure):
        state = state.copyWith(restoring: false, restoreError: failure.message);
        return null;
    }
  }
}
