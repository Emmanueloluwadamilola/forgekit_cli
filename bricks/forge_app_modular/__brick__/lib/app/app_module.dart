import 'package:dio/dio.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'home_page.dart';

final appModule = createModule(
  register: (c) {
    c
      ..addLazySingleton<Dio>(Dio.new)
      // forgekit:services
      ..route('/', child: (_, __) => const HomePage())
      // forgekit:modules
      ;
  },
);
