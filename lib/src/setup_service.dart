import 'dart:io';
import 'dart:isolate';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

const _bricks = <String, String>{
  'forge_app': 'bricks/forge_app',
  'forge_feature': 'bricks/forge_feature',
  'forge_widget': 'bricks/forge_widget',
  'forge_service': 'bricks/forge_service',
};

/// Installs ForgeKit's local tool dependencies and registers bundled bricks.
Future<int> runSetup({Logger? logger}) async {
  final log = logger ?? Logger();

  final packageRoot = await _resolvePackageRoot();
  if (packageRoot == null) {
    log.err('Could not locate the installed ForgeKit package.');
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
      'Reinstall ForgeKit from the GitHub repository and run setup again.',
    );
    return 1;
  }

  final masonReady = await _ensureMason(log);
  if (!masonReady) return 1;

  for (final entry in _bricks.entries) {
    final brickPath = p.join(packageRoot.path, entry.value);
    final progress = log.progress('Registering ${entry.key}');

    // Remove stale registrations first so setup can be re-run non-interactively.
    await Process.run(
      'mason',
      ['remove', '-g', entry.key],
      runInShell: true,
    );

    final result = await Process.run(
      'mason',
      ['add', '-g', entry.key, '--path', brickPath],
      runInShell: true,
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
    ..success('ForgeKit is ready.')
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

Future<bool> _ensureMason(Logger log) async {
  final existing = await Process.run(
    'mason',
    ['--version'],
    runInShell: true,
  );

  if (existing.exitCode == 0) return true;

  final progress = log.progress('Installing Mason CLI');
  final install = await Process.run(
    'dart',
    ['pub', 'global', 'activate', 'mason_cli'],
    runInShell: true,
  );

  if (install.exitCode != 0) {
    progress.fail('Failed to install Mason CLI.');
    _printProcessOutput(log, install);
    return false;
  }

  progress.complete('Installed Mason CLI');

  final check = await Process.run(
    'mason',
    ['--version'],
    runInShell: true,
  );

  if (check.exitCode == 0) return true;

  log.err('Mason was installed, but the "mason" command is not on your PATH.');
  log.info('Add ~/.pub-cache/bin to your PATH, then run: forgekit setup');
  return false;
}

void _printProcessOutput(Logger log, ProcessResult result) {
  final stdoutText = result.stdout.toString().trim();
  final stderrText = result.stderr.toString().trim();

  if (stdoutText.isNotEmpty) log.info(stdoutText);
  if (stderrText.isNotEmpty) log.err(stderrText);
}
