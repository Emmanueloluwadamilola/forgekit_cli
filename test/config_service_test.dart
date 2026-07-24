import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/config_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ForgeKitConfig', () {
    test('round-trips supported project settings', () {
      const original = ForgeKitConfig(
        architecture: 'modular',
        stateManagement: 'riverpod',
        router: 'modular',
        dependencyInjection: 'flutter_modular',
        models: 'json_serializable',
        apiClient: 'retrofit',
        minimumCoverage: 90,
        format: false,
        runBuildRunner: false,
      );

      final parsed = ForgeKitConfig.fromYaml(original.toYaml());

      expect(parsed.architecture, 'modular');
      expect(parsed.stateManagement, 'riverpod');
      expect(parsed.router, 'modular');
      expect(parsed.dependencyInjection, 'flutter_modular');
      expect(parsed.minimumCoverage, 90);
      expect(parsed.format, isFalse);
      expect(parsed.runBuildRunner, isFalse);
    });

    test('rejects unknown state-management values', () {
      expect(
        () => ForgeKitConfig.fromYaml('''
version: 1
state_management: redux
'''),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            contains('provider, riverpod, bloc, cubit'),
          ),
        ),
      );
    });

    test('reads the legacy forgekit state name as provider', () {
      final config = ForgeKitConfig.fromYaml('''
version: 1
state_management: forgekit
''');

      expect(config.stateManagement, 'provider');
      expect(config.toYaml(), contains('state_management: provider'));
    });

    test('sets nested generation values', () {
      final config = const ForgeKitConfig()
          .setValue('generation.build-runner', 'false')
          .setValue('testing.coverage', '95');

      expect(config.runBuildRunner, isFalse);
      expect(config.minimumCoverage, 95);
    });

    test('rejects recognized but unsupported generation backends', () {
      expect(
        () => ForgeKitConfig.fromYaml('''
version: 1
models: freezed
'''),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('models "freezed" is recognized'),
              contains('refuses this configuration'),
            ),
          ),
        ),
      );
      expect(
        () => ForgeKitConfig.fromYaml('''
version: 1
api_client: dio
'''),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            contains('api_client "dio" is recognized'),
          ),
        ),
      );
      expect(
        () => ForgeKitConfig.fromYaml('''
version: 1
dependency_injection: get_it
'''),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            contains('dependency_injection "get_it" is recognized'),
          ),
        ),
      );
    });

    test('enforces architecture backend compatibility', () {
      expect(
        () => const ForgeKitConfig(
          architecture: 'modular',
          router: 'modular',
        ).validate(),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            contains('requires dependency_injection "flutter_modular"'),
          ),
        ),
      );
      expect(
        () => const ForgeKitConfig(router: 'modular').validate(),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            contains('requires architecture "modular"'),
          ),
        ),
      );
    });
  });

  group('detectForgeKitConfig', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('forgekit_config_test_');
      Directory(p.join(root.path, 'lib')).createSync();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('detects Riverpod and GoRouter dependencies', () {
      _writePubspec(root, '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  go_router: ^14.0.0
''');

      final config = detectForgeKitConfig(root: root);

      expect(config.stateManagement, 'riverpod');
      expect(config.router, 'go_router');
      expect(config.dependencyInjection, 'injectable');
      expect(config.models, 'json_serializable');
      expect(config.apiClient, 'retrofit');
    });

    test('distinguishes Bloc from Cubit source', () {
      _writePubspec(root, '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^9.1.0
''');
      File(p.join(root.path, 'lib', 'counter_bloc.dart')).writeAsStringSync(
        'class CounterBloc extends Bloc<CounterEvent, CounterState> {}',
      );

      expect(detectForgeKitConfig(root: root).stateManagement, 'bloc');

      File(p.join(root.path, 'lib', 'counter_bloc.dart')).writeAsStringSync(
        'class CounterCubit extends Cubit<int> {}',
      );
      expect(detectForgeKitConfig(root: root).stateManagement, 'cubit');
    });

    test('detects the MVVM directory profile', () {
      _writePubspec(root, '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2
''');
      Directory(p.join(root.path, 'lib', 'ui')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'data')).createSync(recursive: true);

      final config = detectForgeKitConfig(root: root);

      expect(config.architecture, 'mvvm');
      expect(config.stateManagement, 'provider');
    });

    test('detects Flutter Modular routing and dependency injection', () {
      _writePubspec(root, '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_modular: ^7.1.0
  flutter_bloc: ^9.1.0
''');

      final config = detectForgeKitConfig(root: root);

      expect(config.architecture, 'modular');
      expect(config.router, 'modular');
      expect(config.dependencyInjection, 'flutter_modular');
    });
  });

  test('modular create rejects a separate router option', () async {
    final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

    expect(
      await runner.run([
        'create',
        'app',
        'sample_app',
        '--architecture',
        'modular',
        '--router',
        'named',
        '--state-management',
        'provider',
      ]),
      1,
    );
  });

  test('create app accepts comma-separated non-interactive platforms', () {
    final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

    final results = runner.parse([
      'create',
      'app',
      'sample_app',
      '--architecture',
      'clean',
      '--state-management',
      'provider',
      '--router',
      'named',
      '--platforms',
      'android,web',
    ]);
    final appResults = results.command!.command!;

    expect(appResults['platforms'], ['android', 'web']);
    expect(appResults.wasParsed('platforms'), isTrue);
  });

  test('create app rejects paths and existing destinations before generation',
      () async {
    final root = Directory.systemTemp.createTempSync('forgekit_create_guard_');
    final original = Directory.current;
    Directory.current = root;
    try {
      final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));
      final options = [
        '--architecture',
        'clean',
        '--state-management',
        'provider',
        '--router',
        'named',
        '--platforms',
        'web',
      ];

      expect(await runner.run(['create', 'app', '../escape', ...options]), 1);
      expect(
        await runner.run([
          'create',
          'app',
          'unsafe_org_app',
          ...options,
          '--org',
          'com.example&whoami',
        ]),
        1,
      );

      Directory(p.join(root.path, 'existing_app')).createSync();
      expect(
        await runner.run(['create', 'app', 'existing_app', ...options]),
        1,
      );
    } finally {
      Directory.current = original;
      root.deleteSync(recursive: true);
    }
  });

  test('init supports dry-run without leaving forgekit.yaml behind', () async {
    final root = Directory.systemTemp.createTempSync('forgekit_init_test_');
    final original = Directory.current;
    _writePubspec(root, '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
''');
    Directory(p.join(root.path, 'lib')).createSync();
    Directory.current = root;
    try {
      final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

      expect(await runner.run(['init', '--dry-run']), 0);
      expect(
        File(p.join(root.path, forgeKitConfigFileName)).existsSync(),
        isFalse,
      );

      expect(await runner.run(['init']), 0);
      expect(loadForgeKitConfig(root: root).stateManagement, 'riverpod');
    } finally {
      Directory.current = original;
      root.deleteSync(recursive: true);
    }
  });

  test('doctor does not treat an adopted lean app as Clean', () async {
    final root = Directory.systemTemp.createTempSync('forgekit_lean_doctor_');
    final original = Directory.current;
    _writePubspec(root, '''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
''');
    final mainFile = File(p.join(root.path, 'lib', 'main.dart'));
    mainFile.parent.createSync(recursive: true);
    mainFile.writeAsStringSync('void main() {}');
    Directory.current = root;
    try {
      final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

      expect(await runner.run(['init']), 0);
      expect(loadForgeKitConfig(root: root).architecture, 'lean');
      expect(await runner.run(['doctor', '--fix']), 1);
      expect(Directory(p.join(root.path, 'lib', 'core')).existsSync(), isFalse);
    } finally {
      Directory.current = original;
      root.deleteSync(recursive: true);
    }
  });

  test('feature generation rejects the lean adoption profile before Mason',
      () async {
    final root = Directory.systemTemp.createTempSync('forgekit_lean_feature_');
    final original = Directory.current;
    _writePubspec(root, 'name: sample_app\n');
    File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync(
      const ForgeKitConfig(architecture: 'lean').toYaml(),
    );
    Directory.current = root;
    try {
      final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

      expect(
        await runner.run(['add', 'feature', 'orders', '--no-build-runner']),
        1,
      );
      expect(Directory(p.join(root.path, 'lib')).existsSync(), isFalse);
    } finally {
      Directory.current = original;
      root.deleteSync(recursive: true);
    }
  });
}

void _writePubspec(Directory root, String contents) {
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync(contents.trimLeft());
}
