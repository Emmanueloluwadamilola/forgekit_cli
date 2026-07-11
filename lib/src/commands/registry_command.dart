import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../registry_service.dart';

class RegistryCommand extends Command<int> {
  RegistryCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_RegistryConnectCommand(logger: _logger));
    addSubcommand(_RegistryPullCommand(logger: _logger));
    addSubcommand(_RegistryPushCommand(logger: _logger));
    addSubcommand(_RegistryStatusCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'registry';

  @override
  String get description => 'Manage a shared Git-backed ForgeKit registry.';
}

class _RegistryConnectCommand extends Command<int> {
  _RegistryConnectCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'path',
      help: 'Local clone path. Defaults to ~/.forgekit/registry.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'connect';

  @override
  String get description => 'Connect ForgeKit to a shared registry Git repo.';

  @override
  String get invocation => 'forgekit registry connect <git-url> [--path <dir>]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <git-url>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    return connectRegistry(
      url: rest.first,
      path: argResults!['path'] as String?,
      logger: _logger,
    );
  }
}

class _RegistryPullCommand extends Command<int> {
  _RegistryPullCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'pull';

  @override
  String get description => 'Pull the connected shared registry.';

  @override
  Future<int> run() => pullRegistry(logger: _logger);
}

class _RegistryPushCommand extends Command<int> {
  _RegistryPushCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'message',
      abbr: 'm',
      defaultsTo: 'Sync ForgeKit registry',
      help: 'Commit message for registry changes.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'push';

  @override
  String get description => 'Commit and push shared registry changes.';

  @override
  Future<int> run() {
    return pushRegistry(
      logger: _logger,
      message: argResults!['message'] as String,
    );
  }
}

class _RegistryStatusCommand extends Command<int> {
  _RegistryStatusCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'status';

  @override
  String get description => 'Show the connected shared registry status.';

  @override
  Future<int> run() => registryStatus(logger: _logger);
}
