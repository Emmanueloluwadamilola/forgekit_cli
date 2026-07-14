import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../config_service.dart';
import '../utils.dart';

class ConfigCommand extends Command<int> {
  ConfigCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_ConfigShowCommand(logger: _logger));
    addSubcommand(_ConfigSetCommand(logger: _logger));
    addSubcommand(_ConfigValidateCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'config';

  @override
  String get description => 'Inspect and update forgekit.yaml.';
}

abstract class _ConfigLeafCommand extends Command<int> {
  _ConfigLeafCommand({required Logger logger}) : _logger = logger;

  final Logger _logger;

  Directory? projectRoot() {
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
    }
    return root;
  }
}

class _ConfigShowCommand extends _ConfigLeafCommand {
  _ConfigShowCommand({required super.logger});

  @override
  String get name => 'show';

  @override
  String get description =>
      'Print the resolved Flutter ForgeKit CLI configuration.';

  @override
  Future<int> run() async {
    final root = projectRoot();
    if (root == null) return 1;
    try {
      final config = loadForgeKitConfig(root: root, allowMissing: false);
      _logger.info(config.toYaml());
      return 0;
    } on ConfigException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}

class _ConfigSetCommand extends _ConfigLeafCommand {
  _ConfigSetCommand({required super.logger});

  @override
  String get name => 'set';

  @override
  String get description => 'Set one value in forgekit.yaml.';

  @override
  String get invocation => 'forgekit config set <key> <value>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      _logger.err('Expected exactly two arguments: <key> <value>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = projectRoot();
    if (root == null) return 1;
    try {
      final config = loadForgeKitConfig(root: root, allowMissing: false);
      final updated = config.setValue(rest[0], rest[1]);
      await saveForgeKitConfig(root: root, config: updated);
      _logger.success('Set ${rest[0]} to ${rest[1]} in forgekit.yaml.');
      return 0;
    } on ConfigException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}

class _ConfigValidateCommand extends _ConfigLeafCommand {
  _ConfigValidateCommand({required super.logger});

  @override
  String get name => 'validate';

  @override
  String get description => 'Validate forgekit.yaml.';

  @override
  Future<int> run() async {
    final root = projectRoot();
    if (root == null) return 1;
    try {
      loadForgeKitConfig(root: root, allowMissing: false).validate();
      _logger.success('forgekit.yaml is valid.');
      return 0;
    } on ConfigException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}
