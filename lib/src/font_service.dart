import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Downloads a Google Font and wires it into a Flutter ForgeKit CLI project.
///
/// The flow is fully deterministic once the files are fetched:
///   1. Download the available static weights as `.ttf` files into
///      `assets/fonts/<Family>/`.
///   2. Register those files under `flutter > fonts:` in `pubspec.yaml`.
///   3. Set `fontFamily: '<Family>'` on the generated `ThemeData` in
///      `core/presentation/theme/app_theme.dart` (best effort).
///
/// Returns `0` on success, `1` on any failure. All paths are resolved relative
/// to [projectDir] so the same routine works for `forgekit add font` (cwd) and
/// `forgekit create app --font` (the freshly generated project folder).
Future<int> addFont(
  String rawName, {
  required Logger logger,
  String projectDir = '.',
}) async {
  final family = normalizeFamily(rawName);
  if (family.isEmpty) {
    logger.err('A font name is required, e.g. "forgekit add font Poppins".');
    return 1;
  }

  final progress = logger.progress('Downloading "$family" from Google Fonts');

  final List<_FontFile> files;
  try {
    files = await _downloadFamily(family, projectDir: projectDir);
  } on SocketException {
    progress.fail('Network error — could not reach Google Fonts.');
    logger.err('Check your internet connection and try again.');
    return 1;
  } on http.ClientException catch (e) {
    progress.fail('Download failed: ${e.message}');
    return 1;
  }

  if (files.isEmpty) {
    progress.fail('Font "$family" was not found on Google Fonts.');
    logger
      ..info('')
      ..info(
        'Check the exact name (and casing) at https://fonts.google.com. '
        'Multi-word names work too, e.g. "forgekit add font \'Open Sans\'".',
      );
    return 1;
  }

  progress.complete(
    'Downloaded ${files.length} weight(s) of "$family".',
  );

  // 2. Register the files in pubspec.yaml.
  final pubProgress = logger.progress('Registering "$family" in pubspec.yaml');
  try {
    _registerInPubspec(family, files, projectDir: projectDir);
    pubProgress.complete('Registered "$family" in pubspec.yaml.');
  } on _FontException catch (e) {
    pubProgress.fail(e.message);
    return 1;
  }

  // 3. Wire the family into the app theme (best effort — never fatal).
  _wireIntoTheme(family, logger: logger, projectDir: projectDir);

  logger
    ..info('')
    ..info('Next steps:')
    ..info('  flutter pub get');
  return 0;
}

/// Downloads every available static weight of [family] as `.ttf` and writes
/// them under `<projectDir>/assets/fonts/<Family>/`.
Future<List<_FontFile>> _downloadFamily(
  String family, {
  required String projectDir,
}) async {
  final client = http.Client();
  final downloaded = <_FontFile>[];
  try {
    final destDir = Directory(
      p.join(projectDir, 'assets', 'fonts', family.replaceAll(' ', '')),
    );

    for (final entry in _weightLabels.entries) {
      final weight = entry.key;
      final label = entry.value;

      final ttfUrl = await _resolveTtfUrl(client, family, weight);
      if (ttfUrl == null) continue; // weight not offered by this family

      final bytes = await client.readBytes(Uri.parse(ttfUrl));
      destDir.createSync(recursive: true);

      final fileName = '${family.replaceAll(' ', '')}-$label.ttf';
      final file = File(p.join(destDir.path, fileName));
      file.writeAsBytesSync(bytes);

      // pubspec asset paths are POSIX-style and relative to the project root.
      final assetPath = 'assets/fonts/${family.replaceAll(' ', '')}/$fileName';
      downloaded.add(_FontFile(weight: weight, asset: assetPath));
    }
  } finally {
    client.close();
  }
  return downloaded;
}

/// Asks the Google Fonts `css2` endpoint for a single [weight] of [family] and
/// returns the `.ttf` URL, or `null` if that weight is not available.
///
/// The old-Android User-Agent is deliberate: modern agents get `woff2` (which
/// Flutter can't bundle), an ancient IE agent gets EOT, but an old-Android one
/// makes Google serve a plain `.ttf` per weight — exactly what Flutter wants.
Future<String?> _resolveTtfUrl(
  http.Client client,
  String family,
  int weight,
) async {
  final familyParam = family.replaceAll(' ', '+');
  final uri = Uri.parse(
    'https://fonts.googleapis.com/css2?family=$familyParam:wght@$weight',
  );

  final res = await client.get(
    uri,
    headers: const {
      'User-Agent': 'Mozilla/5.0 (Linux; U; Android 4.4.2; en-us) '
          'AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 '
          'Mobile Safari/534.30',
    },
  );
  if (res.statusCode != 200) return null;

  final match = RegExp(r'url\((https:\/\/[^)]+\.ttf)\)').firstMatch(res.body);
  return match?.group(1);
}

