import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}

import 'app/app.dart';
import 'app/app_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage and other initialized services are inserted above this marker.
  // forgekit:service-initializers

{{#useRiverpod}}  runApp(
    ModularApp(
      module: appModule,
      child: const ProviderScope(child: App()),
    ),
  );
{{/useRiverpod}}{{^useRiverpod}}  runApp(
    ModularApp(module: appModule, child: const App()),
  );
{{/useRiverpod}}}
