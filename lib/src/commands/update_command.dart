import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../update_service.dart';

/// `forgekit update`
///
/// Updates the globally activated CLI from the GitHub repository.
class UpdateCommand extends Command<int> {
  UpdateCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Update Flutter ForgeKit CLI from the GitHub repository.';

  @override
  Future<int> run() => runUpdate(logger: _logger);
}
