import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/my_notes_use_cases.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/repositories/my_notes_repository.dart';
import 'my_notes_access_provider.dart';

final myNotesListControllerProvider = StateNotifierProvider.autoDispose
    .family<MyNotesListController, MyNotesListState, String>((
      ref,
      workspaceId,
    ) {
      return MyNotesListController(
        workspaceId: workspaceId,
        useCases: ref.watch(myNotesUseCasesProvider),
      )..start();
    });

final class MyNotesListState {
  const MyNotesListState({
    this.filter = const MyNoteFilter(),
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
    this.hasLoaded = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isOffline = false,
    this.cachedAt,
    this.featureDisabled = false,
    this.errorMessage,
    this.loadMoreErrorMessage,
    this.folders = const [],
    this.tags = const [],
  });

  final MyNoteFilter filter;
  final List<MyNoteSummary> items;
  final String? nextCursor;
  final bool hasMore;
  final bool hasLoaded;
  final bool isLoading;
  final bool isLoadingMore;

  /// Đang xem bản lưu trên máy vì không gọi được máy chủ.
  final bool isOffline;
  final DateTime? cachedAt;

  /// Máy chủ trả `FEATURE_DISABLED`.
  final bool featureDisabled;
  final String? errorMessage;
  final String? loadMoreErrorMessage;
  final List<MyNoteFolder> folders;
  final List<MyNoteTag> tags;

  List<MyNoteFolderNode> get folderTree => buildMyNoteFolderTree(folders);

  MyNoteFolder? folderById(String? id) {
    if (id == null) return null;
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  MyNotesListState copyWith({
    MyNoteFilter? filter,
    List<MyNoteSummary>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? hasMore,
    bool? hasLoaded,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isOffline,
    DateTime? cachedAt,
    bool? featureDisabled,
    String? errorMessage,
    bool clearError = false,
    String? loadMoreErrorMessage,
    bool clearLoadMoreError = false,
    List<MyNoteFolder>? folders,
    List<MyNoteTag>? tags,
  }) {
    return MyNotesListState(
      filter: filter ?? this.filter,
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isOffline: isOffline ?? this.isOffline,
      cachedAt: cachedAt ?? this.cachedAt,
      featureDisabled: featureDisabled ?? this.featureDisabled,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      loadMoreErrorMessage: clearLoadMoreError
          ? null
          : loadMoreErrorMessage ?? this.loadMoreErrorMessage,
      folders: folders ?? this.folders,
      tags: tags ?? this.tags,
    );
  }
}

/// Danh sách My Note: lọc thư mục / tag / ghim, tìm, cuộn tải thêm, quản lý
/// thư mục. Mất mạng thì hiện bản lưu trên máy và không cho sửa.
final class MyNotesListController extends StateNotifier<MyNotesListState> {
  MyNotesListController({
    required String workspaceId,
    required MyNotesUseCases useCases,
    MyNotesListState initialState = const MyNotesListState(),
  }) : _workspaceId = workspaceId.trim(),
       _useCases = useCases,
       super(initialState);

  @visibleForTesting
  factory MyNotesListController.forTesting({
    required MyNotesRepository repository,
    String workspaceId = 'workspace-1',
  }) {
    return MyNotesListController(
      workspaceId: workspaceId,
      useCases: MyNotesUseCases(repository),
    );
  }

  final String _workspaceId;
  final MyNotesUseCases _useCases;
  int _generation = 0;

  String get workspaceId => _workspaceId;

  void start() {
    unawaited(refresh());
  }

  Future<void> refresh() async {
    await Future.wait([load(), loadFolders(), loadTags()]);
  }

