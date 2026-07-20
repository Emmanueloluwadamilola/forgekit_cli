import 'dart:io';

import 'package:forgekit/src/feature_lifecycle_service.dart';
import 'package:forgekit/src/function_service.dart';
import 'package:forgekit/src/model_service.dart';
import 'package:forgekit/src/test_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_arch_support_');
    logger = Logger(level: Level.quiet);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: sample\n');
    File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync('''
version: 1
architecture: mvvm
state_management: provider
router: named
dependency_injection: injectable
models: json_serializable
api_client: retrofit
''');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('Clean-only semantic generators reject MVVM before prompting or writing',
      () async {
    expect(
      await addModel(name: 'account', logger: logger, root: root),
      1,
    );
    expect(
      await addFunction(
        feature: 'accounts',
        functionName: 'load_account',
        logger: logger,
        root: root,
      ),
      1,
    );
    expect(
      Directory(p.join(root.path, 'lib', 'features')).existsSync(),
      isFalse,
    );
  });

  test('Clean-only feature lifecycle rejects MVVM without touching files',
      () async {
    final userFile =
        File(p.join(root.path, 'lib', 'features', 'orders', 'keep.dart'));
    userFile.parent.createSync(recursive: true);
    userFile.writeAsStringSync('// user file\n');

    expect(
      await renameFeature(
        root: root,
        from: 'orders',
        to: 'purchases',
        logger: logger,
      ),
      1,
    );
    expect(
      await removeFeature(
        root: root,
        feature: 'orders',
        logger: logger,
        force: true,
      ),
      1,
    );
    expect(userFile.readAsStringSync(), '// user file\n');
  });

  test('Clean-only semantic test generators reject MVVM without writing',
      () async {
    expect(
      await addModelTest(name: 'account', logger: logger, root: root),
      1,
    );
    expect(
      await addFunctionTest(
        feature: 'accounts',
        functionName: 'load_account',
        logger: logger,
        root: root,
      ),
      1,
    );
    expect(Directory(p.join(root.path, 'test')).existsSync(), isFalse);
  });
}
