import 'package:flutter/material.dart';
{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}

import 'core/di/core_module_container.dart';
import 'core/presentation/app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire up the get_it/injectable dependency graph.
  await configureDependencies();

  // Register cross-cutting services here, e.g.:
  // await getIt<NotificationService>().init();

{{#useRiverpod}}  runApp(const ProviderScope(child: App()));
{{/useRiverpod}}{{^useRiverpod}}  runApp(const App());
{{/useRiverpod}}
}