  Future<void> load() async {
    final generation = ++_generation;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      clearLoadMoreError: true,
    );
    final result = await _useCases.listNotes.execute(
      workspaceId: _workspaceId,
      filter: state.filter,
    );
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final cached):
        state = state.copyWith(
          items: sortMyNoteSummaries(cached.value.notes),
          nextCursor: cached.value.nextCursor,
          clearNextCursor: cached.value.nextCursor == null,
          hasMore: cached.value.hasMore && !cached.fromCache,
          hasLoaded: true,
          isLoading: false,
          isOffline: cached.fromCache,
          cachedAt: cached.cachedAt,
          featureDisabled: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoading: false,
          hasLoaded: true,
          featureDisabled: isMyNotesFeatureDisabled(failure),
          errorMessage: myNotesErrorText(failure),
        );
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (!state.hasMore ||
        cursor == null ||
        state.isLoading ||
        state.isLoadingMore ||
        state.isOffline) {
      return;
    }
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true, clearLoadMoreError: true);
    final result = await _useCases.listNotes.execute(
      workspaceId: _workspaceId,
      filter: state.filter,
      cursor: cursor,
    );
    if (!mounted || generation != _generation) return;
    switch (result) {
      case Success(value: final cached):
        final known = {for (final item in state.items) item.id};
        state = state.copyWith(
          items: [
            ...state.items,
            ...cached.value.notes.where((item) => !known.contains(item.id)),
          ],
          nextCursor: cached.value.nextCursor,
          clearNextCursor: cached.value.nextCursor == null,
          hasMore: cached.value.hasMore,
          isLoadingMore: false,
        );
      case FailureResult(failure: final failure):
        state = state.copyWith(
          isLoadingMore: false,
          loadMoreErrorMessage: myNotesErrorText(failure),
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

  Future<void> loadTags() async {
    final result = await _useCases.listTags.execute(_workspaceId);
    if (!mounted) return;
    if (result case Success(value: final cached)) {
      state = state.copyWith(tags: cached.value);
    }
  }

  Future<void> setQuery(String query) {
    final clean = query.trim();
    if (clean == state.filter.query) return Future.value();
    return _applyFilter(state.filter.copyWith(query: clean));
  }

  /// [folderId] null = mọi thư mục, [myNoteRootFolderFilter] = gốc.
  Future<void> setFolder(String? folderId) {
    return _applyFilter(
      state.filter.copyWith(folderId: folderId, clearFolder: folderId == null),
    );
  }

  Future<void> setTag(String? tag) {
    return _applyFilter(state.filter.copyWith(tag: tag, clearTag: tag == null));
  }

  Future<void> setPinnedOnly(bool pinnedOnly) {
    return _applyFilter(state.filter.copyWith(pinnedOnly: pinnedOnly));
  }

  Future<void> _applyFilter(MyNoteFilter filter) {
    if (filter == state.filter) return Future.value();
    state = state.copyWith(filter: filter);
    return load();
  }

  /// Trả câu lỗi (null = thành công).
  Future<String?> togglePin(MyNoteSummary note) async {
    final result = await _useCases.updateNote.execute(
      workspaceId: _workspaceId,
      noteId: note.id,
      version: note.version,
      patch: MyNotePatch(pinned: !note.pinned),
    );
    if (!mounted) return null;
    switch (result) {
      case Success(value: final updated):
        upsertNote(updated);
        return null;
      case FailureResult(failure: final failure):
        if (isMyNoteVersionConflict(failure)) {
          unawaited(load());
          return 'Ghi chú vừa được sửa ở nơi khác. Danh sách đã tải lại, '
              'hãy thử lại.';
        }
        return myNotesErrorText(failure);
    }
  }

  Future<String?> deleteNote(MyNoteSummary note) async {
    final result = await _useCases.deleteNote.execute(
      workspaceId: _workspaceId,
      noteId: note.id,
    );
    if (!mounted) return null;
    switch (result) {
      case Success():
        removeNote(note.id);
        unawaited(loadFolders());
        unawaited(loadTags());
        return null;
      case FailureResult(failure: final failure):
        return myNotesErrorText(failure);
    }
  }

  Future<String?> createFolder(String name, {String? parentId}) async {
    final result = await _useCases.createFolder.execute(
      workspaceId: _workspaceId,
      name: name,
      parentId: parentId,
      existingFolders: state.folders,
    );
    if (!mounted) return null;
    switch (result) {
      case Success():
        await loadFolders();
        return null;
      case FailureResult(failure: final failure):
        return myNotesErrorText(failure);
    }
  }

  Future<String?> renameFolder(String folderId, String name) async {
    final result = await _useCases.renameFolder.execute(
      workspaceId: _workspaceId,
      folderId: folderId,
      name: name,
    );
    if (!mounted) return null;
    switch (result) {
      case Success():
        await loadFolders();
        return null;
      case FailureResult(failure: final failure):
        return myNotesErrorText(failure);
    }
  }

  /// Ghi chú trong thư mục bị xoá chuyển về gốc (máy chủ làm).
  Future<String?> deleteFolder(String folderId) async {
    final result = await _useCases.deleteFolder.execute(
      workspaceId: _workspaceId,
      folderId: folderId,
    );
    if (!mounted) return null;
    switch (result) {
      case Success():
        if (state.filter.folderId == folderId) {
          state = state.copyWith(
            filter: state.filter.copyWith(clearFolder: true),
          );
        }
        await Future.wait([loadFolders(), load()]);
        return null;
      case FailureResult(failure: final failure):
        if (failure.code == 'NOTE_FOLDER_HAS_CHILDREN') {
          return 'Thư mục còn thư mục con. Hãy xoá hoặc chuyển thư mục con '
              'trước.';
        }
        return myNotesErrorText(failure);
    }
  }

  /// Cập nhật danh sách sau khi tạo / sửa ghi chú ở màn khác.
  void upsertNote(MyNote note) {
    final summary = note.toSummary();
    final exists = state.items.any((item) => item.id == summary.id);
    final matches = _matchesFilter(summary, state.filter);
    final items = [
      for (final item in state.items)
        if (item.id != summary.id) item,
      if (matches && (exists || state.filter.query.isEmpty)) summary,
    ];
    state = state.copyWith(items: sortMyNoteSummaries(items));
    unawaited(loadTags());
    unawaited(loadFolders());
  }

  void removeNote(String noteId) {
    state = state.copyWith(
      items: state.items
          .where((item) => item.id != noteId)
          .toList(growable: false),
    );
  }
}

bool _matchesFilter(MyNoteSummary note, MyNoteFilter filter) {
  final folder = filter.folderId;
  if (folder == myNoteRootFolderFilter && note.folderId != null) return false;
  if (folder != null &&
      folder != myNoteRootFolderFilter &&
      note.folderId != folder) {
    return false;
  }
  final tag = filter.tag;
  if (tag != null && !note.tags.contains(tag)) return false;
  if (filter.pinnedOnly && !note.pinned) return false;
  return true;
}
