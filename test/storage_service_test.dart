import 'dart:io';

import 'package:forgekit/src/storage_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory root;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_storage_test_');
    logger = Logger(level: Level.quiet);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('generates and bootstraps a SharedPreferences service for Clean',
      () async {
    _writeProject(root, architecture: 'clean', mainSource: _getItMain('core'));

    final result = await addStorageService(
      name: 'local_storage',
      driver: 'shared_preferences',
      root: root,
      logger: logger,
      runBuildRunner: true,
      runPackageCommands: false,
    );

    expect(result, 0);
    expect(_dependency(root, 'shared_preferences'), '^2.5.5');

    final service = _read(
      root,
      'lib/services/local_storage_service.dart',
    );
    expect(service, contains('@lazySingleton'));
    expect(service, contains('class LocalStorageService'));
    expect(service, contains('SharedPreferencesAsync'));
    expect(service, isNot(contains('SharedPreferences.getInstance()')));
    expect(service, contains('Future<void> setString'));
    expect(service, contains('Future<List<String>?> getStringList'));
    expect(service, contains('Future<void> clear({Set<String>? allowList})'));

    final main = _read(root, 'lib/main.dart');
    expect(
      main,
      contains(
        "import 'package:sample_app/services/local_storage_service.dart';",
      ),
    );
    expect(
      main,
      contains('await getIt<LocalStorageService>().init();'),
    );
    expect(
      main.indexOf('await getIt<LocalStorageService>().init();'),
      lessThan(main.indexOf('runApp(')),
    );
    _expectDartParses(root, [
      'lib/services/local_storage_service.dart',
      'lib/main.dart',
    ]);
  });

  test('generates secure typed helpers and preserves an existing dependency',
      () async {
    _writeProject(
      root,
      architecture: 'mvvm',
      mainSource: _getItMain('config'),
      extraDependency: 'flutter_secure_storage: ^10.3.1',
    );

    final result = await addStorageService(
      name: 'secure_storage',
      driver: 'flutter_secure_storage',
      root: root,
      logger: logger,
      runBuildRunner: false,
      runPackageCommands: false,
    );

    expect(result, 0);
    expect(_dependency(root, 'flutter_secure_storage'), '^10.3.1');

    final service = _read(
      root,
      'lib/services/secure_storage_service.dart',
    );
    expect(service, contains('class SecureStorageService'));
    expect(service, contains('await _storage.readAll();'));
    expect(service, contains('Future<void> setString'));
    expect(service, contains('Future<bool?> getBool'));
    expect(service, contains('Future<List<String>?> getStringList'));
    expect(service, contains('Future<void> clear()'));

    final main = _read(root, 'lib/main.dart');
    expect(
      main,
      contains('await getIt<SecureStorageService>().init();'),
    );
    _expectDartParses(root, [
      'lib/services/secure_storage_service.dart',
      'lib/main.dart',
    ]);
  });

  test('registers and initializes the same service instance for Modular',
      () async {
    _writeProject(
      root,
      architecture: 'modular',
      mainSource: _modularMain,
    );
    final appModule = File(p.join(root.path, 'lib', 'app', 'app_module.dart'));
    appModule.parent.createSync(recursive: true);
    appModule.writeAsStringSync(_modularModule);

    final result = await addStorageService(
      name: 'local_storage',
      driver: 'shared_preferences',
      root: root,
      logger: logger,
      runBuildRunner: true,
      runPackageCommands: false,
    );

    expect(result, 0);
    final service = _read(
      root,
      'lib/services/local_storage_service.dart',
    );
    expect(service, isNot(contains('injectable')));
    expect(
      service,
      contains('final localStorageService = LocalStorageService();'),
    );

    final module = appModule.readAsStringSync();
    expect(
      module,
      contains(
        "import 'package:sample_app/services/local_storage_service.dart';",
      ),
    );
    expect(
      module,
      contains(
        '..addInstance<LocalStorageService>(localStorageService)',
      ),
    );

    final main = _read(root, 'lib/main.dart');
    expect(main, contains('Future<void> main() async {'));
    expect(main, contains('WidgetsFlutterBinding.ensureInitialized();'));
    expect(main, contains('await localStorageService.init();'));
    expect(
      main.indexOf('await localStorageService.init();'),
      lessThan(main.indexOf('runApp(')),
    );
    _expectDartParses(root, [
      'lib/services/local_storage_service.dart',
      'lib/app/app_module.dart',
      'lib/main.dart',
    ]);
  });

  test('rejects an existing dependency that excludes the secure baseline',
      () async {
    _writeProject(
      root,
      architecture: 'clean',
      mainSource: _getItMain('core'),
      extraDependency: 'flutter_secure_storage: ^9.2.4',
    );

    final result = await addStorageService(
      name: 'secure_storage',
      driver: 'flutter_secure_storage',
      root: root,
      logger: logger,
      runBuildRunner: false,
      runPackageCommands: false,
    );

    expect(result, 1);
    expect(
      File(p.join(root.path, 'lib', 'services', 'secure_storage_service.dart'))
          .existsSync(),
      isFalse,
    );
  });

  test('does not overwrite an existing service', () async {
    _writeProject(root, architecture: 'clean', mainSource: _getItMain('core'));
    final service = File(
      p.join(root.path, 'lib', 'services', 'local_storage_service.dart'),
    );
    service.parent.createSync(recursive: true);
    service.writeAsStringSync('// user implementation\n');

    final result = await addStorageService(
      name: 'local_storage',
      driver: 'shared_preferences',
      root: root,
      logger: logger,
      runBuildRunner: true,
      runPackageCommands: false,
    );

    expect(result, 1);
    expect(service.readAsStringSync(), '// user implementation\n');
  });
}

void _writeProject(
  Directory root, {
  required String architecture,
  required String mainSource,
  String? extraDependency,
}) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
${extraDependency == null ? '' : '  $extraDependency\n'}
'''
        .trimLeft(),
  );
  File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync(
    '''
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
'''
        .trimLeft(),
  );
  final main = File(p.join(root.path, 'lib', 'main.dart'));
  main.parent.createSync(recursive: true);
  main.writeAsStringSync(mainSource);
}

Object? _dependency(Directory root, String name) {
  final yaml = loadYaml(_read(root, 'pubspec.yaml')) as YamlMap;
  return (yaml['dependencies'] as YamlMap)[name];
}

String _read(Directory root, String path) {
  return File(p.join(root.path, path)).readAsStringSync();
}

void _expectDartParses(Directory root, List<String> paths) {
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['format', '--output=none', ...paths],
    workingDirectory: root.path,
  );
  expect(
    result.exitCode,
    0,
    reason: '${result.stdout}\n${result.stderr}',
  );
}

String _getItMain(String profile) => '''
import 'package:flutter/material.dart';

import '${profile == 'core' ? 'core/di/core_module_container.dart' : 'config/di/dependencies.dart'}';
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
import 'package:dio/dio.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'home_page.dart';

final appModule = createModule(
  register: (c) {
    c
      ..addLazySingleton<Dio>(Dio.new)
      // forgekit:services
      ..route('/', child: (_, __) => const HomePage())
      // forgekit:modules
      ;
  },
);
''';
