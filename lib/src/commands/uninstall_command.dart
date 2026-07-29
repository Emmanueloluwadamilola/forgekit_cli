import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../uninstall_service.dart';
import '../utils.dart';

/// `forgekit uninstall`
///
/// Removes everything `forgekit setup` created: the global Mason brick
/// registrations, ForgeKit's data directory, and the executable itself.
///
/// Not registered in the `--package` or `--dry-run` allow-lists in
/// `command_runner.dart`: it is a machine-level operation, so wrapping it in a
/// project generation transaction would be meaningless. `--dry-run` is a local
/// flag here instead.
class UninstallCommand extends Command<int> {
  UninstallCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Remove without an interactive confirmation.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print what would be removed and change nothing.',
      )
      ..addFlag(
        'keep-widgets',
        negatable: false,
        help: 'Preserve the synced widget library instead of deleting it.',
      )
      ..addFlag(
        'remove-mason',
        negatable: false,
        help: 'Also remove the Mason CLI and its cache. Only do this if '
            'ForgeKit installed Mason for you.',
      )
      ..addFlag(
        'clean-project',
        negatable: false,
        help: 'Also delete forgekit.yaml and .forgekit/ from the current '
            'project. Never searches beyond it.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'uninstall';

  @override
  String get description =>
      'Remove Flutter ForgeKit CLI and everything setup installed.';

  @override
  String get invocation => 'forgekit uninstall [--dry-run] [--force] '
      '[--keep-widgets] [--remove-mason] [--clean-project]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final dryRun = args['dry-run'] as bool;
    final cleanProject = args['clean-project'] as bool;

    final projectRoot = cleanProject ? findProjectRoot() : null;
    if (cleanProject && projectRoot == null) {
      _logger
        ..err('--clean-project needs a project: no pubspec.yaml found here.')
        ..info('Run it from inside the project, or drop the flag.');
      return 1;
    }

    final plan = planUninstall(
      keepWidgets: args['keep-widgets'] as bool,
      removeMason: args['remove-mason'] as bool,
      cleanProject: cleanProject,
      projectRoot: projectRoot,
    );

    _logger.info('This will remove:');
    for (final step in plan.steps) {
      _logger.info('  - ${step.label}');
      _logger.info('      ${step.detail}');
    }

    if (!plan.removeMason) {
      _logger
        ..info('')
        ..info('Mason CLI is kept. If ForgeKit installed it for you and '
            'nothing else needs it, add --remove-mason.');
    }
    if (!plan.cleanProject) {
      _logger.info(
        'forgekit.yaml and .forgekit/ inside your projects are kept. They are '
        'inert without the CLI.',
      );
    }

    if (dryRun) {
      _logger
        ..info('')
        ..info('Dry run: nothing was changed.');
      return 0;
    }

    if (!(args['force'] as bool)) {
      if (!hasInteractiveTerminal) {
        _logger.err(
          'Refusing to uninstall without --force in a non-interactive shell.',
        );
        return 1;
      }
      _logger.info('');
      final confirmed = _logger.confirm(
        'Remove ForgeKit from this machine?',
        defaultValue: false,
      );
      if (!confirmed) {
        _logger.info('Cancelled. Nothing was changed.');
        return 0;
      }
    }

    _logger.info('');
    return runUninstall(logger: _logger, plan: plan);
  }
}
