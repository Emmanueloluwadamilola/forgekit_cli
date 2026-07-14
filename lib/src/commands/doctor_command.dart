import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../doctor_service.dart';
import '../utils.dart';

/// `forgekit doctor [--ci]`
///
/// Verifies the project conforms to the Flutter ForgeKit CLI standard.
class DoctorCommand extends Command<int> {
  DoctorCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'ci',
      negatable: false,
      help: 'Exit non-zero on any issue (warnings included).',
    );
    argParser.addFlag(
      'fix',
      negatable: false,
      help: 'Create missing standard folders/files when safe.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the project against the Flutter ForgeKit CLI Architecture Standard.';

  @override
  Future<int> run() async {
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    return runDoctor(
      logger: _logger,
      root: root,
      ci: argResults!['ci'] as bool,
      fix: argResults!['fix'] as bool,
    );
  }
}
