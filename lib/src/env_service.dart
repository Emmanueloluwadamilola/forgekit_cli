import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'json_to_dart.dart';

Future<int> addEnvironments({
  required List<String> environments,
  required Logger logger,
  required Directory root,
}) async {
  final names =
      environments.map(snakeCase).where((name) => name.isNotEmpty).toList();
  if (names.isEmpty) {
    logger.err(
      'Provide at least one environment, e.g. "forgekit add env dev,prod".',
    );
    return 1;
  }

  final progress =
      logger.progress('Scaffolding environments: ${names.join(', ')}');
  final written = <String>[];

  try {
    final envDir = Directory(p.join(root.path, 'assets', 'env'));
    envDir.createSync(recursive: true);
    for (final name in names) {
      final file = File(p.join(envDir.path, '$name.json'));
      if (!file.existsSync()) {
        file.writeAsStringSync(
          _prettyJson({
            'ENVIRONMENT': name,
            'API_BASE_URL': 'https://$name.api.example.com',
          }),
        );
        written.add(file.path);
      }
    }

    final configFile = File(
      p.join(root.path, 'lib', 'core', 'config', 'env_config.dart'),
    );
    if (!configFile.existsSync()) {
      configFile.parent.createSync(recursive: true);
      configFile.writeAsStringSync(_envConfigTemplate());
      written.add(configFile.path);
    }

    _registerAssetDir(root, 'assets/env/');
  } on FileSystemException catch (e) {
    progress.fail('Failed to scaffold environments.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Scaffolded ${names.length} environment(s).');
  logger
    ..info('')
    ..info('Generated / updated:')
    ..info('  pubspec.yaml')
    ..info(
      written
          .map((file) => '  ${p.relative(file, from: root.path)}')
          .join('\n'),
    )
    ..info('')
    ..info('Load an environment before runApp, e.g.:')
    ..info("  await EnvConfig.load('dev');")
    ..info('')
    ..info('Set values with:')
    ..info(
      '  forgekit set env API_BASE_URL https://api.example.com --environment dev',
    );
  return 0;
}

Future<int> setEnvironmentValue({
  required String key,
  required String value,
  required Logger logger,
  required Directory root,
  String? environment,
  bool all = false,
}) async {
  final normalizedKey = _normalizeKey(key);
  if (normalizedKey.isEmpty) {
    logger.err('An environment key is required.');
    return 1;
  }
  if (!all && (environment == null || environment.trim().isEmpty)) {
    logger.err('Pass --environment <name> or --all.');
    return 1;
  }

  final envDir = Directory(p.join(root.path, 'assets', 'env'));
  if (!envDir.existsSync()) {
    logger.err('No assets/env directory found. Run: forgekit add env dev');
    return 1;
  }

  final files = all
      ? envDir
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.json')
          .toList()
      : [File(p.join(envDir.path, '${snakeCase(environment!)}.json'))];

  if (files.isEmpty || files.any((file) => !file.existsSync())) {
    logger.err('Environment file not found.');
    return 1;
  }

  final progress = logger.progress('Setting $normalizedKey');
  try {
    for (final file in files) {
      final decoded = json.decode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Environment JSON must be an object.');
      }
      decoded[normalizedKey] = value;
      file.writeAsStringSync(_prettyJson(decoded));
    }
  } on FormatException catch (e) {
    progress.fail('Failed to update environment files.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Updated ${files.length} environment file(s).');
  return 0;
}

void _registerAssetDir(Directory root, String assetDir) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  final editor = YamlEditor(pubspec.readAsStringSync());

  final existing = _tryParse(editor, ['flutter', 'assets']);
  final current = existing is YamlList
      ? existing.map((value) => value.toString()).toList()
      : <String>[];
  if (!current.contains(assetDir)) {
    final merged = [...current, assetDir];
    if (_tryParse(editor, ['flutter']) == null) {
      editor.update(['flutter'], {'assets': merged});
    } else {
      editor.update(['flutter', 'assets'], merged);
    }
    pubspec.writeAsStringSync(editor.toString());
  }
}

YamlNode? _tryParse(YamlEditor editor, List<Object> path) {
  try {
    return editor.parseAt(path);
  } on ArgumentError {
    return null;
  }
}

String _normalizeKey(String input) {
  return input
      .trim()
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '')
      .toUpperCase();
}

String _envConfigTemplate() => '''
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class EnvConfig {
  EnvConfig._();

  static String? _environment;
  static Map<String, dynamic> _values = const {};

  static String? get environment => _environment;

  static Future<void> load(String environment) async {
    final normalized = environment.trim().toLowerCase();
    final raw = await rootBundle.loadString('assets/env/\$normalized.json');
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Environment config must be a JSON object.');
    }
    _environment = normalized;
    _values = decoded;
  }

  static String string(String key, {String fallback = ''}) {
    final value = _values[key];
    return value == null ? fallback : value.toString();
  }

  static bool boolValue(String key, {bool fallback = false}) {
    final value = _values[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  static int intValue(String key, {int fallback = 0}) {
    final value = _values[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static Map<String, dynamic> get values => Map.unmodifiable(_values);
}
''';

String _prettyJson(Map<String, dynamic> data) {
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}
