import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/test_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory originalDirectory;
  late Directory root;
  late Logger logger;

  setUp(() {
    originalDirectory = Directory.current;
    root = Directory.systemTemp.createTempSync('forgekit_validation_test_');
    logger = Logger(level: Level.quiet);
  });

  tearDown(() {
    Directory.current = originalDirectory;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('starter widget refuses to write outside a Dart project', () async {
    Directory.current = root;

    final result = await ForgeCommandRunner(logger: logger).run([
      'add',
      'widget',
      'status_badge',
      '--starter',
    ]);

    expect(result, 1);
    expect(Directory(p.join(root.path, 'lib')).existsSync(), isFalse);
  });

  test('usecase refuses to create a missing feature', () async {
    _writeProject(root);
    Directory.current = root;

    final result = await ForgeCommandRunner(logger: logger).run([
      'add',
      'usecase',
      'missing_feature',
      'load_items',
    ]);

    expect(result, 1);
    expect(
      Directory(p.join(root.path, 'lib', 'features', 'missing_feature'))
          .existsSync(),
      isFalse,
    );
  });

  test('standalone test generators require their source artifacts', () async {
    _writeProject(root);

    expect(
      await addFeatureTests(
        feature: 'missing_feature',
        logger: logger,
        root: root,
      ),
      1,
    );
    expect(
      await addModelTest(
        name: 'missing_model',
        logger: logger,
        root: root,
      ),
      1,
    );
    expect(
      await addFunctionTest(
        feature: 'missing_feature',
        functionName: 'missing_call',
        logger: logger,
        root: root,
      ),
      1,
    );
    expect(Directory(p.join(root.path, 'test')).existsSync(), isFalse);
  });
}

void _writeProject(Directory root) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ">=3.8.0 <4.0.0"
''');
  File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync('''
version: 1
architecture: clean
state_management: provider
router: named
dependency_injection: injectable
models: json_serializable
api_client: retrofit
generation:
  format: true
  build_runner: true
testing:
  coverage: 80
''');
}