/// Adds (or replaces) the [family] entry under `flutter > fonts:` in
/// `pubspec.yaml`, preserving all other content and comments.
void _registerInPubspec(
  String family,
  List<_FontFile> files, {
  required String projectDir,
}) {
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw _FontException(
      'No pubspec.yaml found in "$projectDir". '
      'Run this from a Flutter project root.',
    );
  }

  final editor = YamlEditor(pubspec.readAsStringSync());

  final familyEntry = {
    'family': family,
    'fonts': [
      for (final f in files..sort((a, b) => a.weight.compareTo(b.weight)))
        {'asset': f.asset, 'weight': f.weight},
    ],
  };

  // Read any existing fonts list and merge, replacing a same-named family.
  final existing = _plain(_tryParse(editor, ['flutter', 'fonts']));
  final merged = <dynamic>[
    if (existing is List)
      ...existing.where((e) => e is Map && e['family'] != family),
    familyEntry,
  ];

  if (_tryParse(editor, ['flutter']) == null) {
    editor.update(['flutter'], {'fonts': merged});
  } else {
    editor.update(['flutter', 'fonts'], merged);
  }

  pubspec.writeAsStringSync(editor.toString());
}

/// Sets `fontFamily: '<family>'` on the generated `ThemeData`.
///
/// Best effort: if the standard theme file isn't present or doesn't match, we
/// print the manual step instead of failing the whole command.
void _wireIntoTheme(
  String family, {
  required Logger logger,
  required String projectDir,
}) {
  final themeFile = File(
    p.join(
      projectDir,
      'lib',
      'core',
      'presentation',
      'theme',
      'app_theme.dart',
    ),
  );

  if (!themeFile.existsSync()) {
    logger
      ..info('')
      ..info(
        'Could not find app_theme.dart — set the font manually, e.g.\n'
        "  ThemeData(fontFamily: '$family', ...)",
      );
    return;
  }

  var content = themeFile.readAsStringSync();
  if (content.contains('fontFamily:')) {
    content = content.replaceAll(
      RegExp("fontFamily:\\s*'[^']*'"),
      "fontFamily: '$family'",
    );
  } else if (content.contains('useMaterial3: true,')) {
    content = content.replaceAll(
      'useMaterial3: true,',
      "useMaterial3: true,\n      fontFamily: '$family',",
    );
  } else {
    logger
      ..info('')
      ..info(
        "Set the font manually in app_theme.dart: ThemeData(fontFamily: '$family', ...)",
      );
    return;
  }

  themeFile.writeAsStringSync(content);
  logger.info("Set fontFamily: '$family' in app_theme.dart.");
}

/// Parses [path] from [editor], returning `null` if the path is absent.
YamlNode? _tryParse(YamlEditor editor, List<Object?> path) {
  try {
    return editor.parseAt(path);
  } on ArgumentError {
    return null;
  }
}

/// Recursively converts YAML nodes into plain Dart maps/lists.
dynamic _plain(dynamic node) {
  if (node is YamlMap) {
    return {
      for (final e in node.nodes.entries) e.key.toString(): _plain(e.value),
    };
  }
  if (node is YamlList) return node.map(_plain).toList();
  if (node is YamlScalar) return node.value;
  return node;
}

/// Normalizes user input into a Google Fonts family name.
///
/// `roboto` → `Roboto`, `open_sans`/`open-sans` → `Open Sans`. Words that
/// already contain an uppercase letter are left untouched so exact names like
/// `PT Sans` or `IBM Plex Sans` survive.
String normalizeFamily(String input) {
  final cleaned = input.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (cleaned.isEmpty) return '';
  return cleaned.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    final hasUpper = word != word.toLowerCase();
    return hasUpper ? word : word[0].toUpperCase() + word.substring(1);
  }).join(' ');
}

/// The static weights Forge attempts to fetch, mapped to their Flutter labels.
const Map<int, String> _weightLabels = {
  100: 'Thin',
  200: 'ExtraLight',
  300: 'Light',
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
  900: 'Black',
};

class _FontFile {
  const _FontFile({required this.weight, required this.asset});
  final int weight;
  final String asset;
}

class _FontException implements Exception {
  const _FontException(this.message);
  final String message;
}
