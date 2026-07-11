import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../update_service.dart';

/// `forgekit update`
///
/// Checks pub.dev for a newer forgekit and self-updates with consent.
class UpdateCommand extends Command<int> {
  UpdateCommand({required this.version, Logger? logger})
      : _logger = logger ?? Logger();

  final Logger _logger;
  final String version;

  @override
  String get name => 'update';

  @override
  String get description =>
      'Update ForgeKit to the latest version from pub.dev.';

  @override
  Future<int> run() => runUpdate(logger: _logger, currentVersion: version);
}
