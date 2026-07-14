import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../setup_service.dart';

/// `forgekit setup`
///
/// Installs required local tooling and registers bundled bricks.
class SetupCommand extends Command<int> {
  SetupCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'setup';

  @override
  String get description =>
      'Install tooling and register Flutter ForgeKit CLI Mason bricks.';

  @override
  Future<int> run() => runSetup(logger: _logger);
}
