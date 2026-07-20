import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../config_service.dart';
import '../openapi_service.dart';
import '../utils.dart';

class ImportCommand extends Command<int> {
  ImportCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_ImportOpenApiCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'import';

  @override
  String get description =>
      'Import external API definitions into Flutter ForgeKit CLI.';
}

class _ImportOpenApiCommand extends Command<int> {
  _ImportOpenApiCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addMultiOption(
        'tag',
        help: 'Only import operations with these OpenAPI tags.',
        splitCommas: true,
      )
      ..addOption(
        'feature',
        help: 'Generate all selected operations into one feature.',
      )
      ..addOption(
        'base-url',
        help: 'Override the first server URL declared by the specification.',
      )
      ..addFlag(
        'tests',
        defaultsTo: true,
        help: 'Generate feature, use-case, and serialization starter tests.',
      )
      ..addFlag(
        'build-runner',
        help: 'Override the forgekit.yaml build_runner setting.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Replace features that already exist.',
      )
      ..addFlag(
        'allow-remote-references',
        negatable: false,
        help: 'Allow a local OpenAPI file to fetch explicitly declared HTTPS '
            r'$ref documents. Redirects remain same-origin.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'openapi';

  @override
  String get description =>
      'Generate typed API features from an OpenAPI 3.0/3.1 document.';

  @override
  String get invocation =>
      'forgekit import openapi <file-or-url> [--tag <tag>] '
      '[--feature <name>] [--no-tests] [--no-build-runner] [--force]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one OpenAPI <file-or-url>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    final config = loadForgeKitConfig(root: root);
    if (config.architecture != 'clean') {
      _logger.err(
        'OpenAPI complete-feature import currently supports the clean '
        'architecture profile. This project uses ${config.architecture}.',
      );
      return 1;
    }

    final source = rest.single;
    final code = await importOpenApi(
      source: source,
      root: root,
      logger: _logger,
      config: config,
      tags: argResults!['tag'] as List<String>,
      featureOverride: argResults!['feature'] as String?,
      baseUrlOverride: argResults!['base-url'] as String?,
      generateTests: argResults!['tests'] as bool,
      force: argResults!['force'] as bool,
      allowRemoteReferences: argResults!['allow-remote-references'] as bool,
    );
    if (code != 0) return code;

    final runBuildRunner = argResults!.wasParsed('build-runner')
        ? argResults!['build-runner'] as bool
        : config.runBuildRunner;
    if (!runBuildRunner) {
      _logger.info(
        'Skipped build_runner (--no-build-runner). Remember to run:\n'
        '  dart run build_runner build',
      );
      return 0;
    }
    return _runBuildRunner(root, _logger);
  }
}

Future<int> _runBuildRunner(Directory root, Logger logger) async {
  final progress = logger.progress('Running build_runner');
  try {
    final process = await Process.start(
      'dart',
      ['run', 'build_runner', 'build'],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      progress.fail('build_runner failed.');
      return 1;
    }
    progress.complete('build_runner finished.');
    return 0;
  } on ProcessException {
    progress.fail('Could not start Dart build_runner.');
    return 1;
  }
}
