import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/data/remote/service/{{name.snakeCase()}}_api_service.dart';

/// DI module for the {{name.pascalCase()}} feature.
///
/// Provides the retrofit [{{name.pascalCase()}}ApiService]. The repository binding
/// (`{{name.pascalCase()}}RepositoryImpl` -> `{{name.pascalCase()}}Repository`) is declared
/// on the impl via `@LazySingleton(as: {{name.pascalCase()}}Repository)`.
{{#useRouter}}
// The ForgeKit CLI registers this feature's named route automatically.
// Direct Mason rendering bypasses that orchestration and must integrate the
// generated screen into the application router separately.
{{/useRouter}}
@module
abstract class {{name.pascalCase()}}Module {
  @lazySingleton
  {{name.pascalCase()}}ApiService {{name.camelCase()}}ApiService(Dio dio) =>
      {{name.pascalCase()}}ApiService(dio);
}
