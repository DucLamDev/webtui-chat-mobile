import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../data/ide_connection.dart';

/// Trạng thái nối IDE (giá trị hiện tại rồi các thay đổi sau).
final ideLinkStatusProvider = StreamProvider.autoDispose<IdeLinkStatus>((
  ref,
) async* {
  final connection = ref.watch(ideConnectionProvider);
  yield connection.status;
  yield* connection.statuses;
});

/// Một phiên AI trong danh sách `ai.sessions`.
final class IdeAiSessionItem {
  const IdeAiSessionItem({
    required this.key,
    required this.kind,
    required this.project,
    required this.title,
    required this.status,
    this.worktree = '',
    this.updatedAt,
  });

  final String key;
  final String kind;
  final String project;
  final String worktree;
  final String title;
  final String status;
  final DateTime? updatedAt;

  static IdeAiSessionItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    final key = s('session_key');
    if (key.isEmpty) return null;
    return IdeAiSessionItem(
      key: key,
      kind: s('kind'),
      project: s('project'),
      worktree: s('worktree'),
      title: s('title'),
      status: s('status'),
      updatedAt: DateTime.tryParse(s('updated_at'))?.toLocal(),
    );
  }
}

List<IdeAiSessionItem> parseIdeAiSessions(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [for (final e in items) ?IdeAiSessionItem.tryParse(e)];
}

/// Danh sách phiên AI; tải lại khi nối lại được (phase ready).
final ideAiSessionsProvider =
    FutureProvider.autoDispose<List<IdeAiSessionItem>>((ref) async {
      final phase = ref.watch(
        ideLinkStatusProvider.select((v) => v.valueOrNull?.phase),
      );
      if (phase != IdeLinkPhase.ready) return const [];
      final data = await ref
          .read(ideRpcClientProvider)
          .call('ai.sessions', const {});
      return parseIdeAiSessions(data);
    });
