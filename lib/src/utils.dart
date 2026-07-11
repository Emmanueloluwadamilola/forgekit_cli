import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Shared helpers used across the `forgekit` commands.

/// Walks up from [start] (default: current directory) looking for the nearest
/// directory that contains a `pubspec.yaml`, i.e. the project root.
///
/// Returns `null` if none is found before reaching the filesystem root. This
/// lets `add`-style commands work whether they are run from the project root or
/// from somewhere inside `lib/features/<feature>/…`.
Directory? findProjectRoot([Directory? start]) {
  var dir = (start ?? Directory.current).absolute;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // hit the filesystem root
    dir = parent;
  }
}

/// Infers the feature name from the current location when the user has `cd`-ed
/// into `<root>/lib/features/<feature>/…`.
///
/// Returns `null` when [start] is not inside a specific feature folder (e.g. it
/// is the project root, or `lib/features` itself).
String? inferFeatureName({required Directory root, Directory? start}) {
  final current = (start ?? Directory.current).absolute.path;
  final featuresRoot = p.join(root.absolute.path, 'lib', 'features');
  if (!p.isWithin(featuresRoot, current)) return null;
  final rel = p.relative(current, from: featuresRoot);
  final first = p.split(rel).first;
  return first.isEmpty || first == '..' ? null : first;
}

/// Runs the `mason` executable with [args].
///
/// stdout and stderr from the child process are forwarded to this process so
/// the user sees Mason's own output. Returns the child process exit code.
///
/// If the `mason` executable cannot be found / started (e.g. it is not
/// installed), prints an actionable hint and returns `1`.
Future<int> runMason(List<String> args, {Logger? logger}) async {
  final log = logger ?? Logger();
  try {
    final result = await Process.start(
      'mason',
      args,
      // Inherit the parent's stdio so Mason prompts/output stream live.
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    return result.exitCode;
  } on ProcessException {
    log.err(
      'Mason not found. Install with: '
      'dart pub global activate mason_cli',
    );
    return 1;
  }
}

/// Detects the Flutter/Dart project name by reading the `name:` field from the
/// `pubspec.yaml` in [root] (default: current directory).
///
/// Returns [fallback] (default `"app"`) when no pubspec exists or the field
/// cannot be parsed. This is intentionally a tiny hand-rolled parser so the CLI
/// does not depend on a full YAML package just for one field.
String detectProjectName({String fallback = 'app', Directory? root}) {
  final pubspec =
      File(p.join((root ?? Directory.current).path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return fallback;

  for (final rawLine in pubspec.readAsLinesSync()) {
    final line = rawLine.trim();
    // Skip comments and nested keys; the package name is a top-level `name:`.
    if (line.startsWith('#')) continue;
    if (!rawLine.startsWith('name:')) continue;

    var value = line.substring('name:'.length).trim();
    // Strip an inline comment, if any.
    final hashIndex = value.indexOf('#');
    if (hashIndex != -1) value = value.substring(0, hashIndex).trim();
    // Strip surrounding quotes.
    value = value.replaceAll('"', '').replaceAll("'", '').trim();
    if (value.isNotEmpty) return value;
  }
  return fallback;
}
