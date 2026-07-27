import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import 'mason_environment.dart';
import 'utils.dart';

const _bricks = forgekitBricks;

/// Installs Flutter ForgeKit CLI's local dependencies and bundled bricks.
Future<int> runSetup({Logger? logger}) async {
  final log = logger ?? Logger();

  final packageRoot = await _resolvePackageRoot();
  if (packageRoot == null) {
    log.err('Could not locate the installed Flutter ForgeKit CLI package.');
    log.info(
      'Try reinstalling with: dart pub global activate --source git '
      'https://github.com/Emmanueloluwadamilola/forgekit_cli.git',
    );
    return 1;
  }

  final missingBricks = _bricks.entries
      .where(
        (entry) =>
            !Directory(p.join(packageRoot.path, entry.value)).existsSync(),
      )
      .map((entry) => entry.key)
      .toList();

  if (missingBricks.isNotEmpty) {
    log.err(
      'The installed package is missing bundled bricks: ${missingBricks.join(', ')}.',
    );
    log.info(
      'Reinstall Flutter ForgeKit CLI from GitHub and run setup again.',
    );
    return 1;
  }

  final masonReady = await _ensureMason(log);
  if (!masonReady) return 1;

  final installedBricks = await _installBundledBricks(packageRoot);
  await _removeForgekitMasonEntries();

  for (final entry in _bricks.entries) {
    final brickPath = installedBricks[entry.key]!;
    final progress = log.progress('Registering ${entry.key}');

    final result = await Process.run(
      'dart',
      [
        'pub',
        'global',
        'run',
        'mason_cli:mason',
        'add',
        '-g',
        entry.key,
        '--path',
        brickPath,
      ],
    );

    if (result.exitCode != 0) {
      progress.fail('Failed to register ${entry.key}.');
      _printProcessOutput(log, result);
      return result.exitCode;
    }

    progress.complete('Registered ${entry.key}');
  }

  log
    ..info('')
    ..success('Flutter ForgeKit CLI is ready.')
    ..info('Try: forgekit create app my_app');
  return 0;
}

Future<Directory?> _resolvePackageRoot() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:forgekit/forgekit.dart'),
  );
  if (packageUri == null || !packageUri.isScheme('file')) return null;

  final libFile = File.fromUri(packageUri);
  final root = libFile.parent.parent;
  return root.existsSync() ? root : null;
}

Future<Map<String, String>> _installBundledBricks(Directory packageRoot) async {
  final installRoot = forgekitHome();
  final installedBricksRoot = Directory(p.join(installRoot.path, 'bricks'));
  final installedBricks = <String, String>{};

  for (final entry in _bricks.entries) {
    final source = Directory(p.join(packageRoot.path, entry.value));
    final destination = Directory(p.join(installedBricksRoot.path, entry.key));

    await _replaceDirectory(source, destination);
    installedBricks[entry.key] = destination.path;
  }

  return installedBricks;
}

Future<void> _removeForgekitMasonEntries() async {
  final globalDir = masonGlobalDir();

  await _removeForgekitEntriesFromYaml(
    File(p.join(globalDir.path, 'mason.yaml')),
  );
  await _removeForgekitEntriesFromJson(
    File(p.join(globalDir.path, 'mason-lock.json')),
    nestedUnderBricks: true,
  );
  await _removeForgekitEntriesFromJson(
    File(p.join(globalDir.path, '.mason', 'bricks.json')),
  );
}

Future<void> _removeForgekitEntriesFromYaml(File file) async {
  if (!file.existsSync()) return;

  final contents = await file.readAsString();
  if (contents.trim().isEmpty) return;

  final editor = YamlEditor(contents);
  var changed = false;

  for (final brickName in _bricks.keys) {
    try {
      editor.remove(['bricks', brickName]);
      changed = true;
    } catch (_) {
      // Missing entries are fine; setup should be safe to run repeatedly.
    }
  }

  if (changed) {
    await file.writeAsString(editor.toString());
  }
}

Future<void> _removeForgekitEntriesFromJson(
  File file, {
  bool nestedUnderBricks = false,
}) async {
  if (!file.existsSync()) return;

  final contents = await file.readAsString();
  if (contents.trim().isEmpty) return;

  final decoded = json.decode(contents);
  if (decoded is! Map<String, dynamic>) return;

  final target = nestedUnderBricks ? decoded['bricks'] : decoded;
  if (target is! Map<String, dynamic>) return;

  var changed = false;
  for (final brickName in _bricks.keys) {
    changed = target.remove(brickName) != null || changed;
  }

  if (changed) {
    await file.writeAsString(json.encode(decoded));
  }
}

Future<void> _replaceDirectory(Directory source, Directory destination) async {
  if (destination.existsSync()) {
    await destination.delete(recursive: true);
  }
  await destination.create(recursive: true);

  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relativePath = p.relative(entity.path, from: source.path);
    final targetPath = p.join(destination.path, relativePath);

    if (entity is Directory) {
      await Directory(targetPath).create(recursive: true);
    } else if (entity is File) {
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await entity.copy(targetPath);
    } else if (entity is Link) {
      await Directory(p.dirname(targetPath)).create(recursive: true);
      await Link(targetPath).create(await entity.target());
    }
  }
}

Future<bool> _ensureMason(Logger log) async {
  final existing = await Process.run(
    'dart',
    ['pub', 'global', 'run', 'mason_cli:mason', '--version'],
  );

  if (existing.exitCode == 0 &&
      existing.stdout.toString().contains(
            'mason_cli $supportedMasonCliVersion',
          )) {
    return true;
  }

  final progress = log.progress(
    'Installing Mason CLI $supportedMasonCliVersion',
  );
  final install = await Process.run(
    'dart',
    [
      'pub',
      'global',
      'activate',
      'mason_cli',
      supportedMasonCliVersion,
    ],
  );

  if (install.exitCode != 0) {
    progress.fail('Failed to install Mason CLI.');
    _printProcessOutput(log, install);
    return false;
  }

  progress.complete('Installed Mason CLI $supportedMasonCliVersion');

  final check = await Process.run(
    'dart',
    ['pub', 'global', 'run', 'mason_cli:mason', '--version'],
  );

  if (check.exitCode == 0 &&
      check.stdout.toString().contains(
            'mason_cli $supportedMasonCliVersion',
          )) {
    return true;
  }

  log.err(
    'Mason CLI $supportedMasonCliVersion was activated, but that exact '
    'version could not be executed through Dart Pub.',
  );
  log.info('Verify the Dart SDK installation, then run: forgekit setup');
  return false;
}

void _printProcessOutput(Logger log, ProcessResult result) {
  final stdoutText = result.stdout.toString().trim();
  final stderrText = result.stderr.toString().trim();

  if (stdoutText.isNotEmpty) log.info(stdoutText);
  if (stderrText.isNotEmpty) log.err(stderrText);
}
