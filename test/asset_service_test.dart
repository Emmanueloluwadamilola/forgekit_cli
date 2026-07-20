import 'dart:io';

import 'package:forgekit/src/asset_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory sourceRoot;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_asset_project_');
    sourceRoot = Directory.systemTemp.createTempSync('forgekit_asset_source_');
    logger = Logger(level: Level.quiet);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ">=3.5.4 <4.0.0"
flutter:
  uses-material-design: true
''');
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
    if (sourceRoot.existsSync()) sourceRoot.deleteSync(recursive: true);
  });

  test('rejects traversal in the asset destination', () async {
    final source = File(p.join(sourceRoot.path, 'logo.png'))
      ..writeAsBytesSync([1, 2, 3]);

    final result = await addAsset(
      sourcePath: source.path,
      logger: logger,
      root: root,
      dir: '../../../outside',
    );

    expect(result, 1);
    expect(
      File(p.join(root.parent.path, 'outside', 'logo.png')).existsSync(),
      isFalse,
    );
  });

  test('uses the architecture resource path and escapes Dart interpolation',
      () async {
    final source = File(p.join(sourceRoot.path, r'price$icon.png'))
      ..writeAsBytesSync([1, 2, 3]);

    final result = await addAsset(
      sourcePath: source.path,
      logger: logger,
      root: root,
    );

    expect(result, 0);
    final drawables = File(
      p.join(root.path, 'lib', 'ui', 'core', 'resources', 'drawables.dart'),
    ).readAsStringSync();
    expect(drawables, contains(r'assets/images/price\$icon.png'));
  });
}
