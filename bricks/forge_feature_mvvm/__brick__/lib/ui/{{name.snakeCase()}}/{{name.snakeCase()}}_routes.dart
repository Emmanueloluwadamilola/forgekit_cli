{{^useRouter}}import 'package:go_router/go_router.dart';

import 'package:{{projectName}}/ui/{{name.snakeCase()}}/widgets/{{name.snakeCase()}}_screen.dart';

final List<RouteBase> {{name.camelCase()}}Routes = [
  GoRoute(
    path: {{name.pascalCase()}}Screen.id,
    name: {{name.pascalCase()}}Screen.id,
    builder: (_, _) => const {{name.pascalCase()}}Screen(),
  ),
  // forgekit:feature-routes
];
{{/useRouter}}
