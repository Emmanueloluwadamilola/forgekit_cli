import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../env_service.dart';
import '../native_setup_service.dart';
import '../utils.dart';

/// `forgekit set ...`
///
/// Parent command for project-wide native configuration (app icon, splash).
class SetCommand extends Command<int> {
  SetCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_SetIconCommand(logger: _logger));
    addSubcommand(_SetSplashCommand(logger: _logger));
    addSubcommand(_SetEnvCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'set';

  @override
  String get description =>
      'Configure the app icon, splash screen, or environment values.';
}

/// `forgekit set icon <image>`
class _SetIconCommand extends Command<int> {
  _SetIconCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'icon';

  @override
  String get description =>
      'Set the app launcher icon (via flutter_launcher_icons).';

  @override
  String get invocation => 'forgekit set icon <image>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <image>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    return setIcon(sourcePath: rest.first, logger: _logger, root: root);
  }
}

/// `forgekit set splash <image> [--color <hex>]`
class _SetSplashCommand extends Command<int> {
  _SetSplashCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'color',
      help: 'Background color (hex).',
      defaultsTo: '#ffffff',
    );
  }

  final Logger _logger;

  @override
  String get name => 'splash';

  @override
  String get description =>
      'Set the splash screen (via flutter_native_splash).';

  @override
  String get invocation => 'forgekit set splash <image> [--color <hex>]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <image>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    return setSplash(
      sourcePath: rest.first,
      logger: _logger,
      root: root,
      color: args['color'] as String,
    );
  }
}

/// `forgekit set env <KEY> <VALUE> --environment <name>`
class _SetEnvCommand extends Command<int> {
  _SetEnvCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'environment',
        abbr: 'e',
        help: 'Environment name to update, e.g. dev.',
      )
      ..addFlag(
        'all',
        negatable: false,
        help: 'Apply the value to every environment JSON file.',
      )
      ..addFlag(
        'allow-public-value',
        negatable: false,
        help: 'Allow a secret-like key only after confirming that its value '
            'is designed to be public client configuration.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'env';

  @override
  String get description => 'Set an environment config value.';

  @override
  String get invocation => 'forgekit set env <KEY> <VALUE> '
      '(--environment <name>|--all) '
      '[--allow-public-value]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      _logger.err('Expected <KEY> <VALUE>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    return setEnvironmentValue(
      key: rest.first,
      value: rest.skip(1).join(' '),
      logger: _logger,
      root: root,
      environment: argResults!['environment'] as String?,
      all: argResults!['all'] as bool,
      allowPublicValue: argResults!['allow-public-value'] as bool,
    );
  }
}
