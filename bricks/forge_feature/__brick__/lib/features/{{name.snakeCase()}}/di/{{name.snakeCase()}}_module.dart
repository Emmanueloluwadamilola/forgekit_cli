import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/data/remote/service/{{name.snakeCase()}}_api_service.dart';

/// DI module for the {{name.pascalCase()}} feature.
///
/// Provides the retrofit [{{name.pascalCase()}}ApiService]. The repository binding
/// (`{{name.pascalCase()}}RepositoryImpl` -> `{{name.pascalCase()}}Repository`) is declared
/// on the impl via `@LazySingleton(as: {{name.pascalCase()}}Repository)`.
{{#useRouter}}
// NOTE: after running build_runner, register the screen route in
// core/presentation/app/app.dart:
//   {{name.pascalCase()}}Screen.id: (_) => const {{name.pascalCase()}}Screen(),
{{/useRouter}}
@module
abstract class {{name.pascalCase()}}Module {
  @lazySingleton
  {{name.pascalCase()}}ApiService {{name.camelCase()}}ApiService(Dio dio) =>
      {{name.pascalCase()}}ApiService(dio);
}
