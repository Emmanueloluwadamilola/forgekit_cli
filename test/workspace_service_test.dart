import 'dart:io';

import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/workspace_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('discoverPubWorkspace', () {
    late Directory fixture;

    setUp(() {
      fixture = _createWorkspaceFixture();
    });

    tearDown(() {
      if (fixture.existsSync()) fixture.deleteSync(recursive: true);
    });

    test('discovers glob members and nested workspace packages', () async {
      final workspace = await discoverPubWorkspace(
        start: Directory(p.join(fixture.path, 'apps', 'mobile_app', 'lib')),
      );

      expect(
        _resolvedPath(workspace.root),
        _resolvedPath(fixture),
      );
      expect(
        workspace.packages.map((package) => package.name),
        containsAll([
          'workspace_root',
          'mobile_app',
          'platform_packages',
          'analytics_plugin',
        ]),
      );
      expect(
        workspace.packages
            .singleWhere((package) => package.name == 'mobile_app')
            .isFlutter,
        isTrue,
      );
    });

    test('resolves a Flutter package by name and relative path', () async {
      final workspace = await discoverPubWorkspace(start: fixture);

      final byName = workspace.resolvePackage('mobile_app');
      final byPath = workspace.resolvePackage('apps/mobile_app');

      expect(byName.directory.path, byPath.directory.path);
      expect(workspace.relativePath(byName), p.join('apps', 'mobile_app'));
    });

    test('rejects Dart-only packages for project generation', () async {
      final workspace = await discoverPubWorkspace(start: fixture);

      expect(
        () => workspace.resolvePackage('analytics_plugin'),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('is not a Flutter package'),
          ),
        ),
      );
    });

    test('does not treat a standalone Dart package as a workspace', () async {
      final package = Directory(p.join(fixture.path, 'standalone'))
        ..createSync(recursive: true);
      _writePubspec(
        package,
        '''
name: standalone
environment:
  sdk: ^3.11.0
''',
      );

      expect(
        () => discoverPubWorkspace(start: package),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('No Dart pub workspace was found'),
          ),
        ),
      );
    });
  });

  group('normalizePackageOption', () {
    test('moves a trailing package option before the command', () {
      expect(
        normalizePackageOption([
          'add',
          'feature',
          'orders',
          '--package',
          'mobile_app',
          '--no-build-runner',
        ]),
        [
          '--package',
          'mobile_app',
          'add',
          'feature',
          'orders',
          '--no-build-runner',
        ],
      );
    });

    test('supports the equals form and rejects duplicates', () {
      expect(
        normalizePackageOption(['doctor', '--package=mobile_app']),
        ['--package=mobile_app', 'doctor'],
      );
      expect(
        () => normalizePackageOption([
          '--package=mobile_app',
          'doctor',
          '--package',
          'other_app',
        ]),
        throwsFormatException,
      );
    });
  });

  test('runner restores the original directory after a targeted command',
      () async {
    final fixture = _createWorkspaceFixture();
    final original = Directory.current;
    Directory.current = fixture;
    try {
      final exitCode = await ForgeCommandRunner(
        logger: Logger(level: Level.quiet),
      ).run(['doctor', '--fix', '--package', 'mobile_app']);

      expect(exitCode, 0);
      expect(
        _resolvedPath(Directory.current),
        _resolvedPath(fixture),
      );
    } finally {
      Directory.current = original;
      fixture.deleteSync(recursive: true);
    }
  });

  test('runner generates only inside the selected workspace package', () async {
    final fixture = _createWorkspaceFixture();
    final original = Directory.current;
    Directory(
      p.join(
        fixture.path,
        'apps',
        'mobile_app',
        'lib',
        'features',
        'orders',
      ),
    ).createSync(recursive: true);
    Directory.current = fixture;
    try {
      final exitCode = await ForgeCommandRunner(
        logger: Logger(level: Level.quiet),
      ).run([
        'add',
        'usecase',
        'orders',
        'fetch_orders',
        '--package',
        'mobile_app',
      ]);

      final relativeFile = p.join(
        'lib',
        'features',
        'orders',
        'domain',
        'usecase',
        'fetch_orders_usecase.dart',
      );
      final targetFile = File(
        p.join(fixture.path, 'apps', 'mobile_app', relativeFile),
      );
      final rootFile = File(p.join(fixture.path, relativeFile));

      expect(exitCode, 0);
      expect(targetFile.existsSync(), isTrue);
      expect(rootFile.existsSync(), isFalse);
      expect(
        targetFile.readAsStringSync(),
        contains(
          "import 'package:mobile_app/core/domain/api/api_result.dart';",
        ),
      );
      expect(_resolvedPath(Directory.current), _resolvedPath(fixture));
    } finally {
      Directory.current = original;
      fixture.deleteSync(recursive: true);
    }
  });
}

Directory _createWorkspaceFixture() {
  final root = Directory.systemTemp.createTempSync('forgekit_workspace_test_');
  _writePubspec(
    root,
    '''
name: workspace_root
publish_to: none
environment:
  sdk: ^3.11.0
workspace:
  - apps/*
  - packages/platform
''',
  );

  final app = Directory(p.join(root.path, 'apps', 'mobile_app'))
    ..createSync(recursive: true);
  Directory(p.join(app.path, 'lib')).createSync();
  _writePubspec(
    app,
    '''
name: mobile_app
publish_to: none
environment:
  sdk: ^3.11.0
resolution: workspace
dependencies:
  flutter:
    sdk: flutter
flutter:
  uses-material-design: true
''',
  );

  final nested = Directory(p.join(root.path, 'packages', 'platform'))
    ..createSync(recursive: true);
  _writePubspec(
    nested,
    '''
name: platform_packages
publish_to: none
environment:
  sdk: ^3.11.0
resolution: workspace
workspace:
  - plugins/*
''',
  );

  final plugin = Directory(p.join(nested.path, 'plugins', 'analytics'))
    ..createSync(recursive: true);
  _writePubspec(
    plugin,
    '''
name: analytics_plugin
publish_to: none
environment:
  sdk: ^3.11.0
resolution: workspace
''',
  );
  return root;
}

void _writePubspec(Directory directory, String contents) {
  directory.createSync(recursive: true);
  File(p.join(directory.path, 'pubspec.yaml'))
      .writeAsStringSync(contents.trimLeft());
}

String _resolvedPath(Directory directory) =>
    directory.resolveSymbolicLinksSync();
