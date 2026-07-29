@TestOn('vm')
library;

import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/commands/create_command.dart';
import 'package:forgekit/src/utils.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end tests that drive the real [ForgeCommandRunner] the way a shell
/// does, rather than calling a service function directly.
///
/// This is the regression guard for the non-interactive code paths: a command
/// that reaches an unguarded prompt fails here instead of hanging in a user's CI
/// job.
///
/// [debugTerminalOverride] forces the no-terminal condition rather than relying
/// on the suite's actual stdio. `dart test` shares the process's terminal state,
/// so whether a suite sees a TTY depends on how it was launched — without the
/// override these tests would pass in CI and hang on a developer's machine.
///
/// Message wording is asserted against [missingCreateAppFlags] rather than
/// captured log output, so these tests stay independent of the logger.
void main() {
  late Directory originalDirectory;
  late Directory root;
  late Logger logger;

  setUp(() {
    originalDirectory = Directory.current;
    root = Directory.systemTemp.createTempSync('forgekit_e2e_test_');
    logger = Logger(level: Level.quiet);
    debugTerminalOverride = false;
  });

  tearDown(() {
    debugTerminalOverride = null;
    Directory.current = originalDirectory;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('missingCreateAppFlags', () {
    test('lists every prompted value when none are supplied', () {
      final missing = missingCreateAppFlags(
        architecture: null,
        router: null,
        stateManagement: null,
        platformsParsed: false,
      );

      // Reported together so the user fixes the invocation in one round trip.
      expect(missing, hasLength(4));
      expect(missing.join('\n'), contains('--architecture'));
      expect(missing.join('\n'), contains('--router'));
      expect(missing.join('\n'), contains('--state-management'));
      expect(missing.join('\n'), contains('--platforms'));
    });

    test('omits --router for the modular profile, which owns routing', () {
      final missing = missingCreateAppFlags(
        architecture: 'modular',
        router: null,
        stateManagement: 'bloc',
        platformsParsed: true,
      );

      expect(missing, isEmpty);
    });

    test('still requires --router for clean and mvvm', () {
      for (final architecture in ['clean', 'mvvm']) {
        expect(
          missingCreateAppFlags(
            architecture: architecture,
            router: null,
            stateManagement: 'provider',
            platformsParsed: true,
          ),
          ['--router named|go_router'],
          reason: '$architecture must choose a router',
        );
      }
    });

    test('is empty for a fully specified invocation', () {
      expect(
        missingCreateAppFlags(
          architecture: 'clean',
          router: 'go_router',
          stateManagement: 'provider',
          platformsParsed: true,
        ),
        isEmpty,
      );
    });
  });

  group('non-interactive safety', () {
    test('create app fails fast instead of prompting', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'create',
        'app',
        'sample_app',
      ]);

      expect(result, 1);
      // Nothing may be written before the invocation is complete.
      expect(Directory(p.join(root.path, 'sample_app')).existsSync(), isFalse);
    });

    test('create app validates its name before anything else', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'create',
        'app',
        'Not-A-Package',
      ]);

      expect(result, 1);
      expect(
        Directory(p.join(root.path, 'Not-A-Package')).existsSync(),
        isFalse,
      );
    });

    test('create app refuses an existing destination', () async {
      Directory(p.join(root.path, 'sample_app')).createSync();
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'create',
        'app',
        'sample_app',
        '--architecture',
        'clean',
        '--router',
        'named',
        '--state-management',
        'provider',
        '--platforms',
        'android',
      ]);

      expect(result, 1);
    });

    // `add model` is deliberately not covered here: its JSON read goes straight
    // to `stdin.readLineSync()`, which blocks on a real terminal no matter what
    // the override says. Piped input is the supported non-interactive path, so
    // exercising it needs a subprocess with redirected stdin rather than an
    // in-process call.

    test('add function fails fast without --method and --path', () async {
      _writeProject(root);
      _writeCleanFeature(root, 'orders');
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'add',
        'function',
        'orders',
        'fetch_orders',
      ]);

      expect(result, 1);
    });

    test('remove feature declines rather than prompting, keeping the feature',
        () async {
      _writeProject(root);
      _writeCleanFeature(root, 'orders');
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'remove',
        'feature',
        'orders',
      ]);

      expect(result, 1);
      expect(
        Directory(p.join(root.path, 'lib', 'features', 'orders')).existsSync(),
        isTrue,
      );
    });

    test('add firebase reports the flag that replaces its picker', () async {
      _writeProject(root);
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'add',
        'firebase',
      ]);

      expect(result, 1);
      expect(
        Directory(p.join(root.path, 'lib', 'services')).existsSync(),
        isFalse,
      );
    });

    test('add firebase refuses before flutterfire configure has run', () async {
      _writeProject(root);
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'add',
        'firebase',
        '--features',
        'push',
      ]);

      // lib/firebase_options.dart is absent, so generation must not start.
      expect(result, 1);
      expect(
        File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
        isNot(contains('firebase_core')),
      );
    });

    test('add service picks the generic driver rather than a storage driver',
        () async {
      // Needs a bootstrap to wire startup into, otherwise the command fails and
      // the transaction rolls back the very files this test inspects — which
      // would make the assertions unable to fail.
      _writeProject(root, format: false);
      _writeBootstrap(root);
      Directory.current = root;

      // Without a terminal `add service` cannot prompt for --driver, so the
      // fallback must resolve to `generic`. A storage driver would add its
      // package to pubspec.yaml, so the absence of those entries is the proof.
      final result = await ForgeCommandRunner(logger: logger).run([
        'add',
        'service',
        'session',
        '--no-build-runner',
      ]);

      expect(result, 0);
      expect(
        File(p.join(root.path, 'lib', 'services', 'session_service.dart'))
            .existsSync(),
        isTrue,
      );
      final pubspec =
          File(p.join(root.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('flutter_secure_storage')));
      expect(pubspec, isNot(contains('shared_preferences')));
    });
  });

  group('global flag allow-lists', () {
    test('--dry-run is rejected by non-transactional commands', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        '--dry-run',
        'workspace',
        'list',
      ]);

      expect(result, 1);
    });

    test('--dry-run is accepted by transactional commands', () async {
      _writeProject(root);
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        '--dry-run',
        'config',
        'show',
      ]);

      expect(result, 0);
    });

    test('--package is rejected by commands that do not support it', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        '--package',
        'anything',
        'create',
        'app',
        'sample_app',
      ]);

      expect(result, 1);
    });

    test('--version exits zero without needing a project', () async {
      Directory.current = root;

      final result =
          await ForgeCommandRunner(logger: logger).run(['--version']);

      expect(result, 0);
    });

    test('an unknown command exits non-zero', () async {
      Directory.current = root;

      final result =
          await ForgeCommandRunner(logger: logger).run(['nonexistent']);

      expect(result, 1);
    });

    test('an unknown flag exits non-zero rather than throwing', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'doctor',
        '--not-a-flag',
      ]);

      expect(result, 1);
    });
  });

  group('project discovery', () {
    test('generation commands require a pubspec', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'add',
        'screen',
        'orders',
        'order_detail',
      ]);

      expect(result, 1);
    });

    test('config show requires an explicit forgekit.yaml', () async {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: bare\n');
      Directory.current = root;

      final result =
          await ForgeCommandRunner(logger: logger).run(['config', 'show']);

      expect(result, 1);
    });

    test('the working directory is restored after a failed command', () async {
      Directory.current = root;
      final before = Directory.current.path;

      await ForgeCommandRunner(logger: logger).run(['config', 'show']);

      expect(Directory.current.path, before);
    });

    test('the working directory is restored after a successful command',
        () async {
      _writeProject(root);
      Directory.current = root;
      final before = Directory.current.path;

      await ForgeCommandRunner(logger: logger).run(['config', 'validate']);

      expect(Directory.current.path, before);
    });
  });
}

