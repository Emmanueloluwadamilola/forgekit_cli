import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

void wireGetItInitializedService({
  required Directory root,
  required String projectName,
  required String serviceSnake,
  required String className,
}) {
  final mainFile = File(p.join(root.path, 'lib', 'main.dart'));
  if (!mainFile.existsSync()) {
    throw const FileSystemException('Could not find lib/main.dart.');
  }

  var source = mainFile.readAsStringSync();
  source = addDartImport(
    source,
    'package:$projectName/services/${serviceSnake}_service.dart',
  );
  source = insertServiceInitialization(
    source,
    initialization: 'await getIt<$className>().init();',
    anchor: 'await configureDependencies();',
  );
  mainFile.writeAsStringSync(source);
}

void wireModularInitializedService({
  required Directory root,
  required String projectName,
  required String serviceSnake,
  required String className,
  required String instanceName,
}) {
  final moduleFile = File(p.join(root.path, 'lib', 'app', 'app_module.dart'));
  if (!moduleFile.existsSync()) {
    throw const FileSystemException(
      'Could not find lib/app/app_module.dart for Modular registration.',
    );
  }

  var moduleSource = moduleFile.readAsStringSync();
  moduleSource = addDartImport(
    moduleSource,
    'package:$projectName/services/${serviceSnake}_service.dart',
  );
  final registration = '..addInstance<$className>($instanceName)';
  if (!moduleSource.contains(registration)) {
    const marker = '// forgekit:services';
    if (moduleSource.contains(marker)) {
      moduleSource = moduleSource.replaceFirst(
        marker,
        '$registration\n      $marker',
      );
    } else {
      final routeIndex = moduleSource.indexOf('..route(');
      if (routeIndex == -1) {
        throw const FormatException(
          'Could not locate the Modular registration cascade.',
        );
      }
      moduleSource = moduleSource.replaceRange(
        routeIndex,
        routeIndex,
        '$registration\n      ',
      );
    }
  }
  moduleFile.writeAsStringSync(moduleSource);

  final mainFile = File(p.join(root.path, 'lib', 'main.dart'));
  if (!mainFile.existsSync()) {
    throw const FileSystemException('Could not find lib/main.dart.');
  }

  var mainSource = mainFile.readAsStringSync();
  mainSource = addDartImport(
    mainSource,
    'package:$projectName/services/${serviceSnake}_service.dart',
  );
  mainSource = mainSource.replaceFirst(
    RegExp(r'\bvoid\s+main\s*\(\s*\)\s*\{'),
    'Future<void> main() async {',
  );
  if (!mainSource.contains('Future<void> main() async {')) {
    throw const FormatException('Could not make Modular main asynchronous.');
  }
  if (!mainSource.contains('WidgetsFlutterBinding.ensureInitialized();')) {
    mainSource = mainSource.replaceFirst(
      'Future<void> main() async {',
      'Future<void> main() async {\n'
          '  WidgetsFlutterBinding.ensureInitialized();',
    );
  }
  mainSource = insertServiceInitialization(
    mainSource,
    initialization: 'await $instanceName.init();',
    anchor: 'WidgetsFlutterBinding.ensureInitialized();',
  );
  mainFile.writeAsStringSync(mainSource);
}

