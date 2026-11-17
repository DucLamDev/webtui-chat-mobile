import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/my_notes_use_cases.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/my_note_editor_text.dart';
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

String get myNoteConflictMessage => tr(
  'Ghi chú vừa được sửa ở thiết bị khác nên phần bạn đang soạn chưa được lưu. Chọn giữ bản của bạn (ghi đè) hoặc tải bản mới nhất.',
  'This note was just edited on another device, so what you are writing hasn\'t been saved. Keep your version (overwrite) or load the latest one.',
);

/// Thời gian chờ sau lần gõ cuối rồi mới tự lưu.
const myNoteAutosaveDelay = Duration(milliseconds: 900);

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
    this.uploadingCount = 0,
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

  /// Máy chủ trả 409 `NOTE_VERSION_CONFLICT`: dừng tự lưu tới khi người dùng
  /// chọn giữ bản của mình hoặc tải bản mới nhất.
  final bool conflict;

  /// Số tệp đang tải lên để gắn vào ghi chú.
  final int uploadingCount;

  /// Lỗi khi tải (thay cho nội dung).
  final String? errorMessage;

  /// Lỗi khi lưu / xoá / đính kèm (hiện kèm nội dung đang soạn).
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
    int? uploadingCount,
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
      uploadingCount: uploadingCount ?? this.uploadingCount,
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
    this.tags = const [],
    this.pinned = false,
    this.folderId,
  });

  /// Từ văn bản ô soạn kiểu iPhone: dòng đầu là tiêu đề; tag = tag gõ trong
  /// văn bản (`#tag`) cộng [otherTags] (tag đặt từ trước, không nằm trong chữ).
  factory MyNoteDraft.fromEditorText(
    String text, {
    List<String> otherTags = const [],
    bool pinned = false,
    String? folderId,
  }) {
    final parts = splitMyNoteEditorText(text);
    return MyNoteDraft(
      title: parts.title,
      body: parts.body,
      tags: myNoteEditorTags(text, otherTags),
      pinned: pinned,
      folderId: folderId,
    );
  }

  final String title;
  final String body;
  final List<String> tags;
  final bool pinned;

  /// null = gốc.
  final String? folderId;

  /// Không có chữ nào: máy chủ không nhận ghi chú rỗng nên không lưu.
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;
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

  Timer? _autosaveTimer;
  MyNoteDraft? _pendingDraft;
  Future<MyNote?>? _inFlight;

  /// Còn chữ chưa gửi lên máy chủ (đang chờ hẹn giờ hoặc đang lưu).
  bool get hasPendingChanges => _pendingDraft != null || _inFlight != null;

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
              ? tr(
                  'Ghi chú không còn tồn tại hoặc đã bị xoá.',
                  'This note no longer exists or was deleted.',
                )
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

  /// Tải bản mới nhất (bỏ phần đang soạn) sau khi bị xung đột phiên bản.
  Future<void> reloadLatest() {
    _cancelPending();
    return load();
  }

  /// Hẹn tự lưu sau [delay] kể từ lần gọi cuối (gõ liên tục thì dời tiếp).
  void scheduleAutosave(
    MyNoteDraft draft, {
    Duration delay = myNoteAutosaveDelay,
  }) {
    _pendingDraft = draft;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(delay, () => unawaited(flushAutosave()));
  }

  /// Lưu ngay bản nháp đang chờ (rời màn, ẩn bàn phím, app vào nền). Trả true
  /// khi không còn gì chưa lưu; false khi không lưu được (xung đột, lỗi mạng,
  /// ngoại tuyến) — bản nháp vẫn giữ để thử lại.
  Future<bool> flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    while (_inFlight != null) {
      await _inFlight;
    }
    if (!mounted) return false;
    final draft = _pendingDraft;
    if (draft == null) return true;
    if (state.conflict || state.isOffline || state.isDeleting) return false;
    if (draft.isEmpty) {
      // Máy chủ không nhận ghi chú rỗng: giữ bản đã lưu, không gửi.
      _pendingDraft = null;
      return true;
    }
    _pendingDraft = null;
    final future = save(draft);
    _inFlight = future;
    final saved = await future;
    _inFlight = null;
    if (saved == null && mounted && !state.conflict && _pendingDraft == null) {
      // Lỗi mạng: giữ bản nháp để lần sau thử lại.
      _pendingDraft = draft;
    }
    return saved != null && _pendingDraft == null;
  }

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
          // Máy chủ trả ghi chú không kèm tệp đính kèm khi sửa: giữ danh sách
          // đã có để lưới ảnh không nháy mất.
          note: saved.attachments.isEmpty && current != null
              ? saved.copyWith(attachments: current.attachments)
              : saved,
          isSaving: false,
          isOffline: false,
          conflict: false,
        );
        return state.note;
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

  /// Xung đột phiên bản, người dùng chọn "Giữ bản của tôi": lấy số phiên bản
  /// mới nhất trên máy chủ rồi ghi đè bằng [draft].
  Future<MyNote?> saveOverwriting(MyNoteDraft draft) async {
    final current = state.note;
    if (current == null || state.isBusy) return null;
    _cancelPending();
    state = state.copyWith(isSaving: true, clearSaveError: true);
    final latest = await _useCases.getNote.execute(
      workspaceId: _workspaceId,
      noteId: current.id,
    );
    if (!mounted) return null;
    switch (latest) {
      case Success(value: final cached) when !cached.fromCache:
        state = state.copyWith(
          note: cached.value.copyWith(attachments: current.attachments),
          isSaving: false,
          conflict: false,
        );
        if (draft.isEmpty) return state.note;
        return save(draft);
      case Success():
        state = state.copyWith(
          isSaving: false,
          saveErrorMessage: tr(
            'Chưa kết nối được máy chủ. Thử lại khi có mạng.',
            'Can\'t reach the server. Try again when you\'re online.',
          ),
        );
        return null;
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isSaving: false,
          saveErrorMessage: myNotesErrorText(failure),
        );
        return null;
    }
  }

  /// Trả true khi đã xoá.
  Future<bool> delete() async {
    final note = state.note;
    if (note == null || state.isBusy) return false;
    _cancelPending();
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

  /// Tải [files] lên rồi gắn vào ghi chú. Ghi chú mới chưa lưu thì lưu trước
  /// bằng [draftIfNew] (phải có chữ). Trả số tệp gắn được.
  Future<int> addAttachments(
    List<MyNoteLocalFile> files, {
    required MyNoteDraft draftIfNew,
  }) async {
    if (files.isEmpty || state.isOffline || state.conflict) return 0;
    var note = state.note;
    if (note == null) {
      if (draftIfNew.isEmpty) return 0;
      _cancelPending();
      note = await save(draftIfNew);
      if (note == null || !mounted) return 0;
    }
    var added = 0;
    state = state.copyWith(
      uploadingCount: state.uploadingCount + files.length,
      clearSaveError: true,
    );
    for (final file in files) {
      final result = await _useCases.attachLocalFile.execute(
        workspaceId: _workspaceId,
        noteId: note.id,
        file: file,
      );
      if (!mounted) return added;
      switch (result) {
        case Success(value: final attachment):
          added++;
          final latest = state.note ?? note;
          state = state.copyWith(
            note: latest.copyWith(
              attachments: [...latest.attachments, attachment],
            ),
            uploadingCount: state.uploadingCount - 1,
          );
        case FailureResult(failure: final failure):
          state = state.copyWith(
            uploadingCount: state.uploadingCount - 1,
            saveErrorMessage: myNotesErrorText(failure),
          );
      }
    }
    return added;
  }

  Future<bool> removeAttachment(String fileId) async {
    final note = state.note;
    if (note == null || state.isDeleting) return false;
    final result = await _useCases.removeAttachment.execute(
      workspaceId: _workspaceId,
      noteId: note.id,
      fileId: fileId,
    );
    if (!mounted) return result.isSuccess;
    switch (result) {
      case Success():
        final latest = state.note ?? note;
        final remaining = latest.attachments
            .where((item) => item.fileId != fileId)
            .toList(growable: false);
        state = state.copyWith(note: latest.copyWith(attachments: remaining));
        return true;
      case FailureResult(failure: final failure):
        state = state.copyWith(saveErrorMessage: myNotesErrorText(failure));
        return false;
    }
  }

  void _cancelPending() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _pendingDraft = null;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    super.dispose();
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
