import 'dart:io';

import 'package:forgekit/src/native_setup_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late File source;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_native_setup_');
    Directory(p.join(root.path, 'android')).createSync();
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
dev_dependencies: {}
flutter:
  uses-material-design: true
''');
    source = File(p.join(root.path, 'source.png'))..writeAsBytesSync([1, 2, 3]);
    logger = Logger(level: Level.quiet);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('icon setup propagates flutter pub get failure', () async {
    final calls = <String>[];
    final exitCode = await setIcon(
      sourcePath: source.path,
      logger: logger,
      root: root,
      executor: (executable, arguments, workingDirectory) async {
        calls.add('$executable ${arguments.join(' ')}');
        expect(workingDirectory.path, root.path);
        return 7;
      },
    );

    expect(exitCode, 7);
    expect(calls, ['flutter pub get']);
  });

  test('splash setup propagates native generator failure', () async {
    final calls = <String>[];
    final exitCode = await setSplash(
      sourcePath: source.path,
      logger: logger,
      root: root,
      executor: (executable, arguments, _) async {
        calls.add('$executable ${arguments.join(' ')}');
        return calls.length == 1 ? 0 : 9;
      },
    );

    expect(exitCode, 9);
    expect(calls, [
      'flutter pub get',
      'dart run flutter_native_splash:create',
    ]);
  });

  test('icon setup fails before writing when no native platform exists',
      () async {
    Directory(p.join(root.path, 'android')).deleteSync();

    final exitCode = await setIcon(
      sourcePath: source.path,
      logger: logger,
      root: root,
      executor: (_, __, ___) async => fail('must not run a process'),
    );

    expect(exitCode, 1);
    expect(Directory(p.join(root.path, 'assets')).existsSync(), isFalse);
    expect(
      File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
      isNot(contains('flutter_launcher_icons')),
    );
  });
}
