import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/data/remote/service/{{name.snakeCase()}}_api_service.dart';
import 'package:{{projectName}}/features/{{name.snakeCase()}}/domain/repository/{{name.snakeCase()}}_repository.dart';

/// Concrete [{{name.pascalCase()}}Repository] backed by the retrofit API service.
///
/// Methods are added by: `forgekit add function {{name.snakeCase()}} <name>`
@LazySingleton(as: {{name.pascalCase()}}Repository)
class {{name.pascalCase()}}RepositoryImpl implements {{name.pascalCase()}}Repository {
  // ignore: unused_field
  final {{name.pascalCase()}}ApiService _apiService;

  {{name.pascalCase()}}RepositoryImpl(this._apiService);
}
