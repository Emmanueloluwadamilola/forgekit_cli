import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'utils.dart';

/// Generates a standalone domain model + `@JsonSerializable` DTO from a JSON
/// sample pasted at the terminal.
///
/// Placed in `lib/core/domain/entity/…` by default, or inside a feature when
/// [feature] is given. Returns `0` on success, `1` on failure.
Future<int> addModel({
  required String name,
  required Logger logger,
  required Directory root,
  String? feature,
}) async {
  final config = loadForgeKitConfig(root: root);
  if (config.architecture != 'clean') {
    logger.err(
      'forgekit add model currently supports the clean architecture profile. '
      'This project uses ${config.architecture}.',
    );
    return 1;
  }
  final base = pascalCase(name);
  final snake = snakeCase(name);
  if (base.isEmpty || !RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(base)) {
    logger.err(
      'Use a model name whose generated Dart type starts with a letter and '
      'contains only letters or digits, e.g. "forgekit add model User".',
    );
    return 1;
  }
  final projectName = detectProjectName(root: root);
  final featureSnake = feature == null ? null : snakeCase(feature);
  if (featureSnake != null &&
      !Directory(
        p.join(root.path, 'lib', 'features', featureSnake),
      ).existsSync()) {
    logger.err('Feature "$featureSnake" not found.');
    logger.info('Create it first with: forgekit add feature $featureSnake');
    return 1;
  }

  logger.info(
    'Paste the JSON for "$base", then press Enter on an empty line:',
  );
  final jsonText = _readBlock();
  if (jsonText.trim().isEmpty) {
    logger.err('No JSON provided.');
    return 1;
  }

  final List<JsonClass> classes;
  try {
    final decoded = jsonDecode(jsonText);
    if (decoded is Map) {
      classes = analyzeJson(base, decoded.cast<String, dynamic>());
    } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      classes = analyzeJsonObjects(base, decoded);
    } else {
      logger.err('Top-level JSON must be an object or a list of objects.');
      return 1;
    }
  } on FormatException catch (e) {
    logger.err('Could not parse JSON: ${e.message}');
    return 1;
  }

  // Resolve target directories + the model import used by the DTO.
  final String modelDir;
  final String dtoDir;
  final String modelImport;
  if (featureSnake != null) {
    final f = featureSnake;
    modelDir =
        p.join(root.path, 'lib', 'features', f, 'domain', 'entity', 'model');
    dtoDir = p.join(root.path, 'lib', 'features', f, 'data', 'remote', 'dto');
    modelImport =
        'package:$projectName/features/$f/domain/entity/model/$snake.dart';
  } else {
    modelDir = p.join(root.path, 'lib', 'core', 'domain', 'entity', 'model');
    dtoDir = p.join(root.path, 'lib', 'core', 'domain', 'entity', 'dto');
    modelImport = 'package:$projectName/core/domain/entity/model/$snake.dart';
  }

  final progress = logger.progress('Generating model "$base"');
  final modelPath = p.join(modelDir, '$snake.dart');
  final dtoPath = p.join(dtoDir, '${snake}_dto.dart');

  if (File(modelPath).existsSync() || File(dtoPath).existsSync()) {
    progress.fail('A model or DTO named "$snake" already exists.');
    return 1;
  }

  _write(modelPath, emitModels(classes));
  _write(
    dtoPath,
    emitDto(
      classes,
      partName: '${snake}_dto',
      withToModel: true,
      modelImport: modelImport,
    ),
  );
  progress.complete('Generated model "$base".');

  logger
    ..info('')
    ..info('Generated:')
    ..info('  ${p.relative(modelPath, from: root.path)}')
    ..info('  ${p.relative(dtoPath, from: root.path)}')
    ..info('')
    ..info('Next steps:')
    ..info('  dart run build_runner build');
  return 0;
}

/// Reads lines from stdin until a blank line (or EOF).
String _readBlock() {
  final lines = <String>[];
  while (true) {
    final line = stdin.readLineSync();
    if (line == null || line.trim().isEmpty) break;
    lines.add(line);
  }
  return lines.join('\n');
}

void _write(String path, String content) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
