import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'commands/add_command.dart';
import 'commands/create_command.dart';
import 'commands/doctor_command.dart';
import 'commands/set_command.dart';
import 'commands/setup_command.dart';
import 'commands/sync_command.dart';
import 'commands/update_command.dart';

/// The current CLI version. Keep in sync with `pubspec.yaml`.
const packageVersion = '0.1.0';

const _executableName = 'forgekit';
const _description =
    'Scaffold Flutter code that follows the ForgeKit Architecture Standard.';

/// The top-level [CommandRunner] for the `forgekit` CLI.
///
/// Registers every sub-command and wires up global flags such as `--version`.
class ForgeCommandRunner extends CommandRunner<int> {
  ForgeCommandRunner({Logger? logger})
      : _logger = logger ?? Logger(),
        super(_executableName, _description) {
    // Global flags.
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the current ForgeKit version.',
    );

    // Register commands.
    addCommand(CreateCommand(logger: _logger));
    addCommand(AddCommand(logger: _logger));
    addCommand(SetCommand(logger: _logger));
    addCommand(SetupCommand(logger: _logger));
    addCommand(SyncCommand(logger: _logger));
    addCommand(DoctorCommand(logger: _logger));
    addCommand(UpdateCommand(version: packageVersion, logger: _logger));
  }

  final Logger _logger;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);
      if (topLevelResults['version'] == true) {
        _logger.info('forgekit $packageVersion');
        return 0;
      }
      return await runCommand(topLevelResults) ?? 0;
    } on FormatException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(usage);
      return 1;
    } on UsageException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return 1;
    }
  }
}
