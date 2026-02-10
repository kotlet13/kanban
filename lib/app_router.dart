import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/connect_page.dart';
import 'features/auth/launch_page.dart';
import 'features/board/board_page.dart';
import 'features/board/board_structure_page.dart';
import 'features/projects/projects_page.dart';
import 'features/tasks/task_details_page.dart';

final appRouter = GoRouter(
  initialLocation: '/launch',
  routes: <RouteBase>[
    GoRoute(
      path: '/launch',
      builder: (context, state) => const LaunchPage(),
    ),
    GoRoute(
      path: '/connect',
      builder: (context, state) => const ConnectPage(),
    ),
    GoRoute(
      path: '/projects',
      builder: (context, state) => const ProjectsPage(),
    ),
    GoRoute(
      path: '/board/:projectId',
      builder: (context, state) {
        final projectId =
            int.tryParse(state.pathParameters['projectId'] ?? '') ?? 0;
        final projectName = state.uri.queryParameters['projectName'] ?? 'Project';
        return BoardPage(
          projectId: projectId,
          projectName: projectName,
        );
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'structure',
          builder: (context, state) {
            final projectId =
                int.tryParse(state.pathParameters['projectId'] ?? '') ?? 0;
            final projectName =
                state.uri.queryParameters['projectName'] ?? 'Project';
            return BoardStructurePage(
              projectId: projectId,
              projectName: projectName,
            );
          },
        ),
        GoRoute(
          path: 'task',
          builder: (context, state) {
            final projectId =
                int.tryParse(state.pathParameters['projectId'] ?? '') ?? 0;
            final taskId = int.tryParse(state.uri.queryParameters['taskId'] ?? '');
            return TaskDetailsPage(
              projectId: projectId,
              taskId: taskId,
            );
          },
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Route error')),
    body: Center(child: Text(state.error?.toString() ?? 'Unknown error')),
  ),
);
