import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../generation_transaction_service.dart';
import '../utils.dart';

class RollbackCommand extends Command<int> {
  RollbackCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Roll back even when generated files changed afterward.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Roll back the latest Flutter ForgeKit CLI generation.';

  @override
  Future<int> run() async {
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    try {
      return rollbackLatestGeneration(
        root: root,
        logger: _logger,
        force: argResults!['force'] as bool,
      );
    } on GenerationTransactionException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}
