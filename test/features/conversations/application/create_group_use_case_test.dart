import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/create_group_use_case.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';

final _slugFormat = RegExp(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$');

void main() {
  group('suggestGroupSlug', () {
    test('bỏ dấu tiếng Việt kể cả đ, chữ thường, gạch nối, thêm hậu tố', () {
      final slug = suggestGroupSlug(
        'Đội Kế Hoạch  Tháng 12!',
        random: Random(1),
      );
      expect(slug, matches(RegExp(r'^doi-ke-hoach-thang-12-[a-z0-9]{5}$')));
      expect(slug, matches(_slugFormat));
    });

    test('ký tự lạ và tên rỗng vẫn cho slug hợp lệ', () {
      for (final name in ['', '   ', '!!!', '😀😀', '--']) {
        expect(
          suggestGroupSlug(name, random: Random(2)),
          matches(_slugFormat),
          reason: '"$name"',
        );
      }
      expect(suggestGroupSlug('', random: Random(2)), startsWith('nhom-'));
    });

    test('tên rất dài bị cắt và vẫn hợp lệ; hai lần gọi không trùng', () {
      final long = 'Một cái tên nhóm dài ${'rất ' * 30}';
      final a = suggestGroupSlug(long);
      expect(a.length, lessThanOrEqualTo(62));
      expect(a, matches(_slugFormat));
      expect(a, isNot(suggestGroupSlug(long)));
    });
  });

  group('CreateGroupUseCase', () {
    test('tạo nhóm riêng tư rồi thêm đúng từng người (bỏ trùng)', () async {
      final repo = _Repo();
      final result = await CreateGroupUseCase(repo, random: Random(3)).execute(
        workspaceId: 'ws',
        name: '  Nhóm A  ',
        description: ' mô tả ',
        memberIds: const ['u1', 'u2', 'u1'],
      );
      expect(repo.createdVisibility, ChannelVisibility.private);
      expect(repo.createdName, 'Nhóm A');
      expect(repo.createdDescription, 'mô tả');
      expect(repo.createdSlug, matches(_slugFormat));
      expect(repo.added, ['u1', 'u2']);
      expect(result.valueOrNull!.failedMemberIds, isEmpty);
    });

    test('lỗi một phần: nhóm vẫn được tạo, trả danh sách người lỗi', () async {
      final repo = _Repo(failFor: {'u2', 'u3'});
      final result = await CreateGroupUseCase(repo).execute(
        workspaceId: 'ws',
        name: 'Nhóm B',
        memberIds: const ['u1', 'u2', 'u3'],
      );
      final value = result.valueOrNull!;
      expect(value.channel.channelId, 'ch-1');
      expect(value.failedMemberIds, ['u2', 'u3']);
      expect(repo.added, ['u1', 'u2', 'u3']);
    });

    test('tên rỗng hoặc quá 80 ký tự: không gọi máy chủ', () async {
      final repo = _Repo();
      final useCase = CreateGroupUseCase(repo);
      final empty = await useCase.execute(workspaceId: 'ws', name: '  ');
      final long = await useCase.execute(
        workspaceId: 'ws',
        name: 'a' * (groupNameMaxLength + 1),
      );
      expect(empty, isA<FailureResult<CreateGroupResult>>());
      expect(long, isA<FailureResult<CreateGroupResult>>());
      expect(repo.createdName, isNull);
    });

    test('tạo nhóm lỗi thì không thêm ai', () async {
      final repo = _Repo(failCreate: true);
      final result = await CreateGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', name: 'Nhóm C', memberIds: const ['u1']);
      expect(result, isA<FailureResult<CreateGroupResult>>());
      expect(repo.added, isEmpty);
    });
  });
}

class _Repo implements ConversationRepository {
  _Repo({this.failFor = const {}, this.failCreate = false});

  final Set<String> failFor;
  final bool failCreate;
  String? createdName;
  String? createdSlug;
  String? createdDescription;
  ChannelVisibility? createdVisibility;
  final added = <String>[];

  @override
  Future<Result<ConversationSummary>> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) async {
    if (failCreate) {
      return const FailureResult(
        Failure(kind: FailureKind.server, message: 'Lỗi máy chủ'),
      );
    }
    createdName = name;
    createdSlug = slug;
    createdDescription = description;
    createdVisibility = visibility;
    return Success(
      ConversationSummary(
        id: 'ch-1',
        workspaceId: workspaceId,
        channelId: 'ch-1',
        kind: ConversationKind.channel,
        title: name,
        preview: '',
        updatedAt: DateTime.utc(2026, 11, 14),
        channelVisibility: visibility,
      ),
    );
  }

  @override
  Future<Result<ChannelMember>> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    added.add(userId);
    if (failFor.contains(userId)) {
      return const FailureResult(
        Failure(kind: FailureKind.server, message: 'Không thêm được'),
      );
    }
    return Success(
      ChannelMember(
        channelId: channelId,
        userId: userId,
        email: '$userId@example.com',
        username: userId,
        displayName: userId,
        status: 'active',
        joinedAt: DateTime.utc(2026, 11, 14),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
