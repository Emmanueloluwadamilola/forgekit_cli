import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../widget_registry_service.dart';

/// `forgekit sync ...`
///
/// Stores reusable local assets so they can be added to future projects.
class SyncCommand extends Command<int> {
  SyncCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_SyncWidgetCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'sync';

  @override
  String get description => 'Sync reusable ForgeKit resources for later use.';
}

/// `forgekit sync widget <name> [--path <file>]`
class _SyncWidgetCommand extends Command<int> {
  _SyncWidgetCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        help:
            'Path to the widget file to sync. Defaults to the shared widget path.',
      )
      ..addFlag(
        'push',
        negatable: false,
        help:
            'Also sync the widget to the connected shared registry and push it.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'widget';

  @override
  String get description =>
      'Sync a shared widget into the local widget library.';

  @override
  String get invocation =>
      'forgekit sync widget <name> [--path <file>] [--push]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    return syncWidget(
      name: rest.first,
      sourcePath: argResults!['path'] as String?,
      push: argResults!['push'] as bool,
      logger: _logger,
    );
  }
}
