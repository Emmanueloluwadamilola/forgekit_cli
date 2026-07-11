import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:pub_updater/pub_updater.dart';

/// Checks pub.dev for a newer `forgekit` and, with consent, self-updates via
/// `dart pub global activate`.
///
/// Returns `0` on success (including "already latest"), `1` on failure.
Future<int> runUpdate({
  required Logger logger,
  required String currentVersion,
  PubUpdater? updater,
}) async {
  final pub = updater ?? PubUpdater();
  final progress = logger.progress('Checking pub.dev for updates');

  String latest;
  try {
    latest = await pub.getLatestVersion('forgekit');
  } catch (_) {
    progress.fail(
      'Could not check for updates. '
      'forgekit may not be published to pub.dev yet.',
    );
    return 1;
  }

  if (latest == currentVersion) {
    progress.complete('forgekit is up to date ($currentVersion).');
    return 0;
  }

  progress.complete('Update available: $currentVersion → $latest');

  // `confirm` needs a TTY; in a non-interactive shell just print instructions.
  if (!stdout.hasTerminal || !stdin.hasTerminal) {
    logger.info('Run "forgekit update" in an interactive terminal, or:');
    logger.info('  dart pub global activate forgekit');
    return 0;
  }
  if (!logger.confirm('Update now?', defaultValue: true)) {
    logger.info('Skipped. Update later with: forgekit update');
    return 0;
  }

  final updating = logger.progress('Updating forgekit');
  try {
    await pub.update(packageName: 'forgekit');
  } catch (_) {
    updating.fail('Update failed. Try: dart pub global activate forgekit');
    return 1;
  }
  updating.complete('Updated to $latest. Restart your shell to use it.');
  return 0;
}
