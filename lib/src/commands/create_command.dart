import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../config_service.dart';
import '../font_service.dart';
import '../utils.dart';

/// `forgekit create ...`
///
/// Parent command grouping project-creation sub-commands. Currently exposes a
/// single `app` sub-command that scaffolds a new Flutter project.
class CreateCommand extends Command<int> {
  CreateCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_CreateAppCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new Flutter ForgeKit CLI project.';
}

/// `forgekit create app <name> [--org com.forgecyberlabs]`
class _CreateAppCommand extends Command<int> {
  _CreateAppCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'org',
        help: 'The organization identifier (reverse-domain).',
        defaultsTo: 'com.forgecyberlabs',
      )
      ..addOption(
        'font',
        help: 'A Google Font to download and wire into the app theme '
            '(e.g. Poppins).',
      )
      ..addOption(
        'router',
        help: 'Routing style for the generated app.',
        allowed: ['named', 'go_router'],
      )
      ..addOption(
        'architecture',
        help: 'Architecture profile used by the generated project.',
        allowed: creatableArchitectureProfiles,
      )
      ..addOption(
        'state-management',
        help: 'State management used by the generated project.',
        allowed: supportedStateManagement,
      );
  }

  final Logger _logger;

  @override
  String get name => 'app';

  @override
  String get description =>
      'Scaffold a Flutter project from a Flutter ForgeKit CLI profile.';

  @override
  String get invocation =>
      'forgekit create app <name> [--org <org>] [--font <FontName>] '
      '[--architecture clean|mvvm|modular] '
      '[--router named|go_router] '
      '[--state-management provider|riverpod|bloc|cubit]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    // Validate: exactly one positional <name> is required.
    if (rest.isEmpty) {
      _logger.err('Missing required argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    if (rest.length > 1) {
      _logger.err('Too many arguments. Expected a single project <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final name = rest.first;
    final org = args['org'] as String;
    final font = args['font'] as String?;
    final architecture = args['architecture'] as String? ??
        _logger.chooseOne(
          'Select architecture:',
          choices: creatableArchitectureProfiles,
          defaultValue: 'clean',
        ) ??
        'clean';
    final requestedRouter = args['router'] as String?;
    if (architecture == 'modular' && requestedRouter != null) {
      _logger.err(
        '--router cannot be combined with --architecture modular because '
        'Flutter Modular owns routing.',
      );
      return 1;
    }
    final router =
        architecture == 'modular' ? 'modular' : requestedRouter ?? 'named';
    final stateManagement = args['state-management'] as String? ??
        _logger.chooseOne(
          'Select state management:',
          choices: supportedStateManagement,
          defaultValue: 'provider',
        ) ??
        'provider';
    final useRouter = router == 'named';
    final stateFlags = stateManagementMasonFlags(stateManagement);
    final appBrick = switch (architecture) {
      'mvvm' => 'forge_app_mvvm',
      'modular' => 'forge_app_modular',
      _ => 'forge_app',
    };

    final platforms = _logger.chooseAny(
      'Select target platforms to support:',
      choices: ['android', 'ios', 'web', 'macos', 'windows', 'linux'],
      defaultValues: ['android', 'ios', 'web', 'macos', 'windows', 'linux'],
    );

    if (platforms.isEmpty) {
      _logger.err('You must select at least one target platform.');
      return 1;
    }

    final progress = _logger.progress('Creating app "$name"');

    try {
      final flutterResult = await Process.run(
        'flutter',
        ['create', '--org', org, '--platforms', platforms.join(','), name],
        runInShell: true,
      );
      if (flutterResult.exitCode != 0) {
        progress.fail(
          'Failed to run "flutter create". Make sure Flutter is installed.',
        );
        _logger.err(flutterResult.stderr.toString());
        return 1;
      }
    } on ProcessException catch (e) {
      progress.fail(
        'Could not start the "flutter" executable. Make sure Flutter is installed and on your PATH.',
      );
      _logger.err(e.message);
      return 1;
    }

    // Generate into a folder named after the project, overwriting standard files with templates.
    final exitCode = await runMason(
      [
        'make',
        appBrick,
        '-o',
        name,
        '--name',
        name,
        '--org',
        org,
        '--useRouter',
        '$useRouter',
        ...stateFlags,
        '--on-conflict',
        'overwrite',
      ],
      logger: _logger,
    );

    if (exitCode != 0) {
      progress.fail('Failed to create app "$name".');
      return 1;
    }

    final flutterSampleTest = File(
      p.join(name, 'test', 'widget_test.dart'),
    );
    if (flutterSampleTest.existsSync()) {
      await flutterSampleTest.delete();
    }

    progress.complete('Created app "$name" in ./$name');

    try {
      await saveForgeKitConfig(
        root: Directory(name),
        config: ForgeKitConfig(
          architecture: architecture,
          stateManagement: stateManagement,
          router: router,
          dependencyInjection:
              architecture == 'modular' ? 'flutter_modular' : 'injectable',
        ),
      );
    } on ConfigException catch (error) {
      _logger.err('App created, but forgekit.yaml could not be written: '
          '${error.message}');
      return 1;
    }

    // Optionally download and wire up a Google Font into the new project.
    if (font != null && font.trim().isNotEmpty) {
      final fontExit = await addFont(font, logger: _logger, projectDir: name);
      if (fontExit != 0) {
        _logger.warn(
          'App created, but the font "$font" could not be added. '
          'You can retry later with: cd $name && forgekit add font $font',
        );
      }
    }

    _logger
      ..info('')
      ..info('Next steps:')
      ..info('  cd $name')
      ..info('  flutter pub get')
      ..info('  dart run build_runner build');
    return 0;
  }
}
