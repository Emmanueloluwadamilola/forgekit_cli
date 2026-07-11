import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import 'json_to_dart.dart';

Future<int> addI18n({
  required List<String> locales,
  required Logger logger,
  required Directory root,
}) async {
  final normalized = locales.map(_normalizeLocale).whereType<String>().toList();
  if (normalized.isEmpty) {
    logger.err('Provide at least one locale, e.g. "forgekit add i18n en,fr".');
    return 1;
  }

  final progress = logger.progress('Scaffolding i18n');
  final written = <String>[];

  try {
    _updatePubspecForI18n(root);
    final l10nYaml = File(p.join(root.path, 'l10n.yaml'));
    if (!l10nYaml.existsSync()) {
      l10nYaml.writeAsStringSync(_l10nYaml(normalized.first));
      written.add(l10nYaml.path);
    }

    final l10nDir = Directory(p.join(root.path, 'lib', 'l10n'));
    l10nDir.createSync(recursive: true);
    for (final locale in normalized) {
      final arb = File(p.join(l10nDir.path, 'app_$locale.arb'));
      if (!arb.existsSync()) {
        arb.writeAsStringSync(_arb(locale));
        written.add(arb.path);
      }
    }
  } on FileSystemException catch (e) {
    progress.fail('Failed to scaffold i18n.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Scaffolded i18n for ${normalized.join(', ')}.');
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
    ..info('Next steps:')
    ..info('  flutter gen-l10n')
    ..info('  import "package:flutter_gen/gen_l10n/app_localizations.dart";');
  return 0;
}

Future<int> addLocalizedString({
  required String key,
  required String value,
  required Logger logger,
  required Directory root,
  String? locale,
}) async {
  final normalizedKey = camelCase(key);
  if (normalizedKey.isEmpty) {
    logger.err('A string key is required.');
    return 1;
  }

  final l10nDir = Directory(p.join(root.path, 'lib', 'l10n'));
  if (!l10nDir.existsSync()) {
    logger.err('No lib/l10n directory found. Run: forgekit add i18n en');
    return 1;
  }

  final targetLocale = locale == null ? null : _normalizeLocale(locale);
  final arbFiles = l10nDir
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).startsWith('app_'))
      .where((file) => p.extension(file.path) == '.arb')
      .where((file) {
    if (targetLocale == null) return true;
    return p.basenameWithoutExtension(file.path) == 'app_$targetLocale';
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (arbFiles.isEmpty) {
    logger.err(
      targetLocale == null
          ? 'No ARB files found in lib/l10n.'
          : 'No ARB file found for locale "$targetLocale".',
    );
    return 1;
  }

  final progress = logger.progress('Adding localized string "$normalizedKey"');
  try {
    for (final file in arbFiles) {
      final data = json.decode(file.readAsStringSync());
      if (data is! Map<String, dynamic>) {
        throw const FormatException('ARB file must contain a JSON object.');
      }
      data[normalizedKey] = value;
      data['@$normalizedKey'] ??= {
        'description': 'TODO: describe $normalizedKey',
      };
      file.writeAsStringSync(_prettyJson(data));
    }
  } on FormatException catch (e) {
    progress.fail('Failed to update ARB files.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Updated ${arbFiles.length} ARB file(s).');
  logger.info('Run: flutter gen-l10n');
  return 0;
}

void _updatePubspecForI18n(Directory root) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  final editor = YamlEditor(pubspec.readAsStringSync());

  editor.update(['dependencies', 'flutter_localizations'], {'sdk': 'flutter'});
  if (!_hasKey(editor, ['dependencies', 'intl'])) {
    editor.update(['dependencies', 'intl'], 'any');
  }

  if (!_hasKey(editor, ['flutter'])) {
    editor
        .update(['flutter'], {'generate': true, 'uses-material-design': true});
  } else {
    editor.update(['flutter', 'generate'], true);
  }

  pubspec.writeAsStringSync(editor.toString());
}

bool _hasKey(YamlEditor editor, List<Object> path) {
  try {
    editor.parseAt(path);
    return true;
  } on ArgumentError {
    return false;
  }
}

String _l10nYaml(String templateLocale) => '''
arb-dir: lib/l10n
template-arb-file: app_$templateLocale.arb
output-localization-file: app_localizations.dart
''';

String _arb(String locale) {
  return _prettyJson({
    '@@locale': locale,
    'appTitle': 'Forge App',
    '@appTitle': {
      'description': 'Application title',
    },
  });
}

String _prettyJson(Map<String, dynamic> data) {
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}

String? _normalizeLocale(String input) {
  final cleaned = input.trim().replaceAll('-', '_');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^[a-zA-Z]{2,3}(_[a-zA-Z]{2})?$').hasMatch(cleaned)) {
    return null;
  }
  final parts = cleaned.split('_');
  if (parts.length == 1) return parts.first.toLowerCase();
  return '${parts.first.toLowerCase()}_${parts.last.toUpperCase()}';
}
