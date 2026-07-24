import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../config_service.dart';
import '../utils.dart';

class InitCommand extends Command<int> {
  InitCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'profile',
        allowed: supportedProfiles,
        help: 'Override the detected architecture profile.',
      )
      ..addOption(
        'state-management',
        allowed: supportedStateManagement,
        help: 'Override the detected state-management stack.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Replace an existing forgekit.yaml.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Detect an existing Flutter project and create forgekit.yaml.';

  @override
  Future<int> run() async {
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    final configFile = root.uri.resolve(forgeKitConfigFileName).toFilePath();
    if (File(configFile).existsSync() && !(argResults!['force'] as bool)) {
      _logger.err('forgekit.yaml already exists at $configFile.');
      _logger.info('Use --force to replace it after reviewing your settings.');
      return 1;
    }

    try {
      final config = detectForgeKitConfig(
        root: root,
        architecture: argResults!['profile'] as String?,
        stateManagement: argResults!['state-management'] as String?,
      );
      await saveForgeKitConfig(root: root, config: config);
      _logger
        ..success('Created $configFile.')
        ..info('  architecture: ${config.architecture}')
        ..info('  state management: ${config.stateManagement}')
        ..info('  router: ${config.router}')
        ..info('  dependency injection: ${config.dependencyInjection}')
        ..info('  models: ${config.models}')
        ..info('  API client: ${config.apiClient}');
      if (!creatableArchitectureProfiles.contains(config.architecture)) {
        _logger.warn(
          'The "${config.architecture}" profile records an adopted project but '
          'does not enable architecture generators in ForgeKit 0.1.0. Run '
          '"forgekit doctor" to review the boundary before generating code.',
        );
      }
      return 0;
    } on ConfigException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}
