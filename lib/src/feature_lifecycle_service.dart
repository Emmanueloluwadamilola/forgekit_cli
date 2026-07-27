import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'route_wiring_service.dart';
import 'utils.dart';

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
    if (!hasInteractiveTerminal) {
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

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (p.extension(entity.path) != '.dart') continue;

    final original = await entity.readAsString();
    final updated = _renameDartSource(
      original,
      fromSnake: fromSnake,
      toSnake: toSnake,
      fromPascal: fromPascal,
      toPascal: toPascal,
      fromCamel: fromCamel,
      toCamel: toCamel,
    );
    if (updated != original) {
      await entity.writeAsString(updated);
    }
  }
}

String _renameDartSource(
  String source, {
  required String fromSnake,
  required String toSnake,
  required String fromPascal,
  required String toPascal,
  required String fromCamel,
  required String toCamel,
}) {
  String renameToken(String token) {
    if (token.startsWith(fromPascal)) {
      return '$toPascal${token.substring(fromPascal.length)}';
    }
    if (token.startsWith(fromCamel)) {
      return '$toCamel${token.substring(fromCamel.length)}';
    }
    if (token.startsWith(fromSnake)) {
      return '$toSnake${token.substring(fromSnake.length)}';
    }
    return token;
  }

  final output = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index);
      final stop = end == -1 ? source.length : end;
      output.write(source.substring(index, stop));
      index = stop;
      continue;
    }
    if (source.startsWith('/*', index)) {
      var depth = 1;
      var cursor = index + 2;
      while (cursor < source.length && depth > 0) {
        if (source.startsWith('/*', cursor)) {
          depth++;
          cursor += 2;
        } else if (source.startsWith('*/', cursor)) {
          depth--;
          cursor += 2;
        } else {
          cursor++;
        }
      }
      output.write(source.substring(index, cursor));
      index = cursor;
      continue;
    }

    final rawString = source[index] == 'r' &&
        index + 1 < source.length &&
        (source[index + 1] == "'" || source[index + 1] == '"') &&
        (index == 0 || !_isIdentifierPart(source[index - 1]));
    final quoteIndex = rawString ? index + 1 : index;
    if (source[quoteIndex] == "'" || source[quoteIndex] == '"') {
      final quote = source[quoteIndex];
      final triple = source.startsWith('$quote$quote$quote', quoteIndex);
      final delimiter = triple ? '$quote$quote$quote' : quote;
      var cursor = quoteIndex + delimiter.length;
      while (cursor < source.length) {
        if (!rawString && source[cursor] == r'\') {
          cursor += cursor + 1 < source.length ? 2 : 1;
          continue;
        }
        if (source.startsWith(delimiter, cursor)) {
          cursor += delimiter.length;
          break;
        }
        cursor++;
      }
      output.write(source.substring(index, cursor));
      index = cursor;
      continue;
    }

    if (_isIdentifierStart(source[index])) {
      var cursor = index + 1;
      while (cursor < source.length && _isIdentifierPart(source[cursor])) {
        cursor++;
      }
      output.write(renameToken(source.substring(index, cursor)));
      index = cursor;
      continue;
    }

    output.write(source[index]);
    index++;
  }

  var updated = output.toString();
  updated = updated.replaceAllMapped(
    RegExp(
      r'''^(\s*(?:import|export|part)\s+)(['"])(.*?)(['"])(.*)$''',
      multiLine: true,
    ),
    (match) {
      if (match[2] != match[4]) return match[0]!;
      final uri = match[3]!
          .replaceAll(fromSnake, toSnake)
          .replaceAll(fromPascal, toPascal)
          .replaceAll(fromCamel, toCamel);
      return '${match[1]}${match[2]}$uri${match[4]}${match[5]}';
    },
  );
  updated = updated.replaceAllMapped(
    RegExp(
      '// forgekit:(route|route-import):${RegExp.escape(fromSnake)}'
      r'(?=[:\s]|$)',
    ),
    (match) => '// forgekit:${match[1]}:$toSnake',
  );
  return updated;
}

bool _isIdentifierStart(String character) =>
    RegExp(r'[A-Za-z_$]').hasMatch(character);

bool _isIdentifierPart(String character) =>
    RegExp(r'[A-Za-z0-9_$]').hasMatch(character);
