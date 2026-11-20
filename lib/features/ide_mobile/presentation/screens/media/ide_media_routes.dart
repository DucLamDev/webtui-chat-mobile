import 'package:go_router/go_router.dart';

import '../../widgets/ide_access_gate.dart';
import '../ide_route_args.dart';
import '../more/ide_more_common.dart';
import 'ide_appscreen_screen.dart';
import 'ide_video_list_screen.dart';
import 'ide_video_screen.dart';

final _slug = RegExp(r'^[A-Za-z0-9._-]{1,80}$');

/// Tên thư mục video (Phụ lục C): không `..`, không `/`.
bool isIdeVideoSlug(String? s) =>
    s != null && _slug.hasMatch(s) && !s.contains('..');

/// Đường dẫn Màn hình app + Studio video (GĐ4, Phụ lục C).
List<GoRoute> ideMediaRoutes() => [
  GoRoute(
    path: '/ide/appscreen',
    name: 'ide-appscreen',
    builder: (context, state) => IdeAccessGate(
      child: IdeAppScreenScreen(project: ideRouteProject(state)),
    ),
  ),
  GoRoute(
    path: '/ide/video',
    name: 'ide-video',
    builder: (context, state) => IdeAccessGate(
      child: IdeVideoListScreen(project: ideRouteProject(state)),
    ),
  ),
  GoRoute(
    path: '/ide/video/:slug',
    name: 'ide-video-one',
    builder: (context, state) {
      final slug = state.pathParameters['slug'];
      final project = ideRouteProject(state);
      return IdeAccessGate(
        child: isIdeVideoSlug(slug) && project != null
            ? IdeVideoScreen(project: project, slug: slug!)
            : const IdeMoreNotFoundScreen(),
      );
    },
  ),
];
