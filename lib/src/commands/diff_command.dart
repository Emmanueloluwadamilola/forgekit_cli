import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../generation_transaction_service.dart';
import '../utils.dart';

class DiffCommand extends Command<int> {
  DiffCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'diff';

  @override
  String get description =>
      'Show drift from the latest Flutter ForgeKit CLI generation.';

  @override
  Future<int> run() async {
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    try {
      return showGenerationDiff(root: root, logger: _logger);
    } on GenerationTransactionException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}
