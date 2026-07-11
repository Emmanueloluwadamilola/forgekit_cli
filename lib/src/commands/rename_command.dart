import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../feature_lifecycle_service.dart';
import '../utils.dart';

class RenameCommand extends Command<int> {
  RenameCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_RenameFeatureCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'rename';

  @override
  String get description => 'Rename generated ForgeKit resources.';
}

class _RenameFeatureCommand extends Command<int> {
  _RenameFeatureCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'feature';

  @override
  String get description =>
      'Rename a feature folder and generated identifiers.';

  @override
  String get invocation => 'forgekit rename feature <old> <new>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      _logger.err('Expected two arguments: <old> <new>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    return renameFeature(
      root: root,
      from: rest[0],
      to: rest[1],
      logger: _logger,
    );
  }
}
