import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_presence.dart';

/// Lỗi 17/11: Bùi Tú Thiên ở danh sách hội thoại không có chấm (offline) nhưng
/// trong chi tiết nhóm lại có chấm xanh. Chi tiết nhóm từng vẽ chấm theo trạng
/// thái thành viên nhóm (`active`), không theo hiện diện.
void main() {
  final beat = DateTime.utc(2026, 11, 17, 3, 30);
  PresenceSummary presence(String userId, ConversationPresence status) =>
      PresenceSummary(userId: userId, status: status, lastHeartbeatAt: beat);

  test('gộp nhiều thiết bị: online thắng away, away thắng offline', () {
    final merged = presenceByUser([
      presence('thien', ConversationPresence.offline),
      presence('thien', ConversationPresence.online),
      presence('lam', ConversationPresence.offline),
      presence('lam', ConversationPresence.away),
      presence('tien', ConversationPresence.offline),
    ]);

    expect(merged['thien'], ConversationPresence.online);
    expect(merged['lam'], ConversationPresence.away);
    expect(merged['tien'], ConversationPresence.offline);
  });

  test('chấm thành viên nhóm theo hiện diện thật, chỉ xanh khi online', () {
    expect(
      memberPresenceStatus(ConversationPresence.online),
      WebTuiPresenceStatus.online,
    );
    expect(memberPresenceStatus(ConversationPresence.away), isNull);
    expect(memberPresenceStatus(ConversationPresence.offline), isNull);
    expect(
      memberPresenceStatus(null),
      isNull,
      reason: 'không có dữ liệu hiện diện thì không vẽ chấm',
    );
  });

  test('nguồn hiện diện chung đọc GET /presence và gộp theo người', () async {
    final repository = _PresenceRepository(
      Success([
        presence('thien', ConversationPresence.offline),
        presence('lam', ConversationPresence.online),
      ]),
    );
    final container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      workspacePresenceProvider('ws-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);

    final value = await container.read(
      workspacePresenceProvider('ws-1').future,
    );

    expect(repository.workspaceIds, ['ws-1']);
    expect(value, {
      'thien': ConversationPresence.offline,
      'lam': ConversationPresence.online,
    });
  });

  test('lỗi mạng lần đầu: chưa có giá trị (không vẽ chấm nhầm)', () async {
    final repository = _PresenceRepository(
      const FailureResult(
        Failure(kind: FailureKind.network, message: 'Mất kết nối.'),
      ),
    );
    final container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      workspacePresenceProvider('ws-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(repository.workspaceIds, ['ws-1']);
    expect(
      container.read(workspacePresenceProvider('ws-1')).valueOrNull,
      isNull,
    );
  });
}

final class _PresenceRepository implements ConversationRepository {
  _PresenceRepository(this._result);

  final Result<List<PresenceSummary>> _result;
  final workspaceIds = <String>[];

  @override
  Future<Result<List<PresenceSummary>>> listPresence({
    required String workspaceId,
  }) async {
    workspaceIds.add(workspaceId);
    return _result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
