import 'package:go_router/go_router.dart';

import '../../../domain/ide_deploy.dart';
import '../../widgets/ide_access_gate.dart';
import 'ide_deploy_screen.dart';
import 'ide_mergeq_screen.dart';

/// Màn con của tab Dự án; agent chính gắn vào `app_router.dart`.
///
/// - `/ide/mergeq?project=&pr=`: không có `project` thì hàng chờ của tôi.
/// - `/ide/deploy?project=&target=`.
List<GoRoute> ideProjectRoutes() => [
  GoRoute(
    path: '/ide/mergeq',
    name: 'ide-mergeq',
    builder: (context, state) {
      final q = state.uri.queryParameters;
      final project = q['project'];
      return IdeAccessGate(
        child: IdeMergeqScreen(
          project: project == null || project.isEmpty ? null : project,
          pr: ideParsePrNumber(q['pr'] ?? ''),
        ),
      );
    },
  ),
  GoRoute(
    path: '/ide/deploy',
    name: 'ide-deploy',
    builder: (context, state) {
      final q = state.uri.queryParameters;
      final target = q['target'];
      return IdeAccessGate(
        child: IdeDeployScreen(
          project: q['project'] ?? '',
          target: target == null || target.isEmpty ? null : target,
        ),
      );
    },
  ),
];
