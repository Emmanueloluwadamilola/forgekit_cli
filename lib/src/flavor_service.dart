import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'json_to_dart.dart';

/// Scaffolds Dart-side build flavors: a `FlavorConfig` (enum + per-flavor
/// config) and a `lib/main_<flavor>.dart` entrypoint for each flavor.
///
/// Native (Android/iOS) flavor wiring is printed as next steps — it is
/// project-specific and not edited automatically.
Future<int> addFlavors({
  required List<String> flavors,
  required Logger logger,
  required Directory root,
}) async {
  final names =
      flavors.map((f) => camelCase(f)).where((f) => f.isNotEmpty).toList();
  if (names.isEmpty) {
    logger.err(
      'Provide at least one flavor, e.g. "forgekit add flavor dev,prod".',
    );
    return 1;
  }

  final configFile = File(
    p.join(root.path, 'lib', 'core', 'config', 'flavor_config.dart'),
  );
  if (configFile.existsSync()) {
    logger.err('lib/core/config/flavor_config.dart already exists.');
    return 1;
  }

  final progress = logger.progress('Scaffolding flavors: ${names.join(', ')}');
  final written = <String>[];

  configFile.parent.createSync(recursive: true);
  configFile.writeAsStringSync(_flavorConfig(names));
  written.add(configFile.path);

  for (final name in names) {
    final entry = File(p.join(root.path, 'lib', 'main_$name.dart'));
    entry.writeAsStringSync(_entrypoint(name));
    written.add(entry.path);
  }

  progress.complete('Scaffolded ${names.length} flavor(s).');

  logger
    ..info('')
    ..info('Generated:')
    ..info(
      written.map((f) => '  ${p.relative(f, from: root.path)}').join('\n'),
    )
    ..info('')
    ..info('Run a flavor:')
    ..info('  flutter run -t lib/main_${names.first}.dart')
    ..info('')
    ..info('Fill in per-flavor values in flavor_config.dart, then (native):')
    ..info('  • Android — add productFlavors in android/app/build.gradle')
    ..info('  • iOS — add schemes/configurations in Xcode');
  return 0;
}

String _flavorConfig(List<String> names) {
  final b = StringBuffer()
    ..writeln('/// Build flavors. Initialized from the flavor entrypoints in')
    ..writeln('/// `lib/main_<flavor>.dart`.')
    ..writeln('enum Flavor { ${names.join(', ')} }')
    ..writeln()
    ..writeln('class FlavorConfig {')
    ..writeln('  FlavorConfig._();')
    ..writeln()
    ..writeln('  static late Flavor flavor;')
    ..writeln('  static late String name;')
    ..writeln('  static late String apiBaseUrl;')
    ..writeln()
    ..writeln('  static void init(Flavor f) {')
    ..writeln('    flavor = f;')
    ..writeln('    switch (f) {');
  for (final name in names) {
    b
      ..writeln('      case Flavor.$name:')
      ..writeln("        name = '$name';")
      ..writeln("        apiBaseUrl = 'https://$name.api.example.com';")
      ..writeln('    }');
  }
  b
    ..writeln('  }')
    ..writeln('}');
  return b.toString();
}

String _entrypoint(String name) {
  return '''
import 'core/config/flavor_config.dart';
import 'main.dart' as app;

/// Entrypoint for the "$name" flavor. Run with:
///   flutter run -t lib/main_$name.dart
void main() {
  FlavorConfig.init(Flavor.$name);
  app.main();
}
''';
}
