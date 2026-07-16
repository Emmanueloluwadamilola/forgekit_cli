import 'package:flutter/material.dart';
{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}

import 'core/di/core_module_container.dart';
import 'core/presentation/app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire up the get_it/injectable dependency graph.
  await configureDependencies();

  // Storage and other initialized services are inserted above this marker.
  // forgekit:service-initializers

{{#useRiverpod}}  runApp(const ProviderScope(child: App()));
{{/useRiverpod}}{{^useRiverpod}}  runApp(const App());
{{/useRiverpod}}
}