/// Writes the minimum Clean-profile project fixture.
///
/// Pass `format: false` for a test that keeps generated files: the transaction
/// otherwise shells out to `dart format`, which is slow and needs a working
/// Dart on PATH for no benefit to the assertion.
void _writeProject(Directory root, {bool format = true}) {
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
  format: $format
  build_runner: true
testing:
  coverage: 80
''');
}

/// Writes the `lib/main.dart` shape the service generator wires startup into.
///
/// `insertServiceInitialization` anchors on `await configureDependencies();` and
/// `addDartImport` needs at least one existing import line.
void _writeBootstrap(Directory root) {
  final mainFile = File(p.join(root.path, 'lib', 'main.dart'));
  mainFile.parent.createSync(recursive: true);
  mainFile.writeAsStringSync('''
import 'package:flutter/material.dart';

Future<void> main() async {
  await configureDependencies();
  runApp(const Placeholder());
}
''');
}

/// Writes the minimum Clean-profile feature skeleton the generators look for.
void _writeCleanFeature(Directory root, String feature) {
  final apiService = File(
    p.join(
      root.path,
      'lib',
      'features',
      feature,
      'data',
      'remote',
      'service',
      '${feature}_api_service.dart',
    ),
  );
  apiService.parent.createSync(recursive: true);
  final className = feature
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
  apiService.writeAsStringSync('abstract class ${className}ApiService {}\n');
}
