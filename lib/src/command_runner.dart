import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'commands/add_command.dart';
import 'commands/config_command.dart';
import 'commands/create_command.dart';
import 'commands/diff_command.dart';
import 'commands/doctor_command.dart';
import 'commands/init_command.dart';
import 'commands/import_command.dart';
import 'commands/registry_command.dart';
import 'commands/remove_command.dart';
import 'commands/rename_command.dart';
import 'commands/rollback_command.dart';
import 'commands/set_command.dart';
import 'commands/setup_command.dart';
import 'commands/sync_command.dart';
import 'commands/test_command.dart';
import 'commands/uninstall_command.dart';
import 'commands/update_command.dart';
import 'commands/workspace_command.dart';
import 'config_service.dart';
import 'generation_transaction_service.dart';
import 'utils.dart';
import 'workspace_service.dart';

/// The current CLI version. Keep in sync with `pubspec.yaml`.
const packageVersion = '0.1.0';

const _executableName = 'forgekit';
const _description =
    'Flutter ForgeKit CLI scaffolds architecture-aware Flutter projects and code.';

/// Returns the non-sensitive command path stored in generation metadata.
///
/// Positional arguments and option values are deliberately excluded. They can
/// contain environment values, authenticated URLs, local paths, or pasted
/// application data that does not belong in `.forgekit/backups`.
String transactionCommandLabel(ArgResults results) {
  final parts = <String>['forgekit'];
  var command = results.command;
  while (command != null) {
    final name = command.name;
    if (name != null && name.isNotEmpty) parts.add(name);
    command = command.command;
  }
  return parts.join(' ');
}

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
      help: 'Print the current Flutter ForgeKit CLI version.',
    );
    argParser.addOption(
      'package',
      help: 'Target a Flutter package in the current Dart pub workspace.\n'
          'Accepts a package name or workspace-relative path.',
      valueHelp: 'name-or-path',
    );
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Preview and restore project changes instead of keeping them.',
    );

    // Register commands.
    addCommand(CreateCommand(logger: _logger));
    addCommand(ConfigCommand(logger: _logger));
    addCommand(DiffCommand(logger: _logger));
    addCommand(AddCommand(logger: _logger));
    addCommand(RegistryCommand(logger: _logger));
    addCommand(RenameCommand(logger: _logger));
    addCommand(RemoveCommand(logger: _logger));
    addCommand(SetCommand(logger: _logger));
    addCommand(SetupCommand(logger: _logger));
    addCommand(SyncCommand(logger: _logger));
    addCommand(TestCommand(logger: _logger));
    addCommand(DoctorCommand(logger: _logger));
    addCommand(ImportCommand(logger: _logger));
    addCommand(InitCommand(logger: _logger));
    addCommand(RollbackCommand(logger: _logger));
    addCommand(UninstallCommand(logger: _logger));
    addCommand(UpdateCommand(logger: _logger));
    addCommand(WorkspaceCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  Future<int> run(Iterable<String> args) async {
    final originalDirectory = Directory.current;
    try {
      final normalizedArgs =
          normalizeDryRunOption(normalizePackageOption(args));
      final topLevelResults = parse(normalizedArgs);
      if (topLevelResults['version'] == true) {
        _logger.info('Flutter ForgeKit CLI $packageVersion (forgekit)');
        return 0;
      }

      final packageSelector = topLevelResults['package'] as String?;
      if (packageSelector != null) {
        final commandName = topLevelResults.command?.name;
        const supportedCommands = {
          'add',
          'config',
          'diff',
          'doctor',
          'init',
          'import',
          'remove',
          'rename',
          'rollback',
          'set',
          'sync',
          'test',
        };
        if (!supportedCommands.contains(commandName)) {
          throw UsageException(
            '--package is only supported by project commands: '
            'add, config, diff, doctor, import, init, remove, rename, rollback, '
            'set, sync, and test.',
            usage,
          );
        }
        final workspace = await discoverPubWorkspace(start: originalDirectory);
        final package = workspace.resolvePackage(packageSelector);
        Directory.current = package.directory;
        _logger.info(
          'Using workspace package "${package.name}" '
          '(${workspace.relativePath(package)}).',
        );
      }

      final dryRun = topLevelResults['dry-run'] as bool;
      final commandName = topLevelResults.command?.name;
      const transactionalCommands = {
        'add',
        'config',
        'doctor',
        'init',
        'import',
        'remove',
        'rename',
        'set',
      };
      if (dryRun && !transactionalCommands.contains(commandName)) {
        throw UsageException(
          '--dry-run is supported by add, config, doctor, import, init, remove, '
          'rename, and set commands.',
          usage,
        );
      }

      GenerationTransaction? transaction;
      var formatGeneratedFiles = true;
      if (transactionalCommands.contains(commandName)) {
        final root = findProjectRoot();
        if (root != null) {
          try {
            formatGeneratedFiles = loadForgeKitConfig(root: root).format;
          } on ConfigException {
            // The command itself reports malformed configuration when it
            // consumes it. Keep transaction setup available for restoration.
          }
          transaction = await GenerationTransaction.begin(
            root: root,
            command: transactionCommandLabel(topLevelResults),
          );
        }
      }

      int exitCode;
      try {
        exitCode = await runCommand(topLevelResults) ?? 0;
      } catch (_) {
        await transaction?.finish(
          success: false,
          dryRun: false,
          logger: _logger,
        );
        rethrow;
      }
      await transaction?.finish(
        success: exitCode == 0,
        dryRun: dryRun,
        logger: _logger,
        format: formatGeneratedFiles,
      );
      return exitCode;
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
    } on WorkspaceException catch (e) {
      _logger.err(e.message);
      return 1;
    } on ConfigException catch (e) {
      _logger.err(e.message);
      return 1;
    } on GenerationTransactionException catch (e) {
      _logger.err(e.message);
      return 1;
    } on FileSystemException catch (e) {
      _logger.err(
        'Filesystem operation failed${e.path == null ? '' : ' for ${e.path}'}: '
        '${e.message}',
      );
      return 1;
    } on ProcessException catch (e) {
      _logger.err('Could not run ${e.executable}: ${e.message}');
      return 1;
    } catch (error, stackTrace) {
      _logger.err(
        'ForgeKit could not complete the command: $error\n'
        'No intentional partial project changes were kept. Set '
        'FORGEKIT_DEBUG=1 and retry to include diagnostic details.',
      );
      if (Platform.environment['FORGEKIT_DEBUG'] == '1') {
        _logger.detail(stackTrace.toString());
      }
      return 1;
    } finally {
      Directory.current = originalDirectory;
    }
  }
}
