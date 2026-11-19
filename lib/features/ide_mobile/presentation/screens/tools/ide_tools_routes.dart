import 'package:go_router/go_router.dart';

import '../../widgets/ide_access_gate.dart';
import '../ide_route_args.dart';
import 'ide_agents_screen.dart';
import 'ide_demo_screen.dart';
import 'ide_devices_screen.dart';
import 'ide_monitor_screen.dart';
import 'ide_servers_screen.dart';
import 'ide_skills_screen.dart';

/// Đường dẫn công cụ IDE (GĐ4, Phụ lục C); mỗi màn bọc cổng vân tay.
List<GoRoute> ideToolsRoutes() => [
  GoRoute(
    path: '/ide/skills',
    name: 'ide-skills',
    builder: (context, state) =>
        IdeAccessGate(child: IdeSkillsScreen(project: ideRouteProject(state))),
  ),
  GoRoute(
    path: '/ide/agents',
    name: 'ide-agents',
    builder: (context, state) =>
        IdeAccessGate(child: IdeAgentsScreen(project: ideRouteProject(state))),
  ),
  GoRoute(
    path: '/ide/demo',
    name: 'ide-demo',
    builder: (context, state) =>
        IdeAccessGate(child: IdeDemoScreen(project: ideRouteProject(state))),
  ),
  GoRoute(
    path: '/ide/monitor',
    name: 'ide-monitor',
    builder: (context, state) =>
        IdeAccessGate(child: IdeMonitorScreen(project: ideRouteProject(state))),
  ),
  GoRoute(
    path: '/ide/servers',
    name: 'ide-servers',
    builder: (context, state) => const IdeAccessGate(child: IdeServersScreen()),
  ),
  GoRoute(
    path: '/ide/devices',
    name: 'ide-devices',
    builder: (context, state) => const IdeAccessGate(child: IdeDevicesScreen()),
  ),
];
