import 'dart:io';

import 'package:forgekit/src/flavor_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_flavor_');
    logger = Logger(level: Level.quiet);
    File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync('''
version: 1
architecture: clean
state_management: provider
router: named
dependency_injection: injectable
models: json_serializable
api_client: retrofit
''');
    Directory(p.join(root.path, 'lib')).createSync();
    File(p.join(root.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {}
''');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('generates valid Dart for multiple flavors', () async {
    expect(
      await addFlavors(
        flavors: const ['dev', 'prod'],
        logger: logger,
        root: root,
      ),
      0,
    );

    final config = File(
      p.join(root.path, 'lib', 'core', 'config', 'flavor_config.dart'),
    );
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['format', '--output=none', config.path],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(config.readAsStringSync(), contains('case Flavor.prod:'));
  });

  test('rejects duplicate flavor names before writing', () async {
    expect(
      await addFlavors(
        flavors: const ['dev', 'dev'],
        logger: logger,
        root: root,
      ),
      1,
    );
    expect(
      Directory(p.join(root.path, 'lib', 'core', 'config')).existsSync(),
      isFalse,
    );
  });

  test('normalizes a Dart keyword into a safe enum value', () async {
    expect(
      await addFlavors(
        flavors: const ['case'],
        logger: logger,
        root: root,
      ),
      0,
    );
    final config = File(
      p.join(root.path, 'lib', 'core', 'config', 'flavor_config.dart'),
    );
    expect(config.readAsStringSync(), contains('enum Flavor { caseValue }'));
  });
}
