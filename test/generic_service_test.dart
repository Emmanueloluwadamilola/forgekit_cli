import 'dart:io';

import 'package:forgekit/src/generic_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_service_test_');
    logger = Logger(level: Level.quiet);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('generates, registers, and initializes a Clean service', () async {
    _writeProject(root, architecture: 'clean', mainSource: _getItMain);

    final result = await addGenericService(
      name: 'analytics',
      root: root,
      logger: logger,
      runBuildRunner: false,
      runPackageCommands: false,
    );

    expect(result, 0);
    final service = _read(root, 'lib/services/analytics_service.dart');
    expect(service, contains('@lazySingleton'));
    expect(service, contains('class AnalyticsService'));
    expect(service, contains('Future<void> init() async'));
    expect(service, contains('if (_initialized) return;'));

    final main = _read(root, 'lib/main.dart');
    expect(main, contains('await getIt<AnalyticsService>().init();'));
    expect(
      main.indexOf('await getIt<AnalyticsService>().init();'),
      lessThan(main.indexOf('runApp(')),
    );
    _expectDartParses(root, [
      'lib/services/analytics_service.dart',
      'lib/main.dart',
    ]);
  });

  test('uses one registered and initialized instance for Modular', () async {
    _writeProject(root, architecture: 'modular', mainSource: _modularMain);
    _write(root, 'lib/app/app_module.dart', _modularModule);

    final result = await addGenericService(
      name: 'analytics',
      root: root,
      logger: logger,
      runBuildRunner: true,
      runPackageCommands: false,
    );

    expect(result, 0);
    final service = _read(root, 'lib/services/analytics_service.dart');
    expect(service, isNot(contains('injectable')));
    expect(service, contains('final analyticsService = AnalyticsService();'));
    expect(
      _read(root, 'lib/app/app_module.dart'),
      contains('..addInstance<AnalyticsService>(analyticsService)'),
    );
    expect(
      _read(root, 'lib/main.dart'),
      contains('await analyticsService.init();'),
    );
    _expectDartParses(root, [
      'lib/services/analytics_service.dart',
      'lib/app/app_module.dart',
      'lib/main.dart',
    ]);
  });

  test('does not overwrite an existing generic service', () async {
    _writeProject(root, architecture: 'clean', mainSource: _getItMain);
    final service = _write(
      root,
      'lib/services/analytics_service.dart',
      '// custom implementation\n',
    );

    final result = await addGenericService(
      name: 'analytics',
      root: root,
      logger: logger,
      runBuildRunner: false,
      runPackageCommands: false,
    );

    expect(result, 1);
    expect(service.readAsStringSync(), '// custom implementation\n');
  });
}

void _writeProject(
  Directory root, {
  required String architecture,
  required String mainSource,
}) {
  _write(root, 'pubspec.yaml', '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
''');
  _write(root, 'forgekit.yaml', '''
version: 1
architecture: $architecture
state_management: provider
router: ${architecture == 'modular' ? 'modular' : 'named'}
dependency_injection: ${architecture == 'modular' ? 'flutter_modular' : 'injectable'}
models: json_serializable
api_client: retrofit
generation:
  format: true
  build_runner: true
''');
  _write(root, 'lib/main.dart', mainSource);
}

File _write(Directory root, String relativePath, String source) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
  return file;
}

String _read(Directory root, String path) =>
    File(p.join(root.path, path)).readAsStringSync();

void _expectDartParses(Directory root, List<String> paths) {
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['format', '--output=none', ...paths],
    workingDirectory: root.path,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

const _getItMain = '''
import 'package:flutter/material.dart';

import 'core/di/core_module_container.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  // forgekit:service-initializers
  runApp(const App());
}
''';

const _modularMain = '''
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'app/app.dart';
import 'app/app_module.dart';

void main() {
  runApp(ModularApp(module: appModule, child: const App()));
}
''';

const _modularModule = '''
import 'package:flutter_modular/flutter_modular.dart';

final appModule = createModule(
  register: (c) {
    c
      // forgekit:services
      ;
  },
);
''';
