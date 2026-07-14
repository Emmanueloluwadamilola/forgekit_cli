import 'package:dio/dio.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'data/{{name.snakeCase()}}_api_service.dart';
import 'data/{{name.snakeCase()}}_repository.dart';
import 'presentation/{{name.snakeCase()}}_page.dart';

final {{name.camelCase()}}Module = createModule(
  path: '/{{name.snakeCase()}}',
  register: (c) {
    c
      ..addLazySingleton<{{name.pascalCase()}}ApiService>(
        (Dio dio) => {{name.pascalCase()}}ApiService(dio),
      )
      ..addLazySingleton<{{name.pascalCase()}}Repository>(
        {{name.pascalCase()}}Repository.new,
      )
      ..route('/', child: (_, __) => const {{name.pascalCase()}}Page());
  },
);
