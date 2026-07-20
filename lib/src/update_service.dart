import 'dart:io';

import 'package:mason_logger/mason_logger.dart';

const forgekitGitUrl =
    'https://github.com/Emmanueloluwadamilola/forgekit_cli.git';

typedef UpdateProcessExecutor = Future<int> Function(
  String executable,
  List<String> arguments,
);

bool isImmutableGitRevision(String value) {
  return RegExp(r'^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$')
      .hasMatch(value.trim());
}

/// Updates Flutter ForgeKit CLI from an immutable Git revision and refreshes
/// local setup.
Future<int> runUpdate({
  required String revision,
  Logger? logger,
  UpdateProcessExecutor? executor,
}) async {
  final log = logger ?? Logger();
  final normalizedRevision = revision.trim();
  if (!isImmutableGitRevision(normalizedRevision)) {
    log.err(
      'Refusing an unpinned update. Provide a complete 40- or 64-character '
      'Git commit SHA.',
    );
    return 64;
  }
  final execute = executor ??
      (String executable, List<String> arguments) =>
          _runInherited(executable, arguments, logger: log);

  final updateExit = await execute(
    'dart',
    [
      'pub',
      'global',
      'activate',
      '--source',
      'git',
      forgekitGitUrl,
      '--git-ref',
      normalizedRevision,
    ],
  );
  if (updateExit != 0) {
    log.err('Failed to update Flutter ForgeKit CLI from GitHub.');
    return updateExit;
  }

  final setupExit = await execute(
    'dart',
    ['pub', 'global', 'run', 'forgekit:forgekit', 'setup'],
  );
  if (setupExit != 0) {
    log
      ..err('Flutter ForgeKit CLI updated, but setup failed.')
      ..info('Try running setup manually: forgekit setup');
    return setupExit;
  }

  log.success(
    'Flutter ForgeKit CLI updated to commit '
    '${normalizedRevision.substring(0, 12)}.',
  );
  return 0;
}

Future<int> _runInherited(
  String executable,
  List<String> args, {
  required Logger logger,
}) async {
  try {
    final process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  } on ProcessException catch (e) {
    logger.err('Could not start "$executable": ${e.message}');
    return 1;
  }
}
