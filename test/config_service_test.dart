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
        router: 'go_router',
        dependencyInjection: 'riverpod',
        models: 'freezed',
        apiClient: 'dio',
        minimumCoverage: 90,
        format: false,
        runBuildRunner: false,
      );

      final parsed = ForgeKitConfig.fromYaml(original.toYaml());

      expect(parsed.architecture, 'modular');
      expect(parsed.stateManagement, 'riverpod');
      expect(parsed.router, 'go_router');
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
      expect(config.dependencyInjection, 'riverpod');
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
}

void _writePubspec(Directory root, String contents) {
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync(contents.trimLeft());
}
