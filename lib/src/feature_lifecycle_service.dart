import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'route_wiring_service.dart';

Future<int> renameFeature({
  required Directory root,
  required String from,
  required String to,
  required Logger logger,
}) async {
  final config = loadForgeKitConfig(root: root);
  if (config.architecture != 'clean') {
    logger.err(
      'forgekit rename feature currently supports the clean architecture '
      'profile. This project uses ${config.architecture}.',
    );
    return 1;
  }
  final fromSnake = snakeCase(from);
  final toSnake = snakeCase(to);

  if (fromSnake.isEmpty || toSnake.isEmpty) {
    logger.err('Feature names cannot be empty.');
    return 1;
  }
  if (fromSnake == toSnake) {
    logger.err('Old and new feature names are the same.');
    return 1;
  }

  final featuresDir = Directory(p.join(root.path, 'lib', 'features'));
  final fromDir = Directory(p.join(featuresDir.path, fromSnake));
  final toDir = Directory(p.join(featuresDir.path, toSnake));
  if (!fromDir.existsSync()) {
    logger.err('Feature not found: lib/features/$fromSnake');
    return 1;
  }
  if (toDir.existsSync()) {
    logger.err('Target feature already exists: lib/features/$toSnake');
    return 1;
  }

  final progress =
      logger.progress('Renaming feature "$fromSnake" to "$toSnake"');
  try {
    await fromDir.rename(toDir.path);
    await _renamePaths(toDir, fromSnake: fromSnake, toSnake: toSnake);
    await _replaceInTree(
      Directory(p.join(root.path, 'lib')),
      fromSnake: fromSnake,
      toSnake: toSnake,
    );

    final testFrom =
        Directory(p.join(root.path, 'test', 'features', fromSnake));
    final testTo = Directory(p.join(root.path, 'test', 'features', toSnake));
    if (testFrom.existsSync()) {
      if (testTo.existsSync()) {
        throw FileSystemException('Target tests already exist', testTo.path);
      }
      await testFrom.rename(testTo.path);
      await _renamePaths(testTo, fromSnake: fromSnake, toSnake: toSnake);
    }
    final testsRoot = Directory(p.join(root.path, 'test'));
    if (testsRoot.existsSync()) {
      await _replaceInTree(
        testsRoot,
        fromSnake: fromSnake,
        toSnake: toSnake,
      );
    }
  } on FileSystemException catch (e) {
    progress.fail('Failed to rename feature.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Renamed feature "$fromSnake" to "$toSnake".');
  return 0;
}

Future<int> removeFeature({
  required Directory root,
  required String feature,
  required Logger logger,
  required bool force,
}) async {
  final config = loadForgeKitConfig(root: root);
  if (config.architecture != 'clean') {
    logger.err(
      'forgekit remove feature currently supports the clean architecture '
      'profile. This project uses ${config.architecture}.',
    );
    return 1;
  }
  final featureSnake = snakeCase(feature);
  if (featureSnake.isEmpty) {
    logger.err('A feature name is required.');
    return 1;
  }

  final featureDir = Directory(
    p.join(root.path, 'lib', 'features', featureSnake),
  );
  final testDir = Directory(
    p.join(root.path, 'test', 'features', featureSnake),
  );

  if (!featureDir.existsSync() && !testDir.existsSync()) {
    logger.err('Feature not found: $featureSnake');
    return 1;
  }

  if (!force) {
    if (!stdin.hasTerminal || !stdout.hasTerminal) {
      logger.err(
        'Refusing to remove without --force in a non-interactive shell.',
      );
      return 1;
    }
    final confirmed = logger.confirm(
      'Remove feature "$featureSnake" and its generated tests?',
      defaultValue: false,
    );
    if (!confirmed) {
      logger.info('Skipped.');
      return 0;
    }
  }

  final progress = logger.progress('Removing feature "$featureSnake"');
  try {
    unregisterFeatureRoutes(
      root: root,
      config: config,
      feature: featureSnake,
    );
    if (featureDir.existsSync()) await featureDir.delete(recursive: true);
    if (testDir.existsSync()) await testDir.delete(recursive: true);
  } on FileSystemException catch (e) {
    progress.fail('Failed to remove feature.');
    logger.err(e.message);
    return 1;
  } on RouteWiringException catch (e) {
    progress.fail('Failed to remove feature route registrations.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Removed feature "$featureSnake".');
  logger.info('Removed ForgeKit-owned route registrations for this feature.');
  return 0;
}

Future<void> _renamePaths(
  Directory root, {
  required String fromSnake,
  required String toSnake,
}) async {
  final entities =
      await root.list(recursive: true, followLinks: false).toList();
  entities.sort((a, b) => b.path.length.compareTo(a.path.length));

  for (final entity in entities) {
    final basename = p.basename(entity.path);
    if (!basename.contains(fromSnake)) continue;
    final targetPath = p.join(
      p.dirname(entity.path),
      basename.replaceAll(fromSnake, toSnake),
    );
    await entity.rename(targetPath);
  }
}

Future<void> _replaceInTree(
  Directory root, {
  required String fromSnake,
  required String toSnake,
}) async {
  final fromPascal = pascalCase(fromSnake);
  final toPascal = pascalCase(toSnake);
  final fromCamel = camelCase(fromSnake);
  final toCamel = camelCase(toSnake);
  final fromTitle = _titleCase(fromSnake);
  final toTitle = _titleCase(toSnake);

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!_isTextFile(entity.path)) continue;

    final original = await entity.readAsString();
    final updated = original
        .replaceAll(fromSnake, toSnake)
        .replaceAll(fromPascal, toPascal)
        .replaceAll(fromCamel, toCamel)
        .replaceAll(fromTitle, toTitle);
    if (updated != original) {
      await entity.writeAsString(updated);
    }
  }
}

bool _isTextFile(String path) {
  return const {
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.md',
  }.contains(p.extension(path));
}

String _titleCase(String input) {
  return snakeCase(input)
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
