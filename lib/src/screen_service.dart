import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'route_wiring_service.dart';
import 'utils.dart';

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
  final config = loadForgeKitConfig(root: root);
  final projectName = detectProjectName(root: root);
  final featureSnake = snakeCase(feature);
  final featureDir = Directory(
    p.joinAll([
      root.path,
      'lib',
      if (config.architecture == 'mvvm')
        'ui'
      else if (config.architecture == 'modular')
        'modules'
      else
        'features',
      featureSnake,
    ]),
  );
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
    p.joinAll([
      featureDir.path,
      if (config.architecture == 'mvvm')
        'widgets'
      else if (config.architecture == 'modular')
        'presentation'
      else ...[
        'presentation',
        'screens',
      ],
      '${snake}_screen.dart',
    ]),
  );
  if (file.existsSync()) {
    logger.err(
      'Screen already exists: ${p.relative(file.path, from: root.path)}',
    );
    return 1;
  }

  final progress = logger.progress('Adding screen "$className"');
  file.parent.createSync(recursive: true);
  final routePath =
      config.architecture == 'modular' ? '/$snake' : '/$featureSnake/$snake';
  file.writeAsStringSync('''
import 'package:flutter/material.dart';

/// $title screen for the ${pascalCase(featureSnake)} feature.
class $className extends StatelessWidget {
  const $className({super.key});

  static const id = '$routePath';

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
  try {
    registerScreenRoute(
      root: root,
      config: config,
      projectName: projectName,
      feature: featureSnake,
      screenName: snake,
    );
  } on RouteWiringException catch (error) {
    if (file.existsSync()) file.deleteSync();
    progress.fail('Could not register the screen route.');
    logger.err(error.message);
    return 1;
  }

  progress.complete('Added and registered screen "$className".');
  logger
    ..info('')
    ..info('Created ${p.relative(file.path, from: root.path)}')
    ..info('Registered route: $routePath');
  return 0;
}
