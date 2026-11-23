import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/features/admin_panel/application/admin_panel_access.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';

PermissionSet _perms(List<String> codes) => PermissionSet([
  for (final code in codes)
    WorkspacePermission(
      id: code,
      code: code,
      module: code.split('.').first,
      action: code,
      name: code,
    ),
]);

SelfHostedServerDiscovery _discovery({String? adminBaseUrl}) {
  return SelfHostedServerDiscovery.fromApiResponse(
    payload: {
      'data': {
        'discovery': {
          'version': '1',
          'instance_id': '11111111-1111-4111-8111-111111111111',
          'domain': 'chat.company.example',
          'zone': {'name': 'Company Chat', 'status': 'active'},
          'runtime': {
            'app_name': 'Company Chat',
            'app_version': 'self-hosted',
            'server_version': 'self-hosted',
            'api_contract_version': 1,
            'minimum_supported_mobile_version': '1.1.0',
            'api_base_url': 'https://chat.company.example',
            'ws_base_url': 'wss://chat.company.example/ws',
            'admin_base_url': ?adminBaseUrl,
          },
          // Các cờ an toàn bắt buộc của discovery (thiếu là app từ chối máy chủ).
          'capabilities': {
            'self_hosted': true,
            'chat': true,
            'moderation': true,
            'reporting': true,
            'blocking': true,
            'account_deletion': true,
            'legal_acceptance': true,
          },
          'deployment': {'status': 'ready'},
        },
      },
    },
    requestedServer: Uri.parse('https://chat.company.example'),
    mobileVersion: '1.2.0',
  );
}

void main() {
  test('chỉ hiện Trang quản trị khi có quyền admin.view', () {
    expect(adminPanelPermission, 'admin.view');
    // Chủ sở hữu / quản trị workspace: máy chủ trả admin.view.
    expect(
      canOpenAdminPanel(_perms(['admin.view', 'user.manage', 'message.send'])),
      isTrue,
    );
    // Thành viên thường: chỉ quyền trò chuyện; quyền quản lý lẻ khác không đủ.
    expect(
      canOpenAdminPanel(
        _perms(['workspace.view_members', 'message.send', 'file.upload']),
      ),
      isFalse,
    );
    expect(
      canOpenAdminPanel(_perms(['moderation.manage', 'channel.manage'])),
      isFalse,
    );
    // Quyền chưa tải xong: chưa hiện.
    expect(canOpenAdminPanel(null), isFalse);
  });

  test(
    'địa chỉ: admin_base_url cùng origin, không có thì /admin/; luôn kèm from=app',
    () {
      expect(adminPanelUri(null), isNull);
      expect(
        adminPanelUri(_discovery()),
        Uri.parse('https://chat.company.example/admin/?from=app'),
      );
      expect(
        adminPanelUri(
          _discovery(adminBaseUrl: 'https://chat.company.example/quan-tri'),
        ),
        Uri.parse('https://chat.company.example/quan-tri?from=app'),
      );
      // admin_base_url khác origin bị bỏ lúc đọc discovery → về /admin/.
      expect(
        adminPanelUri(_discovery(adminBaseUrl: 'https://evil.example/admin')),
        Uri.parse('https://chat.company.example/admin/?from=app'),
      );
      expect(adminPanelFromAppParam, 'from');
      expect(adminPanelFromAppValue, 'app');
    },
  );
}
