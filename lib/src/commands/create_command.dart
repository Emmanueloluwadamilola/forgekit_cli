import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../config_service.dart';
import '../font_service.dart';
import '../utils.dart';

const supportedFlutterPlatforms = <String>[
  'android',
  'ios',
  'web',
  'macos',
  'windows',
  'linux',
];

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

/// The flags a non-interactive `forgekit create app` invocation must supply.
///
/// Returns an empty list when the invocation is already complete. Exposed
/// because the message a user sees in CI is the whole point of the check, so it
/// is asserted directly rather than through captured log output.
///
/// [router] is not required for the modular profile, which owns its own routing
/// and rejects `--router` outright.
List<String> missingCreateAppFlags({
  required String? architecture,
  required String? router,
  required String? stateManagement,
  required bool platformsParsed,
}) {
  return <String>[
    if (architecture == null) '--architecture clean|mvvm|modular',
    if (architecture != 'modular' && router == null) '--router named|go_router',
    if (stateManagement == null)
      '--state-management provider|riverpod|bloc|cubit',
    if (!platformsParsed) '--platforms android,ios,web,macos,windows,linux',
  ];
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
      )
      ..addMultiOption(
        'platforms',
        help: 'Flutter target platforms. Pass a comma-separated list to run '
            'non-interactively.',
        valueHelp: 'android,ios,web,macos,windows,linux',
        allowed: supportedFlutterPlatforms,
        splitCommas: true,
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
      '[--state-management provider|riverpod|bloc|cubit] '
      '[--platforms android,ios,web,macos,windows,linux]';

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
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      _logger.err(
        'Project name must be a lowercase Dart package name containing only '
        'letters, digits, and underscores, and it must start with a letter.',
      );
      return 1;
    }
    final destination = Directory(p.join(Directory.current.path, name));
    final destinationType = FileSystemEntity.typeSync(
      destination.path,
      followLinks: false,
    );
    if (destinationType != FileSystemEntityType.notFound) {
      _logger.err(
        'Destination already exists: ${destination.path}\n'
        'ForgeKit refuses to create into an existing file, directory, or '
        'symbolic link.',
      );
      return 1;
    }

    final org = args['org'] as String;
    if (!RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$').hasMatch(org)) {
      _logger.err(
        '--org must be a lowercase reverse-domain identifier such as '
        'com.example or io.example_team.',
      );
      return 1;
    }
    final font = args['font'] as String?;
    final requestedRouter = args['router'] as String?;

    // Without a terminal every prompt below would throw or block, so collect
    // the flags that would have been prompted for and report them together.
    // One round trip beats four. Checked before the toolchain probe because it
    // costs nothing, while the probe spawns a process.
    if (!hasInteractiveTerminal) {
      final missing = missingCreateAppFlags(
        architecture: args['architecture'] as String?,
        router: requestedRouter,
        stateManagement: args['state-management'] as String?,
        platformsParsed: args.wasParsed('platforms'),
      );
      if (missing.isNotEmpty) {
        logMissingInteractiveInput(
          logger: _logger,
          missing: missing,
          invocation: invocation,
        );
        return 1;
      }
    }

    // Verify the toolchain before prompting or writing anything. The bundled app
    // bricks require a newer Dart SDK than the CLI itself does, so without this
    // the failure surfaces as an opaque `pub get` error after creation has
    // already reported success.
    final sdkSupport = await checkGeneratedProjectSdkSupport(logger: _logger);
    if (sdkSupport != 0) return sdkSupport;

    final architecture = args['architecture'] as String? ??
        _logger.chooseOne(
          'Select architecture:',
          choices: creatableArchitectureProfiles,
          defaultValue: 'clean',
        ) ??
        'clean';
    if (architecture == 'modular' && requestedRouter != null) {
      _logger.err(
        '--router cannot be combined with --architecture modular because '
        'Flutter Modular owns routing.',
      );
      return 1;
    }
    final router = architecture == 'modular'
        ? 'modular'
        : requestedRouter ??
            _logger.chooseOne(
              'Select routing:',
              choices: const ['go_router', 'named'],
              defaultValue: 'go_router',
            ) ??
            'go_router';
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

    final platforms = args.wasParsed('platforms')
        ? (args['platforms'] as List<String>).toSet().toList()
        : _logger.chooseAny(
            'Select target platforms to support:',
            choices: supportedFlutterPlatforms,
            defaultValues: supportedFlutterPlatforms,
          );

    if (platforms.isEmpty) {
      _logger.err('You must select at least one target platform.');
      return 1;
    }

    var creationComplete = false;
    try {
      final progress = _logger.progress('Creating app "$name"');

      try {
        final flutterResult = await Process.run(
          'flutter',
          ['create', '--org', org, '--platforms', platforms.join(','), name],
          runInShell: Platform.isWindows,
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

      // Flutter created this destination during this invocation, so the app
      // brick may safely replace Flutter's standard starter files.
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
        requiredBrick: appBrick,
      );

      if (exitCode != 0) {
        progress.fail('Failed to create app "$name".');
        return 1;
      }

      final flutterSampleTest = File(
        p.join(destination.path, 'test', 'widget_test.dart'),
      );
      if (flutterSampleTest.existsSync()) {
        await flutterSampleTest.delete();
      }

      try {
        await saveForgeKitConfig(
          root: destination,
          config: ForgeKitConfig(
            architecture: architecture,
            stateManagement: stateManagement,
            router: router,
            dependencyInjection:
                architecture == 'modular' ? 'flutter_modular' : 'injectable',
          ),
        );
      } on ConfigException catch (error) {
        _logger.err('App creation failed while writing forgekit.yaml: '
            '${error.message}');
        return 1;
      }

      creationComplete = true;
      progress.complete('Created app "$name" in ./$name');

      // Optionally download and wire up a Google Font into the new project.
      if (font != null && font.trim().isNotEmpty) {
        final fontExit = await addFont(
          font,
          logger: _logger,
          projectDir: destination.path,
        );
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
    } finally {
      if (!creationComplete &&
          FileSystemEntity.typeSync(destination.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
        try {
          final type = FileSystemEntity.typeSync(
            destination.path,
            followLinks: false,
          );
          var removed = false;
          switch (type) {
            case FileSystemEntityType.directory:
              await destination.delete(recursive: true);
              removed = true;
              break;
            case FileSystemEntityType.file:
              await File(destination.path).delete();
              removed = true;
              break;
            case FileSystemEntityType.link:
              await Link(destination.path).delete();
              removed = true;
              break;
            case FileSystemEntityType.notFound:
            case FileSystemEntityType.pipe:
            case FileSystemEntityType.unixDomainSock:
              break;
          }
          if (removed) {
            _logger.warn(
              'Removed incomplete app destination after creation failed: '
              '${destination.path}',
            );
          } else if (type != FileSystemEntityType.notFound) {
            _logger.err(
              'Refused to remove an unexpected filesystem object at the app '
              'destination after creation failed: ${destination.path}',
            );
          }
        } on FileSystemException catch (error) {
          _logger.err(
            'Could not remove the incomplete app destination '
            '${destination.path}: ${error.message}',
          );
        }
      }
    }
  }
}
