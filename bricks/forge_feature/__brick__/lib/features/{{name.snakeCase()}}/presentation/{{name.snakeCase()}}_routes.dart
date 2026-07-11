{{^useRouter}}import 'package:go_router/go_router.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/screens/{{name.snakeCase()}}_screen.dart';

/// go_router routes for the {{name.pascalCase()}} feature.
///
/// Register these in your central AppRouter by spreading the list, e.g.:
///
///   final router = GoRouter(
///     routes: [
///       ...{{name.camelCase()}}Routes,
///       // ...other feature routes
///     ],
///   );
///
/// Navigate with: `context.goNamed({{name.pascalCase()}}Screen.id)` or
/// `context.go({{name.pascalCase()}}Screen.id)`.
final List<RouteBase> {{name.camelCase()}}Routes = [
  GoRoute(
    path: {{name.pascalCase()}}Screen.id,
    name: {{name.pascalCase()}}Screen.id,
    builder: (context, state) => const {{name.pascalCase()}}Screen(),
  ),
];
{{/useRouter}}