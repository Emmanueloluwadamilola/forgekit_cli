import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/config_service.dart';
import 'package:forgekit/src/coverage_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('detects Windows batch control characters in forwarded arguments', () {
    expect(hasUnsafeWindowsBatchCharacters('serializes an order'), isFalse);
    expect(hasUnsafeWindowsBatchCharacters('name&whoami'), isTrue);
    expect(hasUnsafeWindowsBatchCharacters('%PATH%'), isTrue);
  });

  test('test command parses coverage control and forwarded Flutter arguments',
      () {
    final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

    final results = runner.parse([
      'test',
      '--no-coverage',
      '--',
      'test/unit',
      '--name',
      'serializes an order',
    ]);
    final command = results.command!;

    expect(command['coverage'], isFalse);
    expect(command.rest, ['test/unit', '--name', 'serializes an order']);
  });

  group('parseLcov', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('forgekit_coverage_test_');
      Directory(p.join(root.path, 'lib')).createSync();
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('counts unique production lines and excludes generated files', () {
      final service = File(p.join(root.path, 'lib', 'src', 'service.dart'));
      service.parent.createSync(recursive: true);
      service.writeAsStringSync('void run() {}\n');
      File(p.join(root.path, 'lib', 'src', 'service.g.dart'))
          .writeAsStringSync('// generated\n');
      final summary = parseLcov(
        '''
SF:lib/src/service.dart
DA:10,1
DA:11,0
end_of_record
SF:${p.join(root.path, 'lib', 'src', 'service.dart')}
DA:11,2
DA:12,0
end_of_record
SF:lib/src/service.g.dart
DA:1,1
end_of_record
SF:test/service_test.dart
DA:1,1
end_of_record
''',
        projectRoot: root,
      );

      expect(summary.coveredLines, 2);
      expect(summary.totalLines, 3);
      expect(summary.percentage, closeTo(66.67, 0.01));
      expect(summary.unreportedFiles, isEmpty);
    });

    test('reports eligible production libraries omitted from LCOV', () {
      File(p.join(root.path, 'lib', 'loaded.dart'))
          .writeAsStringSync('void loaded() {}\n');
      File(p.join(root.path, 'lib', 'never_loaded.dart'))
          .writeAsStringSync('void neverLoaded() {}\n');
      File(p.join(root.path, 'lib', 'ignored.g.dart'))
          .writeAsStringSync('// generated\n');

      final summary = parseLcov(
        '''
SF:lib/loaded.dart
DA:1,1
end_of_record
''',
        projectRoot: root,
      );

      expect(summary.unreportedFiles, ['lib/never_loaded.dart']);
    });

    test('rejects malformed line records', () {
      expect(
        () => parseLcov('DA:1,1\n', projectRoot: root),
        throwsA(
          isA<CoverageException>().having(
            (error) => error.message,
            'message',
            contains('without a preceding SF record'),
          ),
        ),
      );
    });
  });

  group('runProjectTests', () {
    late Directory root;
    late Logger logger;

    setUp(() {
      root = Directory.systemTemp.createTempSync('forgekit_test_gate_');
      Directory(p.join(root.path, 'lib')).createSync();
      logger = Logger(level: Level.quiet);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('passes when tests succeed and coverage meets the threshold',
        () async {
      File(p.join(root.path, 'lib', 'service.dart'))
          .writeAsStringSync('void service() {}\n');
      late List<String> receivedArguments;

      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(minimumCoverage: 50),
        flutterTestArguments: const ['test/unit'],
        executor: (workingDirectory, arguments) async {
          expect(workingDirectory.path, root.path);
          receivedArguments = arguments;
          final report = File(p.join(root.path, 'coverage', 'lcov.info'));
          report.parent.createSync(recursive: true);
          report.writeAsStringSync('''
SF:lib/service.dart
DA:1,1
DA:2,0
end_of_record
''');
          return 0;
        },
      );

      expect(exitCode, 0);
      expect(receivedArguments, ['test', '--coverage', 'test/unit']);
    });

    test('fails when coverage is below the configured threshold', () async {
      File(p.join(root.path, 'lib', 'service.dart'))
          .writeAsStringSync('void service() {}\n');
      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(minimumCoverage: 51),
        executor: (_, __) async {
          final report = File(p.join(root.path, 'coverage', 'lcov.info'));
          report.parent.createSync(recursive: true);
          report.writeAsStringSync('''
SF:lib/service.dart
DA:1,1
DA:2,0
end_of_record
''');
          return 0;
        },
      );

      expect(exitCode, 1);
    });

    test('fails when an eligible production file is missing from LCOV',
        () async {
      File(p.join(root.path, 'lib', 'loaded.dart'))
          .writeAsStringSync('void loaded() {}\n');
      File(p.join(root.path, 'lib', 'missing.dart'))
          .writeAsStringSync('void missing() {}\n');

      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(minimumCoverage: 0),
        executor: (_, __) async {
          final report = File(p.join(root.path, 'coverage', 'lcov.info'));
          report.parent.createSync(recursive: true);
          report.writeAsStringSync('''
SF:lib/loaded.dart
DA:1,1
end_of_record
''');
          return 0;
        },
      );

      expect(exitCode, 1);
    });

    test('does not accept forwarded coverage options', () async {
      var invoked = false;

      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(),
        flutterTestArguments: const ['--coverage-path=custom.info'],
        executor: (_, __) async {
          invoked = true;
          return 0;
        },
      );

      expect(exitCode, 64);
      expect(invoked, isFalse);
    });

    test('preserves the Flutter test failure exit code', () async {
      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(),
        executor: (_, __) async => 7,
      );

      expect(exitCode, 7);
    });

    test('can run tests without collecting coverage', () async {
      late List<String> receivedArguments;

      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(),
        collectCoverage: false,
        flutterTestArguments: const ['test/unit'],
        executor: (_, arguments) async {
          receivedArguments = arguments;
          return 0;
        },
      );

      expect(exitCode, 0);
      expect(receivedArguments, ['test', 'test/unit']);
    });

    test('does not use a stale report when Flutter creates none', () async {
      final stale = File(p.join(root.path, 'coverage', 'lcov.info'));
      stale.parent.createSync(recursive: true);
      stale.writeAsStringSync('SF:lib/stale.dart\nDA:1,1\nend_of_record\n');

      final exitCode = await runProjectTests(
        root: root,
        logger: logger,
        config: const ForgeKitConfig(minimumCoverage: 0),
        executor: (_, __) async => 0,
      );

      expect(exitCode, 1);
      expect(stale.existsSync(), isFalse);
    });
  });
}
