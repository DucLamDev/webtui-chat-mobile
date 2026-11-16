import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/auth/data/dto/auth_dto.dart';
import 'package:webtui_chat/features/conversations/data/datasources/conversation_remote_data_source.dart';
import 'package:webtui_chat/features/profile/data/dto/profile_dto.dart';

void main() {
  test('chat 1-1: đọc giới tính người đối diện, thiếu thì null', () async {
    final remote = ConversationRemoteDataSource(
      _Api({
        'data': {
          'direct_conversations': [
            {
              'id': 'd1',
              'channel_id': 'c1',
              'participants': [
                {'user_id': 'u2', 'display_name': 'Lan', 'gender': 'female'},
              ],
            },
            {
              'id': 'd2',
              'channel_id': 'c2',
              'peer_gender': 'male',
              'participants': [
                {'user_id': 'u3', 'display_name': 'Nam'},
              ],
            },
            {
              'id': 'd3',
              'channel_id': 'c3',
              'participants': [
                {'user_id': 'u4', 'display_name': 'An'},
              ],
            },
          ],
        },
      }),
    );
    final list = await remote.listDirectConversations(workspaceId: 'w');
    expect(list.map((c) => c.gender), ['female', 'male', null]);
  });

  test('danh bạ và thành viên workspace đọc gender', () async {
    final contacts = await ConversationRemoteDataSource(
      _Api({
        'data': {
          'contacts': [
            {'id': 'u1', 'display_name': 'A', 'gender': 'unspecified'},
            {'id': 'u2', 'display_name': 'B'},
          ],
        },
      }),
    ).listContacts();
    expect(contacts.map((c) => c.gender), ['unspecified', null]);

    final members = await ConversationRemoteDataSource(
      _Api({
        'data': {
          'members': [
            {'user_id': 'u1', 'display_name': 'A', 'gender': 'male'},
          ],
        },
      }),
    ).listWorkspaceMembers(workspaceId: 'w');
    expect(members.single.gender, 'male');
  });

  test('DTO người dùng hiện tại và hồ sơ đọc gender', () {
    expect(
      AuthUserDto.fromJson({'id': 'u', 'gender': 'female'}).toDomain().gender,
      'female',
    );
    expect(AuthUserDto.fromJson({'id': 'u'}).toDomain().gender, isNull);
    expect(
      UserProfileDto.fromJson({'id': 'u', 'gender': 'male'}).toDomain().gender,
      'male',
    );
  });
}

final class _Api implements ApiTransport {
  _Api(this.body);

  final Object body;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: body as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