/// Inserts `Firebase.initializeApp` into `lib/main.dart` ahead of everything
/// else the bootstrap does.
///
/// Firebase differs from an ordinary ForgeKit service: it is a prerequisite of
/// the services that depend on it, not a peer. `FirebaseMessaging.instance` and
/// `FirebaseRemoteConfig.instance` both throw if the core app has not been
/// initialised, so this cannot use the shared
/// `// forgekit:service-initializers` marker — that marker sits *after*
/// `configureDependencies()`, and a `@lazySingleton` resolved during DI setup
/// would construct before Firebase existed.
///
/// Insertion order, most specific anchor first:
///   1. before `await configureDependencies();` (Clean and MVVM), or
///   2. after `WidgetsFlutterBinding.ensureInitialized();` (Modular, which has
///      no GetIt bootstrap).
///
/// Idempotent: a `main.dart` that already calls `Firebase.initializeApp` is
/// returned unchanged, so re-running `forgekit add firebase` to add a second
/// capability does not duplicate the call.
void wireFirebaseCoreInitialization({
  required Directory root,
  required String projectName,
}) {
  final mainFile = File(p.join(root.path, 'lib', 'main.dart'));
  if (!mainFile.existsSync()) {
    throw const FileSystemException('Could not find lib/main.dart.');
  }

  var source = mainFile.readAsStringSync();
  if (source.contains('Firebase.initializeApp(')) return;

  source = addDartImport(source, 'package:firebase_core/firebase_core.dart');
  source = addDartImport(source, 'package:$projectName/firebase_options.dart');

  source = source.replaceFirst(
    RegExp(r'\bvoid\s+main\s*\(\s*\)\s*\{'),
    'Future<void> main() async {',
  );
  if (!source.contains('Future<void> main() async {')) {
    throw const FormatException(
      'Could not make main() asynchronous for Firebase initialization.',
    );
  }
  if (!source.contains('WidgetsFlutterBinding.ensureInitialized();')) {
    source = source.replaceFirst(
      'Future<void> main() async {',
      'Future<void> main() async {\n'
          '  WidgetsFlutterBinding.ensureInitialized();',
    );
  }

  const initialization = '  await Firebase.initializeApp(\n'
      '    options: DefaultFirebaseOptions.currentPlatform,\n'
      '  );';

  const diAnchor = 'await configureDependencies();';
  if (source.contains(diAnchor)) {
    // Match the anchor with its leading indentation so the replacement keeps
    // the original line intact.
    final anchorPattern = RegExp(
      r'^([ \t]*)' + RegExp.escape(diAnchor),
      multiLine: true,
    );
    final match = anchorPattern.firstMatch(source);
    if (match == null) {
      // The anchor exists but not at the start of a line, e.g. a hand-edited
      // `if (kDebugMode) await configureDependencies();`. Fall back to a plain
      // substitution rather than throwing a TypeError.
      source = source.replaceFirst(diAnchor, '$initialization\n\n  $diAnchor');
    } else {
      source = source.replaceRange(
        match.start,
        match.end,
        '$initialization\n\n${match.group(1)}$diAnchor',
      );
    }
  } else {
    const bindingAnchor = 'WidgetsFlutterBinding.ensureInitialized();';
    source = source.replaceFirst(
      bindingAnchor,
      '$bindingAnchor\n\n$initialization',
    );
  }

  mainFile.writeAsStringSync(source);
}

String addDartImport(String source, String uri) {
  final import = "import '$uri';";
  if (source.contains(import)) return source;
  final imports = RegExp(r'''^import ['"].+['"];\s*$''', multiLine: true)
      .allMatches(source)
      .toList();
  if (imports.isEmpty) {
    throw const FormatException('Could not locate imports in the Dart file.');
  }
  final last = imports.last;
  return source.replaceRange(last.end, last.end, '\n$import');
}

String insertServiceInitialization(
  String source, {
  required String initialization,
  required String anchor,
}) {
  if (source.contains(initialization)) return source;
  const marker = '// forgekit:service-initializers';
  if (source.contains(marker)) {
    return source.replaceFirst(marker, '$initialization\n  $marker');
  }
  if (!source.contains(anchor)) {
    throw FormatException('Could not find bootstrap anchor `$anchor`.');
  }
  return source.replaceFirst(
    anchor,
    '$anchor\n\n  $initialization\n  $marker',
  );
}

Future<int> runInheritedProjectCommand(
  String executable,
  List<String> arguments, {
  required Directory root,
  required Logger logger,
  required String label,
}) async {
  final progress = logger.progress('Running $label');
  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows && executable == 'flutter',
    );
    final code = await process.exitCode;
    if (code == 0) {
      progress.complete('$label finished.');
    } else {
      progress.fail('$label exited with code $code.');
    }
    return code;
  } on ProcessException catch (error) {
    progress.fail('Could not start $label.');
    logger.err(error.message);
    return 1;
  }
}
