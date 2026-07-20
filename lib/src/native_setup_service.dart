import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

typedef NativeProcessExecutor = Future<int> Function(
  String executable,
  List<String> arguments,
  Directory workingDirectory,
);

/// Sets the app launcher icon using `flutter_launcher_icons`.
///
/// Copies [sourcePath] to `assets/icon/`, adds the package + config to
/// `pubspec.yaml`, then runs the generator and propagates its exit code.
Future<int> setIcon({
  required String sourcePath,
  required Logger logger,
  required Directory root,
  NativeProcessExecutor? executor,
}) async {
  final dest = _copyInto(sourcePath, root, 'icon', logger);
  if (dest == null) return 1;

  final editor = _openPubspec(root, logger);
  if (editor == null) return 1;

  _ensureDevDependency(editor, 'flutter_launcher_icons', '^0.14.1');
  editor.update(
    ['flutter_launcher_icons'],
    {
      'android': true,
      'ios': true,
      'image_path': dest,
      'remove_alpha_ios': true,
    },
  );
  _savePubspec(root, editor);
  logger.info('Configured flutter_launcher_icons (image: $dest).');

  return _pubGetThen(
    root: root,
    logger: logger,
    generator: ['run', 'flutter_launcher_icons'],
    manualHint: 'dart run flutter_launcher_icons',
    executor: executor,
  );
}

/// Sets the splash screen using `flutter_native_splash`.
Future<int> setSplash({
  required String sourcePath,
  required Logger logger,
  required Directory root,
  String color = '#ffffff',
  NativeProcessExecutor? executor,
}) async {
  final dest = _copyInto(sourcePath, root, 'splash', logger);
  if (dest == null) return 1;

  final editor = _openPubspec(root, logger);
  if (editor == null) return 1;

  _ensureDevDependency(editor, 'flutter_native_splash', '^2.4.1');
  editor.update(
    ['flutter_native_splash'],
    {
      'color': color,
      'image': dest,
      'android_12': {'image': dest, 'color': color},
    },
  );
  _savePubspec(root, editor);
  logger
      .info('Configured flutter_native_splash (image: $dest, color: $color).');

  return _pubGetThen(
    root: root,
    logger: logger,
    generator: ['run', 'flutter_native_splash:create'],
    manualHint: 'dart run flutter_native_splash:create',
    executor: executor,
  );
}

/// Copies [sourcePath] into `assets/<subdir>/` and returns the POSIX asset path.
String? _copyInto(
  String sourcePath,
  Directory root,
  String subdir,
  Logger logger,
) {
  final src = File(sourcePath);
  if (!src.existsSync()) {
    logger.err('Source image not found: $sourcePath');
    return null;
  }
  final fileName = p.basename(sourcePath);
  final destAbs = p.join(root.path, 'assets', subdir, fileName);
  File(destAbs).parent.createSync(recursive: true);
  src.copySync(destAbs);
  return 'assets/$subdir/$fileName';
}

YamlEditor? _openPubspec(Directory root, Logger logger) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    logger.err('No pubspec.yaml at the project root.');
    return null;
  }
  return YamlEditor(pubspec.readAsStringSync());
}

void _savePubspec(Directory root, YamlEditor editor) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(editor.toString());
}

void _ensureDevDependency(YamlEditor editor, String name, String version) {
  YamlNode? node;
  try {
    node = editor.parseAt(['dev_dependencies']);
  } on ArgumentError {
    node = null;
  }
  if (node is! YamlMap) {
    editor.update([
      'dev_dependencies',
    ], {
      name: version,
    });
    return;
  }
  if (!node.containsKey(name)) {
    editor.update(['dev_dependencies', name], version);
  }
}

/// Runs `flutter pub get` then the [generator], preserving non-zero exit codes
/// so the surrounding ForgeKit transaction can restore partial changes.
Future<int> _pubGetThen({
  required Directory root,
  required Logger logger,
  required List<String> generator,
  required String manualHint,
  NativeProcessExecutor? executor,
}) async {
  final ok = await _execute(
    'flutter',
    ['pub', 'get'],
    root,
    logger,
    'flutter pub get',
    executor,
  );
  if (ok != 0) {
    logger.err(
      'Native configuration failed because "flutter pub get" did not '
      'complete. ForgeKit will restore the project transaction.',
    );
    return ok;
  }
  final gen = await _execute(
    'dart',
    generator,
    root,
    logger,
    manualHint,
    executor,
  );
  if (gen != 0) {
    logger.err(
      'Native generator failed. ForgeKit will restore the project '
      'transaction; fix the reported error and rerun the ForgeKit command.',
    );
    return gen;
  }
  return 0;
}

Future<int> _execute(
  String executable,
  List<String> arguments,
  Directory root,
  Logger logger,
  String label,
  NativeProcessExecutor? executor,
) {
  if (executor != null) return executor(executable, arguments, root);
  return _run(executable, arguments, root, logger, label);
}

Future<int> _run(
  String exe,
  List<String> args,
  Directory root,
  Logger logger,
  String label,
) async {
  final progress = logger.progress('Running $label');
  try {
    final proc = await Process.start(
      exe,
      args,
      workingDirectory: root.path,
      runInShell: Platform.isWindows && exe == 'flutter',
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await proc.exitCode;
    if (code != 0) {
      progress.fail('$label exited with code $code.');
      return code;
    }
    progress.complete('$label finished.');
    return 0;
  } on ProcessException {
    progress.fail('Could not start "$exe".');
    return 1;
  }
}
