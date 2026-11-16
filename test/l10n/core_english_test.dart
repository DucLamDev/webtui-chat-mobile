import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/error_mapper.dart';
import 'package:webtui_chat/features/auth/presentation/auth_formatters.dart';
import 'package:webtui_chat/features/call_privacy/domain/entities/call_privacy.dart';
import 'package:webtui_chat/features/workspace/presentation/screens/permission_denied_view.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

void main() {
  void useEnglish() {
    AppStrings.current = const AppStringsEn();
    addTearDown(() => AppStrings.current = const AppStringsVi());
  }

  test('lỗi mạng và lỗi HTTP đổi sang tiếng Anh', () {
    final timeout = DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(
      mapDioExceptionToFailure(timeout).message,
      'Kết nối quá hạn. Vui lòng thử lại.',
    );
    useEnglish();
    expect(
      mapDioExceptionToFailure(timeout).message,
      'Connection timed out. Please try again.',
    );
    expect(
      userFacingErrorMessage(timeout),
      'Connection timed out. Please try again.',
    );
    expect(
      userFacingErrorMessage(Exception('boom')),
      'Could not complete that. Please try again.',
    );
  });

  test('định dạng phiên và quyền riêng tư cuộc gọi đổi sang tiếng Anh', () {
    final now = DateTime.utc(2026, 11, 16, 10);
    final earlier = now.subtract(const Duration(minutes: 5));
    expect(formatLastActive(earlier, now), '5 phút trước');
    expect(WhoCanCallMe.nobody.label, 'Không ai');
    useEnglish();
    expect(formatLastActive(earlier, now), '5 min ago');
    expect(authMethodLabel('password'), 'Password');
    expect(WhoCanCallMe.nobody.label, 'Nobody');
    expect(WhoCanCallMe.contacts.label, 'Friends');
  });

  testWidgets('màn không đủ quyền hiện tiếng Anh', (tester) async {
    useEnglish();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PermissionDeniedView())),
    );
    expect(find.text('Not enough permission'), findsOneWidget);
    expect(
      find.text('You do not have permission to do this.'),
      findsOneWidget,
    );
  });
}
