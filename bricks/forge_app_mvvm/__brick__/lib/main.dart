import 'package:flutter/material.dart';
{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}

import 'config/di/dependencies.dart';
import 'ui/core/app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  // Storage and other initialized services are inserted above this marker.
  // forgekit:service-initializers

{{#useRiverpod}}  runApp(const ProviderScope(child: App()));
{{/useRiverpod}}{{^useRiverpod}}  runApp(const App());
{{/useRiverpod}}}
