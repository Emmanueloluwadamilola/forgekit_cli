import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../native_setup_service.dart';
import '../utils.dart';

/// `forgekit set ...`
///
/// Parent command for project-wide native configuration (app icon, splash).
class SetCommand extends Command<int> {
  SetCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_SetIconCommand(logger: _logger));
    addSubcommand(_SetSplashCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'set';

  @override
  String get description => 'Configure the app icon or splash screen.';
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
