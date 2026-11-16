import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/components/webtui_person_silhouette.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/profile/application/use_cases/profile_use_cases.dart';
import 'package:webtui_chat/features/profile/domain/entities/user_profile.dart';
import 'package:webtui_chat/features/profile/domain/repositories/avatar_repository.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';
import 'package:webtui_chat/features/profile/presentation/controllers/profile_controller.dart';
import 'package:webtui_chat/features/profile/presentation/screens/profile_screen.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  Future<_Repo> pump(WidgetTester tester, _Repo repo) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileControllerProvider.overrideWith(
            (ref) => ProfileController(
              loadProfileUseCase: LoadProfileUseCase(repo),
              updateProfileUseCase: UpdateProfileUseCase(repo),
              changeAvatarUseCase: ChangeAvatarUseCase(
                pickerRepository: _Unused(),
                uploadRepository: _Unused(),
                profileRepository: repo,
                workspaceSessionRepository: _Unused(),
              ),
            )..load(),
          ),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Set<String> selected(WidgetTester tester) => tester
      .widget<SegmentedButton<String>>(
        find.byKey(const Key('profile_gender_field')),
      )
      .selected;

  testWidgets('chưa chọn: không lựa chọn nào đánh dấu, chọn thì lưu ngay', (
    tester,
  ) async {
    final repo = await pump(tester, _Repo());
    expect(selected(tester), isEmpty);
    expect(
      tester.widget<WebTuiAvatar>(find.byType(WebTuiAvatar)).gender,
      WebTuiAvatarGender.neutral,
    );

    await tester.tap(find.text('Nữ'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['female']);
    expect(selected(tester), {'female'});
    // Ảnh đại diện của mình đổi theo ngay sau khi lưu.
    expect(
      tester.widget<WebTuiAvatar>(find.byType(WebTuiAvatar)).gender,
      WebTuiAvatarGender.female,
    );
    expect(find.byType(WebTuiPersonSilhouette), findsOneWidget);
  });

  testWidgets('lưu lỗi: báo lỗi và giữ giá trị cũ', (tester) async {
    final repo = await pump(tester, _Repo(gender: 'male', fail: true));
    expect(selected(tester), {'male'});

    await tester.tap(find.text('Không muốn nói'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['unspecified']);
    expect(selected(tester), {'male'});
    expect(find.text('Máy chủ từ chối'), findsOneWidget);
    expect(
      tester.widget<WebTuiAvatar>(find.byType(WebTuiAvatar)).gender,
      WebTuiAvatarGender.male,
    );
  });

  test('use case từ chối giới tính lạ trước khi gọi máy chủ', () async {
    final repo = _Repo();
    final result = await UpdateProfileUseCase(
      repo,
    ).execute(const UpdateProfileCommand(gender: 'robot'));
    expect(result, isA<FailureResult<UserProfile>>());
    expect(repo.sent, isEmpty);
  });
}

final class _Repo implements ProfileRepository {
  _Repo({this.gender, this.fail = false});

  String? gender;
  final bool fail;
  final sent = <String>[];

  UserProfile get _profile => UserProfile(
    id: 'u-me',
    email: 'me@example.com',
    username: 'me',
    displayName: 'Tôi',
    status: 'active',
    locale: 'vi',
    timezone: 'Asia/Ho_Chi_Minh',
    gender: gender,
  );

  @override
  Future<Result<UserProfile>> me() async => Success(_profile);

  @override
  Future<Result<UserProfile>> updateMe(UpdateProfileCommand command) async {
    sent.add(command.gender ?? '');
    if (fail) {
      return FailureResult(
        const Failure(kind: FailureKind.server, message: 'Máy chủ từ chối'),
      );
    }
    gender = command.gender;
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
