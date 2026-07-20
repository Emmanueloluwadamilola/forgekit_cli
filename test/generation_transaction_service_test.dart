import 'dart:convert';
import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/generation_transaction_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_transaction_test_');
    logger = Logger(level: Level.quiet);
    File(p.join(root.path, 'existing.txt')).writeAsStringSync('before\n');
    File(p.join(root.path, 'deleted.txt')).writeAsStringSync('keep me\n');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('dry-run reports and restores created, modified, and deleted files',
      () async {
    final transaction = await GenerationTransaction.begin(
      root: root,
      command: 'forgekit add feature orders --dry-run',
    );
    File(p.join(root.path, 'existing.txt')).writeAsStringSync('after\n');
    File(p.join(root.path, 'created.txt')).writeAsStringSync('new\n');
    File(p.join(root.path, 'deleted.txt')).deleteSync();

    final changes = await transaction.finish(
      success: true,
      dryRun: true,
      logger: logger,
    );

    expect(
      changes.map((change) => change.type),
      containsAll([
        GenerationChangeType.created,
        GenerationChangeType.modified,
        GenerationChangeType.deleted,
      ]),
    );
    expect(
      File(p.join(root.path, 'existing.txt')).readAsStringSync(),
      'before\n',
    );
    expect(
      File(p.join(root.path, 'deleted.txt')).readAsStringSync(),
      'keep me\n',
    );
    expect(File(p.join(root.path, 'created.txt')).existsSync(), isFalse);
    expect(Directory(p.join(root.path, '.forgekit')).existsSync(), isFalse);
    expect(File(p.join(root.path, '.gitignore')).existsSync(), isFalse);
  });

  test('failed generation restores project files', () async {
    final transaction = await GenerationTransaction.begin(
      root: root,
      command: 'forgekit add feature broken',
    );
    File(p.join(root.path, 'existing.txt')).writeAsStringSync('partial\n');
    File(p.join(root.path, 'partial.txt')).writeAsStringSync('partial\n');

    await transaction.finish(success: false, dryRun: false, logger: logger);

    expect(
      File(p.join(root.path, 'existing.txt')).readAsStringSync(),
      'before\n',
    );
    expect(File(p.join(root.path, 'partial.txt')).existsSync(), isFalse);
  });

  test('formats changed Dart files before recording the transaction', () async {
    final transaction = await GenerationTransaction.begin(
      root: root,
      command: 'forgekit add service clock',
    );
    final dartFile = File(p.join(root.path, 'clock.dart'))
      ..writeAsStringSync('class Clock{int now()=>1;}\n');

    await transaction.finish(
      success: true,
      dryRun: false,
      logger: logger,
      format: true,
    );

    expect(dartFile.readAsStringSync(), contains('class Clock {'));
    expect(dartFile.readAsStringSync(), contains('int now() => 1;'));
  });

  test('restores project files when formatting fails', () async {
    final transaction = await GenerationTransaction.begin(
      root: root,
      command: 'forgekit add service broken',
    );
    final invalid = File(p.join(root.path, 'broken.dart'))
      ..writeAsStringSync('class Broken {');

    await expectLater(
      transaction.finish(
        success: true,
        dryRun: false,
        logger: logger,
        format: true,
      ),
      throwsA(isA<GenerationTransactionException>()),
    );
    expect(invalid.existsSync(), isFalse);
  });

  test('records a manifest and performs drift-protected rollback', () async {
    final transaction = await GenerationTransaction.begin(
      root: root,
      command: 'forgekit add feature orders',
    );
    File(p.join(root.path, 'existing.txt')).writeAsStringSync('generated\n');
    final generated = File(p.join(root.path, 'generated.txt'))
      ..writeAsStringSync('generated\n');

    await transaction.finish(success: true, dryRun: false, logger: logger);

    final manifestFile = File(p.join(root.path, '.forgekit', 'manifest.json'));
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
    expect(
      File(p.join(root.path, '.gitignore')).readAsStringSync(),
      contains('.forgekit/'),
    );
    expect(manifest['latestTransaction'], isA<String>());
    expect(
      (manifest['generatedFiles'] as Map).keys,
      containsAll([
        'existing.txt',
        'generated.txt',
      ]),
    );
    expect(await showGenerationDiff(root: root, logger: logger), 0);

    generated.writeAsStringSync('human edit\n');
    expect(await showGenerationDiff(root: root, logger: logger), 1);
    expect(
      await rollbackLatestGeneration(root: root, logger: logger),
      1,
    );
    expect(generated.existsSync(), isTrue);

    expect(
      await rollbackLatestGeneration(root: root, logger: logger, force: true),
      0,
    );
    expect(generated.existsSync(), isFalse);
    expect(File(p.join(root.path, '.gitignore')).existsSync(), isFalse);
    expect(
      File(p.join(root.path, 'existing.txt')).readAsStringSync(),
      'before\n',
    );
  });

  group('normalizeDryRunOption', () {
    test('moves a trailing flag and rejects duplicates', () {
      expect(
        normalizeDryRunOption(['add', 'feature', 'orders', '--dry-run']),
        ['--dry-run', 'add', 'feature', 'orders'],
      );
      expect(
        () => normalizeDryRunOption(['--dry-run', 'doctor', '--dry-run']),
        throwsFormatException,
      );
    });
  });

  test('transaction command labels exclude arguments and option values', () {
    final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));
    final results = runner.parse([
      'set',
      'env',
      'ACCESS_TOKEN',
      'do-not-record-me',
      '--environment',
      'dev',
    ]);

    final label = transactionCommandLabel(results);

    expect(label, 'forgekit set env');
    expect(label, isNot(contains('ACCESS_TOKEN')));
    expect(label, isNot(contains('do-not-record-me')));
  });
}
