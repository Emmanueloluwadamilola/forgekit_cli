import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'json_to_dart.dart';

/// Adds a screen (a `StatelessWidget` with a static route `id`) to an existing
/// feature's `presentation/screens/` folder.
///
/// Returns `0` on success, `1` on failure.
Future<int> addScreen({
  required String feature,
  required String screenName,
  required Logger logger,
  required Directory root,
}) async {
  final featureSnake = snakeCase(feature);
  final featureDir =
      Directory(p.join(root.path, 'lib', 'features', featureSnake));
  if (!featureDir.existsSync()) {
    logger.err('Feature "$featureSnake" not found (looked for '
        '${featureDir.path}).');
    logger.info('Create it first with: forgekit add feature $featureSnake');
    return 1;
  }

  // Normalize names so both "order_detail" and "OrderDetailScreen" work.
  var pascal = pascalCase(screenName);
  if (pascal.endsWith('Screen')) {
    pascal = pascal.substring(0, pascal.length - 'Screen'.length);
  }
  final snake = snakeCase(pascal);
  final className = '${pascal}Screen';
  final title = pascal.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );

  final file = File(
    p.join(featureDir.path, 'presentation', 'screens', '${snake}_screen.dart'),
  );
  if (file.existsSync()) {
    logger.err(
      'Screen already exists: ${p.relative(file.path, from: root.path)}',
    );
    return 1;
  }

  final progress = logger.progress('Adding screen "$className"');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('''
import 'package:flutter/material.dart';

/// $title screen for the ${pascalCase(featureSnake)} feature.
class $className extends StatelessWidget {
  const $className({super.key});

  static const id = '/$snake';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$title')),
      // TODO: build the $title UI.
      body: const Center(child: Text('$title')),
    );
  }
}
''');
  progress.complete('Added screen "$className".');

  logger
    ..info('')
    ..info('Created ${p.relative(file.path, from: root.path)}')
    ..info('')
    ..info('Register the route:')
    ..info('  • Named routes — in core/presentation/app/app.dart `routes` map:')
    ..info('      $className.id: (_) => const $className(),')
    ..info('  • go_router — add a GoRoute for $className to your AppRouter.');
  return 0;
}
