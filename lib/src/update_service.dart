import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

const forgekitGitUrl =
    'https://github.com/Emmanueloluwadamilola/forgekit_cli.git';

/// Updates ForgeKit from the GitHub repository and refreshes local setup.
Future<int> runUpdate({Logger? logger}) async {
  final log = logger ?? Logger();

  final updateExit = await _runInherited(
    'dart',
    ['pub', 'global', 'activate', '--source', 'git', forgekitGitUrl],
    logger: log,
    failureMessage: 'Failed to update ForgeKit from GitHub.',
  );
  if (updateExit != 0) return updateExit;

  final setupExit = await _runInherited(
    'dart',
    ['pub', 'global', 'run', 'forgekit:forgekit', 'setup'],
    logger: log,
    failureMessage: 'ForgeKit updated, but setup failed.',
  );
  if (setupExit != 0) {
    log.info('Try running setup manually: forgekit setup');
    return setupExit;
  }

  log.success('ForgeKit updated from GitHub.');
  return 0;
}

Future<int> _runInherited(
  String executable,
  List<String> args, {
  required Logger logger,
  required String failureMessage,
}) async {
  try {
    final process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) logger.err(failureMessage);
    return exitCode;
  } on ProcessException catch (e) {
    logger
      ..err(failureMessage)
      ..err(e.message);
    return 1;
  }
}
