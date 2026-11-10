import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/my_notes_use_cases.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/repositories/my_notes_repository.dart';
import 'my_notes_access_provider.dart';

/// Khoá của màn soạn: [noteId] null = ghi chú mới.
typedef MyNoteEditorKey = ({String workspaceId, String? noteId});

final myNoteEditorControllerProvider = StateNotifierProvider.autoDispose
    .family<MyNoteEditorController, MyNoteEditorState, MyNoteEditorKey>((
      ref,
      key,
    ) {
      return MyNoteEditorController(
        workspaceId: key.workspaceId,
        noteId: key.noteId,
        useCases: ref.watch(myNotesUseCasesProvider),
      )..start();
    });

const myNoteConflictMessage =
    'Ghi chú đã được sửa ở thiết bị khác nên bản của bạn chưa được lưu. '
    'Hãy sao chép phần vừa sửa nếu cần, rồi tải bản mới nhất.';

final class MyNoteEditorState {
  const MyNoteEditorState({
    this.note,
    this.folders = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.isDeleting = false,
    this.isOffline = false,
    this.featureDisabled = false,
    this.notFound = false,
    this.conflict = false,
    this.errorMessage,
    this.saveErrorMessage,
  });

  final MyNote? note;
  final List<MyNoteFolder> folders;
  final bool isLoading;
  final bool isSaving;
  final bool isDeleting;

  /// Đang xem bản lưu trên máy (không sửa được).
  final bool isOffline;
  final bool featureDisabled;
  final bool notFound;

  /// Máy chủ trả 409 `NOTE_VERSION_CONFLICT`.
  final bool conflict;

  /// Lỗi khi tải (thay cho nội dung).
  final String? errorMessage;

  /// Lỗi khi lưu / xoá (hiện kèm nội dung đang soạn).
  final String? saveErrorMessage;

  bool get isNew => note == null;

  bool get isBusy => isSaving || isDeleting;

  MyNoteEditorState copyWith({
    MyNote? note,
    List<MyNoteFolder>? folders,
    bool? isLoading,
    bool? isSaving,
    bool? isDeleting,
    bool? isOffline,
    bool? featureDisabled,
    bool? notFound,
    bool? conflict,
    String? errorMessage,
    bool clearError = false,
    String? saveErrorMessage,
    bool clearSaveError = false,
  }) {
    return MyNoteEditorState(
      note: note ?? this.note,
      folders: folders ?? this.folders,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isDeleting: isDeleting ?? this.isDeleting,
      isOffline: isOffline ?? this.isOffline,
      featureDisabled: featureDisabled ?? this.featureDisabled,
      notFound: notFound ?? this.notFound,
      conflict: conflict ?? this.conflict,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      saveErrorMessage: clearSaveError
          ? null
          : saveErrorMessage ?? this.saveErrorMessage,
    );
  }
}

/// Dữ liệu người dùng vừa soạn.
final class MyNoteDraft {
  const MyNoteDraft({
    required this.title,
    required this.body,
    this.tagsInput = '',
    this.pinned = false,
    this.folderId,
  });

  final String title;
  final String body;

  /// Tag gõ cách nhau bằng dấu phẩy.
  final String tagsInput;
  final bool pinned;

  /// null = gốc.
  final String? folderId;

  List<String> get tags => parseMyNoteTagInput(tagsInput);
}

final class MyNoteEditorController extends StateNotifier<MyNoteEditorState> {
  MyNoteEditorController({
    required String workspaceId,
    required String? noteId,
    required MyNotesUseCases useCases,
  }) : _workspaceId = workspaceId.trim(),
       _noteId = noteId?.trim(),
       _useCases = useCases,
       super(const MyNoteEditorState());

  @visibleForTesting
  factory MyNoteEditorController.forTesting({
    required MyNotesRepository repository,
    String workspaceId = 'workspace-1',
    String? noteId,
  }) {
    return MyNoteEditorController(
      workspaceId: workspaceId,
      noteId: noteId,
      useCases: MyNotesUseCases(repository),
    );
  }

  final String _workspaceId;
  final String? _noteId;
  final MyNotesUseCases _useCases;

  void start() {
    unawaited(load());
    unawaited(loadFolders());
  }

