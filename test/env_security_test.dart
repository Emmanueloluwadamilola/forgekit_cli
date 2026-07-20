import 'dart:convert';
import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/env_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File envFile;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_env_security_');
    envFile = File(p.join(root.path, 'assets', 'env', 'dev.json'));
    envFile.parent.createSync(recursive: true);
    envFile.writeAsStringSync('{"ENVIRONMENT":"dev"}\n');
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
dependencies:
  flutter:
    sdk: flutter
''');
    logger = Logger(level: Level.quiet);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('recognizes credential-like environment keys', () {
    expect(isPotentiallySensitiveEnvironmentKey('STRIPE_SECRET_KEY'), isTrue);
    expect(isPotentiallySensitiveEnvironmentKey('access-token'), isTrue);
    expect(isPotentiallySensitiveEnvironmentKey('API_BASE_URL'), isFalse);
    expect(isPotentiallySensitiveEnvironmentKey('ENABLE_LOGGING'), isFalse);
  });

  test('refuses to bundle a secret-like key by default', () async {
    final exitCode = await setEnvironmentValue(
      key: 'ACCESS_TOKEN',
      value: 'do-not-write',
      logger: logger,
      root: root,
      environment: 'dev',
    );

    expect(exitCode, 1);
    expect(envFile.readAsStringSync(), isNot(contains('do-not-write')));
  });

  test('requires explicit acknowledgement for a publishable client key',
      () async {
    final exitCode = await setEnvironmentValue(
      key: 'MAPS_API_KEY',
      value: 'public-provider-key',
      logger: logger,
      root: root,
      environment: 'dev',
      allowPublicValue: true,
    );

    expect(exitCode, 0);
    final decoded = jsonDecode(envFile.readAsStringSync()) as Map;
    expect(decoded['MAPS_API_KEY'], 'public-provider-key');
    expect(
      findPotentiallySensitiveBundledEnvironmentKeys(root),
      {
        'assets/env/dev.json': ['MAPS_API_KEY'],
      },
    );
  });

  test('CLI transaction metadata never stores environment keys or values',
      () async {
    final original = Directory.current;
    Directory.current = root;
    try {
      final runner = ForgeCommandRunner(logger: logger);
      final exitCode = await runner.run([
        'set',
        'env',
        'API_BASE_URL',
        'https://not-recorded.example.com',
        '--environment',
        'dev',
      ]);

      expect(exitCode, 0);
      final manifest = jsonDecode(
        File(p.join(root.path, '.forgekit', 'manifest.json'))
            .readAsStringSync(),
      ) as Map;
      final transaction = File(
        p.join(
          root.path,
          '.forgekit',
          'backups',
          manifest['latestTransaction'],
          'transaction.json',
        ),
      ).readAsStringSync();
      expect(transaction, contains('forgekit set env'));
      expect(transaction, isNot(contains('API_BASE_URL')));
      expect(transaction, isNot(contains('not-recorded.example.com')));
    } finally {
      Directory.current = original;
    }
  });
}
