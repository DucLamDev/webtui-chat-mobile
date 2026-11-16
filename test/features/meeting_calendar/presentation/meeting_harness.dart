import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/platform/external_url_launcher.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/meeting_calendar/application/meeting_calendar_providers.dart';
import 'package:webtui_chat/features/meeting_calendar/presentation/controllers/meeting_calendar_controllers.dart';
import 'package:webtui_chat/features/meeting_calendar/presentation/screens/meeting_detail_screen.dart';
import 'package:webtui_chat/features/meetings/application/meeting_providers.dart';
import 'package:webtui_chat/features/meetings/data/meeting_remote_data_source.dart';
import 'package:webtui_chat/features/meetings/domain/meeting_models.dart';

import '../meeting_calendar_fakes.dart';

final class FakeUrlLauncher implements ExternalUrlLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

/// Chỉ cấp token tham gia họp.
final class FakeMeetingApi implements MeetingApi {
  FakeMeetingApi({this.join});

  MeetingJoinInfo? join;
  final tokenRequests = <String>[];

  @override
  Future<MeetingJoinInfo> fetchJoinToken({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) async {
    tokenRequests.add('$channelId/$meetingId');
    return join ??
        const MeetingJoinInfo(
          provider: MeetingProviderKind.jitsi,
          serverUrl: 'https://meet.example.com/',
          room: 'phong-1',
          token: 'jwt-1',
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void phoneView(WidgetTester tester, {double height = 2000}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Router nhỏ: `/` là màn kiểm thử, chi tiết họp là màn thật, phòng chat chỉ
/// hiện chữ để biết đã mở tới đâu.
Widget meetingApp({
  required Widget home,
  FakeMeetingCalendarRepository? calendar,
  FakeMeetingConversations? conversations,
  FakeMeetingApi? meetingApi,
  FakeUrlLauncher? launcher,
  DateTime? now,
  Brightness brightness = Brightness.light,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/meetings/:id',
        builder: (_, state) => MeetingDetailScreen(
          workspaceId: state.uri.queryParameters['workspaceId'] ?? 'ws',
          channelId: state.uri.queryParameters['channelId'] ?? '',
          meetingId: state.pathParameters['id'] ?? '',
          now: now,
        ),
      ),
      GoRoute(
        path: '/conversations/:id',
        builder: (_, state) => Scaffold(
          body: Text(
            'phòng ${state.pathParameters['id']} '
            '${state.uri.queryParameters['title']}',
          ),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      meetingCalendarRepositoryProvider.overrideWithValue(
        calendar ?? FakeMeetingCalendarRepository(),
      ),
      conversationRepositoryProvider.overrideWithValue(
        conversations ?? FakeMeetingConversations(),
      ),
      meetingApiProvider.overrideWithValue(meetingApi ?? FakeMeetingApi()),
      externalUrlLauncherProvider.overrideWithValue(
        launcher ?? FakeUrlLauncher(),
      ),
      meetingTimezoneProvider.overrideWithValue('Asia/Ho_Chi_Minh'),
    ],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark
          ? WebTuiTheme.dark()
          : WebTuiTheme.light(),
      routerConfig: router,
    ),
  );
}
