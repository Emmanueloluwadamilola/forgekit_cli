import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/uninstall_service.dart';
import 'package:forgekit/src/utils.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory originalDirectory;
  late Directory root;
  late Logger logger;

  setUp(() {
    originalDirectory = Directory.current;
    root = Directory.systemTemp.createTempSync('forgekit_uninstall_test_');
    logger = Logger(level: Level.quiet);
    debugTerminalOverride = false;
  });

  tearDown(() {
    debugTerminalOverride = null;
    Directory.current = originalDirectory;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('isUnsafeUninstallTarget', () {
    test('refuses the filesystem root and its immediate children', () {
      expect(isUnsafeUninstallTarget(Directory('/')), isTrue);
      expect(isUnsafeUninstallTarget(Directory('/Users')), isTrue);
      expect(isUnsafeUninstallTarget(Directory('/home')), isTrue);
    });

    test('refuses the home directory itself', () {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      if (home == null || home.trim().isEmpty) return;

      expect(isUnsafeUninstallTarget(Directory(home)), isTrue);
      // A trailing separator must not defeat the comparison.
      expect(isUnsafeUninstallTarget(Directory('$home/')), isTrue);
    });

    test('allows a real ForgeKit data directory', () {
      final home = Platform.environment['HOME'];
      if (home == null || home.trim().isEmpty) return;

      expect(
        isUnsafeUninstallTarget(Directory(p.join(home, '.forgekit'))),
        isFalse,
      );
    });

    test('allows a temp directory, which the tests below delete', () {
      expect(isUnsafeUninstallTarget(root), isFalse);
    });
  });

  group('planUninstall', () {
    test('always ends by deactivating the executable', () {
      final plan = planUninstall(
        keepWidgets: false,
        removeMason: false,
        cleanProject: false,
      );

      expect(plan.steps, isNotEmpty);
      expect(plan.steps.last.detail, contains('deactivate forgekit'));
    });

    test('omits Mason unless asked', () {
      final plan = planUninstall(
        keepWidgets: false,
        removeMason: false,
        cleanProject: false,
      );

      expect(
        plan.steps.any((step) => step.label.contains('Mason CLI')),
        isFalse,
      );
    });

    test('includes project files only when they exist and are requested', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: app\n');
      File(p.join(root.path, 'forgekit.yaml'))
          .writeAsStringSync('version: 1\n');
      Directory(p.join(root.path, '.forgekit')).createSync();

      final withFlag = planUninstall(
        keepWidgets: false,
        removeMason: false,
        cleanProject: true,
        projectRoot: root,
      );
      expect(
        withFlag.steps.where((s) => s.detail.contains('forgekit')).length,
        greaterThanOrEqualTo(2),
      );

      final withoutFlag = planUninstall(
        keepWidgets: false,
        removeMason: false,
        cleanProject: false,
        projectRoot: root,
      );
      expect(
        withoutFlag.steps.any((s) => s.detail.endsWith('forgekit.yaml')),
        isFalse,
      );
    });
  });

  group('runUninstall', () {
    test('refuses an unsafe target and reports the failure', () async {
      // Deliberately a path that is unsafe by the guard's rules AND does not
      // exist. Pointing this at the real home directory would mean a regression
      // in the guard deletes the developer's home while running the tests.
      final unsafe = Directory('/forgekit-unsafe-target-should-not-exist');
      expect(isUnsafeUninstallTarget(unsafe), isTrue);
      expect(unsafe.existsSync(), isFalse);

      final code = await runUninstall(
        logger: logger,
        plan: UninstallPlan(
          registeredBricks: const [],
          forgekitHomeDir: unsafe,
          widgetsDir: null,
          masonCacheDir: null,
          projectConfig: null,
          projectState: null,
          keepWidgets: false,
          removeMason: false,
          cleanProject: false,
        ),
        runProcesses: false,
      );

      expect(code, 1);
    });

    test('removes the data directory', () async {
      final home = Directory(p.join(root.path, '.forgekit'));
      Directory(p.join(home.path, 'bricks')).createSync(recursive: true);

      final code = await runUninstall(
        logger: logger,
        plan: UninstallPlan(
          registeredBricks: const [],
          forgekitHomeDir: home,
          widgetsDir: null,
          masonCacheDir: null,
          projectConfig: null,
          projectState: null,
          keepWidgets: false,
          removeMason: false,
          cleanProject: false,
        ),
        runProcesses: false,
      );

      expect(code, 0);
      expect(home.existsSync(), isFalse);
    });

    test('preserves the widget library with keepWidgets', () async {
      final home = Directory(p.join(root.path, '.forgekit'));
      final widgets = Directory(p.join(home.path, 'widgets'));
      Directory(p.join(home.path, 'bricks')).createSync(recursive: true);
      widgets.createSync(recursive: true);
      File(p.join(widgets.path, 'badge.dart')).writeAsStringSync('// mine\n');
      File(p.join(home.path, 'registry.json')).writeAsStringSync('{}');

      final code = await runUninstall(
        logger: logger,
        plan: UninstallPlan(
          registeredBricks: const [],
          forgekitHomeDir: home,
          widgetsDir: widgets,
          masonCacheDir: null,
          projectConfig: null,
          projectState: null,
          keepWidgets: true,
          removeMason: false,
          cleanProject: false,
        ),
        runProcesses: false,
      );

      expect(code, 0);
      expect(File(p.join(widgets.path, 'badge.dart')).existsSync(), isTrue);
      expect(Directory(p.join(home.path, 'bricks')).existsSync(), isFalse);
      expect(File(p.join(home.path, 'registry.json')).existsSync(), isFalse);
    });

    test('removes the current project files when planned', () async {
      final config = File(p.join(root.path, 'forgekit.yaml'))
        ..writeAsStringSync('version: 1\n');
      final state = Directory(p.join(root.path, '.forgekit'))
        ..createSync(recursive: true);

      final code = await runUninstall(
        logger: logger,
        plan: UninstallPlan(
          registeredBricks: const [],
          forgekitHomeDir: null,
          widgetsDir: null,
          masonCacheDir: null,
          projectConfig: config,
          projectState: state,
          keepWidgets: false,
          removeMason: false,
          cleanProject: true,
        ),
        runProcesses: false,
      );

      expect(code, 0);
      expect(config.existsSync(), isFalse);
      expect(state.existsSync(), isFalse);
    });
  });

  group('uninstall command', () {
    test('--dry-run changes nothing and exits zero', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'uninstall',
        '--dry-run',
      ]);

      expect(result, 0);
    });

    test('refuses without --force in a non-interactive shell', () async {
      Directory.current = root;

      final result =
          await ForgeCommandRunner(logger: logger).run(['uninstall']);

      expect(result, 1);
    });

    test('--clean-project requires a project', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        'uninstall',
        '--clean-project',
        '--dry-run',
      ]);

      expect(result, 1);
    });

    test('is excluded from the global --dry-run allow-list', () async {
      Directory.current = root;

      // Machine-level, so a project generation transaction is meaningless.
      final result = await ForgeCommandRunner(logger: logger).run([
        '--dry-run',
        'uninstall',
      ]);

      expect(result, 1);
    });

    test('is excluded from the global --package allow-list', () async {
      Directory.current = root;

      final result = await ForgeCommandRunner(logger: logger).run([
        '--package',
        'anything',
        'uninstall',
      ]);

      expect(result, 1);
    });
  });
}
