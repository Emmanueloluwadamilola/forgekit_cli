import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../config_service.dart';
import '../coverage_service.dart';
import '../utils.dart';

/// `forgekit test [--no-coverage] [-- <flutter-test arguments>]`
///
/// Runs the Flutter test suite and, by default, enforces the coverage threshold
/// declared in `forgekit.yaml`.
class TestCommand extends Command<int> {
  TestCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'coverage',
      defaultsTo: true,
      help: 'Collect line coverage and enforce testing.coverage.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'test';

  @override
  String get description =>
      'Run Flutter tests and enforce the configured coverage threshold.';

  @override
  String get invocation =>
      'forgekit test [--no-coverage] [-- <flutter-test arguments>]';

  @override
  Future<int> run() async {
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    final config = loadForgeKitConfig(root: root, allowMissing: false);
    return runProjectTests(
      root: root,
      logger: _logger,
      config: config,
      collectCoverage: argResults!['coverage'] as bool,
      flutterTestArguments: argResults!.rest,
    );
  }
}
