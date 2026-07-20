import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../update_service.dart';

/// `forgekit update`
///
/// Updates the globally activated CLI from the GitHub repository.
class UpdateCommand extends Command<int> {
  UpdateCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'ref',
      valueHelp: 'full-commit-sha',
      help: 'Reviewed immutable Git commit to install (40 or 64 hex digits).',
    );
  }

  final Logger _logger;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Update Flutter ForgeKit CLI to a reviewed immutable Git commit.';

  @override
  String get invocation => 'forgekit update --ref <full-commit-sha>';

  @override
  Future<int> run() {
    final revision = argResults!['ref'] as String?;
    if (revision == null || revision.trim().isEmpty) {
      _logger
        ..err('A reviewed immutable revision is required.')
        ..info('Usage: $invocation');
      return Future.value(64);
    }
    if (!isImmutableGitRevision(revision)) {
      _logger.err(
        '--ref must be a complete 40- or 64-character hexadecimal Git '
        'commit, not a mutable branch or abbreviated revision.',
      );
      return Future.value(64);
    }
    return runUpdate(revision: revision, logger: _logger);
  }
}
