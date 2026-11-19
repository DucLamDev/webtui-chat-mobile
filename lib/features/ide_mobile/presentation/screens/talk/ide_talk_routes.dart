import 'package:go_router/go_router.dart';

import '../../widgets/ide_access_gate.dart';
import '../more/ide_more_common.dart';
import 'ide_profile_screen.dart';
import 'ide_talk_list_screen.dart';
import 'ide_talk_screen.dart';

final _talkId = RegExp(r'^[0-9a-f]{32}$');

/// Mã cuộc chat thường: 32 hex (Phụ lục C).
bool isIdeTalkId(String? id) => id != null && _talkId.hasMatch(id);

/// Đường dẫn chat thường + hồ sơ (GĐ4, Phụ lục C).
List<GoRoute> ideTalkRoutes() => [
  GoRoute(
    path: '/ide/talk',
    name: 'ide-talk',
    builder: (context, state) =>
        const IdeAccessGate(child: IdeTalkListScreen()),
  ),
  GoRoute(
    path: '/ide/talk/:id',
    name: 'ide-talk-one',
    builder: (context, state) {
      final id = state.pathParameters['id'];
      return IdeAccessGate(
        child: isIdeTalkId(id)
            ? IdeTalkScreen(talkId: id!)
            : const IdeMoreNotFoundScreen(),
      );
    },
  ),
  GoRoute(
    path: '/ide/profile',
    name: 'ide-profile',
    builder: (context, state) => const IdeAccessGate(child: IdeProfileScreen()),
  ),
];
