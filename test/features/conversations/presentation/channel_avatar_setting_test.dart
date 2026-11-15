import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/channel_avatar_setting.dart';

ConversationSummary _channel({
  ConversationKind kind = ConversationKind.channel,
  ChannelVisibility visibility = ChannelVisibility.private,
  bool canManage = false,
}) {
  return ConversationSummary(
    id: 'ch',
    workspaceId: 'ws',
    channelId: 'ch',
    kind: kind,
    title: 'Nhóm',
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 15),
    channelVisibility: visibility,
    membershipStatus: MembershipStatus.active,
    canManage: canManage,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: WebTuiTheme.light(),
      home: Scaffold(body: ListView(children: [child])),
    ),
  );
}

void main() {
  final row = find.byKey(const ValueKey('channel-change-avatar'));

  testWidgets('thành viên nhóm thấy "Đổi ảnh nhóm", bấm được, vùng bấm ≥ 48', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      ChannelAvatarSetting(
        channel: _channel(),
        updating: false,
        onChange: () => taps++,
      ),
    );
    expect(find.text('Đổi ảnh nhóm'), findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    await tester.tap(row);
    expect(taps, 1);
  });

  testWidgets('kênh công khai không quản lý / chat 1-1: không có mục', (
    tester,
  ) async {
    await _pump(
      tester,
      ChannelAvatarSetting(
        channel: _channel(visibility: ChannelVisibility.public),
        updating: false,
        onChange: () {},
      ),
    );
    expect(find.text('Đổi ảnh nhóm'), findsNothing);

    await _pump(
      tester,
      ChannelAvatarSetting(
        channel: _channel(
          kind: ConversationKind.direct,
          visibility: ChannelVisibility.direct,
        ),
        updating: false,
        onChange: () {},
      ),
    );
    expect(find.text('Đổi ảnh nhóm'), findsNothing);
  });

  testWidgets('đang tải: hiện tiến trình, không bấm lại; có lỗi thì báo', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      ChannelAvatarSetting(
        channel: _channel(
          visibility: ChannelVisibility.public,
          canManage: true,
        ),
        updating: true,
        errorMessage: 'Ảnh tối đa 8 MB.',
        onChange: () => taps++,
      ),
    );
    expect(find.text('Đang tải ảnh lên...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Ảnh tối đa 8 MB.'), findsOneWidget);
    await tester.tap(row);
    expect(taps, 0);
  });
}
