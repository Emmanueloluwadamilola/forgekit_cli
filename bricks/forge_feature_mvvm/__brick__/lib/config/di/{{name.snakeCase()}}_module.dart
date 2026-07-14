import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/data/services/{{name.snakeCase()}}_api_service.dart';

@module
abstract class {{name.pascalCase()}}Module {
  @lazySingleton
  {{name.pascalCase()}}ApiService {{name.camelCase()}}ApiService(Dio dio) =>
      {{name.pascalCase()}}ApiService(dio);
}
