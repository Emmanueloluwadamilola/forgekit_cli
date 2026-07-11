import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../feature_lifecycle_service.dart';
import '../utils.dart';

class RemoveCommand extends Command<int> {
  RemoveCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_RemoveFeatureCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove generated ForgeKit resources.';
}

class _RemoveFeatureCommand extends Command<int> {
  _RemoveFeatureCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Remove without an interactive confirmation.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'feature';

  @override
  String get description => 'Remove a feature folder and generated tests.';

  @override
  String get invocation => 'forgekit remove feature <name> [--force]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    return removeFeature(
      root: root,
      feature: rest.first,
      logger: _logger,
      force: argResults!['force'] as bool,
    );
  }
}
