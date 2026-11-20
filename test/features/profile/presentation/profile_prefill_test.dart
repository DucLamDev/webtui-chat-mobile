import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/profile/application/use_cases/profile_use_cases.dart';
import 'package:webtui_chat/features/profile/domain/entities/user_profile.dart';
import 'package:webtui_chat/features/profile/domain/repositories/avatar_repository.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';
import 'package:webtui_chat/features/profile/presentation/controllers/profile_controller.dart';
import 'package:webtui_chat/features/profile/presentation/screens/profile_screen.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  ProfileController build(_Repo repo) => ProfileController(
    loadProfileUseCase: LoadProfileUseCase(repo),
    updateProfileUseCase: UpdateProfileUseCase(repo),
    changeAvatarUseCase: ChangeAvatarUseCase(
      pickerRepository: _Unused(),
      uploadRepository: _Unused(),
      profileRepository: repo,
      workspaceSessionRepository: _Unused(),
    ),
  );

  Future<void> open(WidgetTester tester, ProfileController c) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileControllerProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String firstFieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  testWidgets('hồ sơ đã nạp sẵn: ô tên có đúng tên, lưu không gửi tên rỗng', (
    tester,
  ) async {
    final repo = _Repo();
    final c = build(repo);
    await c.load();
    await open(tester, c);

    expect(firstFieldText(tester), 'Nguyễn An');
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    expect(repo.sent, ['Nguyễn An']);
  });

  testWidgets('chưa có hồ sơ: nút lưu bị chặn, nạp xong thì điền ô', (
    tester,
  ) async {
    final repo = _Repo(gate: Completer<void>());
    final c = build(repo);
    unawaited(c.load());
    await open(tester, c);
    await tester.tap(find.byIcon(Icons.check_rounded), warnIfMissed: false);
    await tester.pump();
    expect(repo.sent, isEmpty);

    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(firstFieldText(tester), 'Nguyễn An');
  });

  testWidgets('tải lại hồ sơ không đè chữ đang sửa', (tester) async {
    final repo = _Repo();
    final c = build(repo);
    await c.load();
    await open(tester, c);
    await tester.enterText(find.byType(TextField).first, 'Tên mới');
    await c.load();
    await tester.pumpAndSettle();
    expect(firstFieldText(tester), 'Tên mới');
  });
}

final class _Repo implements ProfileRepository {
  _Repo({this.gate});

  final Completer<void>? gate;
  final sent = <String>[];

  final _profile = const UserProfile(
    id: 'u-me',
    email: 'me@example.com',
    username: 'me',
    displayName: 'Nguyễn An',
    status: 'active',
    locale: 'vi',
    timezone: 'Asia/Ho_Chi_Minh',
  );

  @override
  Future<Result<UserProfile>> me() async {
    await gate?.future;
    return Success(_profile);
  }

  @override
  Future<Result<UserProfile>> updateMe(UpdateProfileCommand command) async {
    sent.add(command.displayName ?? '');
    return Success(_profile);
  }
}

final class _Unused
    implements
        AvatarPickerRepository,
        AvatarUploadRepository,
        WorkspaceSessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
