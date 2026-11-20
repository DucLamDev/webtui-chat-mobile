import 'package:go_router/go_router.dart';

/// `?project=` của đường dẫn IDE; rỗng coi như không có.
String? ideRouteProject(GoRouterState s) {
  final p = s.uri.queryParameters['project'];
  return p == null || p.isEmpty ? null : p;
}
