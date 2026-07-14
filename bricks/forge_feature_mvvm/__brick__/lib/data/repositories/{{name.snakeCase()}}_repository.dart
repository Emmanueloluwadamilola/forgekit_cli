import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/data/services/{{name.snakeCase()}}_api_service.dart';

@lazySingleton
class {{name.pascalCase()}}Repository {
  {{name.pascalCase()}}Repository(this._apiService);

  // ignore: unused_field
  final {{name.pascalCase()}}ApiService _apiService;
}