  Future<void> load() async {
    final noteId = state.note?.id ?? _noteId;
    if (noteId == null || noteId.isEmpty) return;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSaveError: true,
      notFound: false,
    );
    final result = await _useCases.getNote.execute(
      workspaceId: _workspaceId,
      noteId: noteId,
    );
    if (!mounted) return;
    switch (result) {
      case Success(value: final cached):
        state = state.copyWith(
          note: cached.value,
          isLoading: false,
          isOffline: cached.fromCache,
          conflict: false,
          featureDisabled: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          featureDisabled: isMyNotesFeatureDisabled(failure),
          notFound: failure.kind == FailureKind.notFound,
          errorMessage: failure.kind == FailureKind.notFound
              ? 'Ghi chú không còn tồn tại hoặc đã bị xoá.'
              : myNotesErrorText(failure),
        );
    }
  }

  Future<void> loadFolders() async {
    final result = await _useCases.listFolders.execute(_workspaceId);
    if (!mounted) return;
    if (result case Success(value: final cached)) {
      state = state.copyWith(folders: cached.value);
    }
  }

  /// Tải bản mới nhất sau khi bị xung đột phiên bản.
  Future<void> reloadLatest() => load();

  /// Tạo mới hoặc lưu thay đổi; trả ghi chú đã lưu (null khi lỗi).
  Future<MyNote?> save(MyNoteDraft draft) async {
    if (state.isBusy) return null;
    state = state.copyWith(isSaving: true, clearSaveError: true);
    final current = state.note;
    final Result<MyNote> result;
    if (current == null) {
      result = await _useCases.createNote.execute(
        workspaceId: _workspaceId,
        title: draft.title,
        body: draft.body,
        tags: draft.tags,
        pinned: draft.pinned,
        folderId: draft.folderId,
      );
    } else {
      final patch = _patchFor(current, draft);
      if (patch.isEmpty) {
        state = state.copyWith(isSaving: false);
        return current;
      }
      result = await _useCases.updateNote.execute(
        workspaceId: _workspaceId,
        noteId: current.id,
        version: current.version,
        patch: patch,
      );
    }
    if (!mounted) return null;
    switch (result) {
      case Success(value: final saved):
        state = state.copyWith(
          note: saved,
          isSaving: false,
          isOffline: false,
          conflict: false,
        );
        return saved;
      case FailureResult(failure: final failure):
        final conflict = isMyNoteVersionConflict(failure);
        state = state.copyWith(
          isSaving: false,
          conflict: conflict,
          featureDisabled: isMyNotesFeatureDisabled(failure),
          saveErrorMessage: conflict
              ? myNoteConflictMessage
              : myNotesErrorText(failure),
        );
        return null;
    }
  }

  /// Trả true khi đã xoá.
  Future<bool> delete() async {
    final note = state.note;
    if (note == null || state.isBusy) return false;
    state = state.copyWith(isDeleting: true, clearSaveError: true);
    final result = await _useCases.deleteNote.execute(
      workspaceId: _workspaceId,
      noteId: note.id,
    );
    if (!mounted) return result.isSuccess;
    switch (result) {
      case Success():
        state = state.copyWith(isDeleting: false);
        return true;
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isDeleting: false,
          saveErrorMessage: myNotesErrorText(failure),
        );
        return false;
    }
  }

  Future<bool> removeAttachment(String fileId) async {
    final note = state.note;
    if (note == null || state.isBusy) return false;
    final result = await _useCases.removeAttachment.execute(
      workspaceId: _workspaceId,
      noteId: note.id,
      fileId: fileId,
    );
    if (!mounted) return result.isSuccess;
    switch (result) {
      case Success():
        state = state.copyWith(
          note: note.copyWith(
            attachments: note.attachments
                .where((item) => item.fileId != fileId)
                .toList(growable: false),
          ),
        );
        return true;
      case FailureResult(failure: final failure):
        state = state.copyWith(saveErrorMessage: myNotesErrorText(failure));
        return false;
    }
  }
}

MyNotePatch _patchFor(MyNote current, MyNoteDraft draft) {
  final title = draft.title.trim();
  final tags = draft.tags;
  final folderId = draft.folderId?.trim();
  final targetFolder = folderId == null || folderId.isEmpty ? null : folderId;
  final folderChanged = targetFolder != current.folderId;
  return MyNotePatch(
    title: title != current.title ? title : null,
    body: draft.body != current.body ? draft.body : null,
    tags: listEquals(tags, current.tags) ? null : tags,
    pinned: draft.pinned != current.pinned ? draft.pinned : null,
    folderId: folderChanged ? targetFolder : null,
    moveToRoot: folderChanged && targetFolder == null,
  );
}
