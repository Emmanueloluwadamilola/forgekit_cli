import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../asset_service.dart';
import '../config_service.dart';
import '../env_service.dart';
import '../flavor_service.dart';
import '../font_service.dart';
import '../function_service.dart';
import '../generic_service.dart';
import '../i18n_service.dart';
import '../model_service.dart';
import '../route_wiring_service.dart';
import '../screen_service.dart';
import '../storage_service.dart';
import '../test_service.dart';
import '../utils.dart';
import '../widget_registry_service.dart';

/// `forgekit add ...`
///
/// Parent command grouping the artifact-generation sub-commands that operate on
/// an existing Flutter ForgeKit CLI project (run from the project root).
class AddCommand extends Command<int> {
  AddCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_AddFeatureCommand(logger: _logger));
    addSubcommand(_AddWidgetCommand(logger: _logger));
    addSubcommand(_AddServiceCommand(logger: _logger));
    addSubcommand(_AddUsecaseCommand(logger: _logger));
    addSubcommand(_AddFontCommand(logger: _logger));
    addSubcommand(_AddFunctionCommand(logger: _logger));
    addSubcommand(_AddModelCommand(logger: _logger));
    addSubcommand(_AddScreenCommand(logger: _logger));
    addSubcommand(_AddAssetCommand(logger: _logger));
    addSubcommand(_AddFlavorCommand(logger: _logger));
    addSubcommand(_AddTestCommand(logger: _logger));
    addSubcommand(_AddI18nCommand(logger: _logger));
    addSubcommand(_AddStringCommand(logger: _logger));
    addSubcommand(_AddEnvCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'add';

  @override
  String get description =>
      'Add a feature, function, model, screen, widget, service, usecase, '
      'font, asset, flavor, test, i18n, string, or env.';
}

/// `forgekit add feature <name> [--router named|go_router] [--no-build-runner]`
class _AddFeatureCommand extends Command<int> {
  _AddFeatureCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'router',
        help: 'Routing style for the generated feature.',
        allowed: ['named', 'go_router'],
      )
      ..addFlag(
        'build-runner',
        help: 'Override the forgekit.yaml build_runner setting.',
      )
      ..addFlag(
        'with-tests',
        negatable: false,
        help: 'Generate starter tests for the feature.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'feature';

  @override
  String get description =>
      'Generate a feature for the project architecture profile.';

  @override
  String get invocation =>
      'forgekit add feature <name> [--router named|go_router] '
      '[--with-tests] [--no-build-runner]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final name = rest.first;
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    final config = loadForgeKitConfig(root: root);
    if (!creatableArchitectureProfiles.contains(config.architecture)) {
      _logger.err(
        'Feature generation is not available for the '
        '"${config.architecture}" adoption profile. Create a Clean, MVVM, or '
        'Modular ForgeKit project, or migrate the application architecture '
        'before changing forgekit.yaml.',
      );
      return 1;
    }
    final requestedRouter = args['router'] as String?;
    if (config.architecture == 'modular' && requestedRouter != null) {
      _logger.err(
        '--router is not available for modular projects because the module '
        'owns its routes.',
      );
      return 1;
    }
    if (requestedRouter != null && requestedRouter != config.router) {
      _logger.err(
        'This project uses router "${config.router}". A feature cannot use '
        'the incompatible router "$requestedRouter". Update forgekit.yaml '
        'and the application router together before changing route styles.',
      );
      return 1;
    }
    final router = requestedRouter ?? config.router;
    final stateManagement = config.stateManagement;
    // The brick's `useRouter` var means "this project uses named routes" — true
    // for the default `named` style, false when go_router is chosen.
    final useRouter = router == 'named';
    final projectName = detectProjectName(root: root);
    final featureBrick = switch (config.architecture) {
      'mvvm' => 'forge_feature_mvvm',
      'modular' => 'forge_feature_modular',
      _ => 'forge_feature',
    };

    final progress = _logger.progress('Adding feature "$name"');

    final exitCode = await runMason(
      [
        'make',
        featureBrick,
        '--name',
        name,
        '--useRouter',
        '$useRouter',
        '--projectName',
        projectName,
        ...stateManagementMasonFlags(stateManagement),
        // Supply every brick var so Mason never stops for an interactive
        // prompt (a hidden prompt behind our spinner looks like a hang).
        // Flutter ForgeKit CLI runs build_runner, so the brick must not.
        '--runBuildRunner',
        'false',
        '-o',
        '.',
      ],
      logger: _logger,
      requiredBrick: featureBrick,
    );

    if (exitCode != 0) {
      progress.fail('Failed to add feature "$name".');
      return 1;
    }

    if (config.architecture == 'mvvm' && useRouter) {
      final emptyRoutesFile = File(
        p.join(
          root.path,
          'lib',
          'ui',
          _snakeCase(name),
          '${_snakeCase(name)}_routes.dart',
        ),
      );
      if (emptyRoutesFile.existsSync() &&
          emptyRoutesFile.readAsStringSync().trim().isEmpty) {
        await emptyRoutesFile.delete();
      }
    }

    if (config.architecture == 'modular') {
      final registered = _registerModularFeature(root: root, feature: name);
      if (!registered) {
        progress.fail('Generated feature, but could not register its module.');
        _logger.err(
          'Expected the marker `// forgekit:modules` in '
          'lib/app/app_module.dart.',
        );
        return 1;
      }
    } else {
      try {
        registerFeatureRoute(
          root: root,
          config: config.copyWith(router: router),
          projectName: projectName,
          feature: name,
        );
      } on RouteWiringException catch (error) {
        progress.fail('Generated feature, but could not register its route.');
        _logger.err(error.message);
        return 1;
      }
    }
    progress.complete('Added feature "$name".');

    if (args['with-tests'] as bool) {
      final root = findProjectRoot();
      if (root == null) {
        _logger.err('No pubspec.yaml found after feature generation.');
        return 1;
      }
      final testCode = await addFeatureTests(
        feature: name,
        logger: _logger,
        root: root,
        stateManagement: stateManagement,
      );
      if (testCode != 0) return testCode;
    }

    // Optionally run build_runner to wire up DI / serialization codegen.
    final runBuildRunner = args.wasParsed('build-runner')
        ? args['build-runner'] as bool
        : config.runBuildRunner;
    if (runBuildRunner) {
      return _runBuildRunner(_logger);
    }
    _logger.info(
      'Skipped build_runner (--no-build-runner). Remember to run:\n'
      '  dart run build_runner build',
    );
    return 0;
  }
}

/// `forgekit add widget <name>`
class _AddWidgetCommand extends Command<int> {
  _AddWidgetCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Overwrite an existing widget when installing a synced widget.',
      )
      ..addFlag(
        'starter',
        negatable: false,
        help:
            'Generate the starter widget template even if a synced widget exists.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'widget';

  @override
  String get description =>
      'Add a synced shared widget or generate a starter widget.';

  @override
  String get invocation => 'forgekit add widget <name> [--force] [--starter]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final name = rest.first;
    final useStarter = argResults!['starter'] as bool;
    final force = argResults!['force'] as bool;
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    if (!useStarter) {
      final synced = await installSyncedWidget(
        name: name,
        root: root,
        force: force,
        logger: _logger,
      );

      if (synced != null) {
        if (synced.name.isEmpty) return 1;
        _logger.success('Added synced widget "${synced.name}".');
        _logger.info('Wrote ${synced.path}');
        return 0;
      }
    }

    final config = loadForgeKitConfig(root: root);
    if (config.architecture != 'clean') {
      _logger.err(
        'Starter widget generation currently supports the clean architecture '
        'profile. This project uses ${config.architecture}. Sync a widget '
        'explicitly or add architecture-specific widget support first.',
      );
      return 1;
    }

    final projectName = detectProjectName(root: root);
    final progress = _logger.progress('Adding widget "$name"');

    final exitCode = await runMason(
      [
        'make',
        'forge_widget',
        '--name',
        name,
        '--projectName',
        projectName,
        '-o',
        '.',
      ],
      logger: _logger,
      requiredBrick: 'forge_widget',
    );

    if (exitCode != 0) {
      progress.fail('Failed to add widget "$name".');
      return 1;
    }
    progress.complete('Added widget "$name".');
    return 0;
  }
}

/// `forgekit add service <name>`
class _AddServiceCommand extends Command<int> {
  _AddServiceCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'driver',
        allowed: ['generic', ...storageServiceDrivers],
        help: 'Service implementation. Omit in a terminal to choose '
            'interactively.',
      )
      ..addFlag(
        'build-runner',
        help: 'Override the forgekit.yaml build_runner setting.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'service';

  @override
  String get description =>
      'Generate a generic singleton or a fully wired storage service.';

  @override
  String get invocation => 'forgekit add service <name> '
      '[--driver generic|shared_preferences|flutter_secure_storage] '
      '[--no-build-runner]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    final name = rest.first;
    final requestedDriver = argResults!['driver'] as String?;
    final driver = requestedDriver ??
        (hasInteractiveTerminal
            ? _logger.chooseOne(
                'Select service type:',
                choices: const [
                  'generic',
                  'shared_preferences',
                  'flutter_secure_storage',
                ],
                defaultValue: 'generic',
              )
            : 'generic') ??
        'generic';
    final config = loadForgeKitConfig(root: root);
    final runBuildRunner = argResults!.wasParsed('build-runner')
        ? argResults!['build-runner'] as bool
        : config.runBuildRunner;
    if (driver != 'generic') {
      return addStorageService(
        name: name,
        driver: driver,
        root: root,
        logger: _logger,
        runBuildRunner: runBuildRunner,
      );
    }
    return addGenericService(
      name: name,
      root: root,
      logger: _logger,
      runBuildRunner: runBuildRunner,
    );
  }
}

/// `forgekit add font <FontName>`
///
/// Downloads the font's available static weights from Google Fonts into
/// `assets/fonts/`, registers them in `pubspec.yaml`, and sets it as the app's
/// `fontFamily`. Run from a Flutter ForgeKit CLI project root.
class _AddFontCommand extends Command<int> {
  _AddFontCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'font';

  @override
  String get description =>
      'Download a Google Font and wire it into pubspec + the app theme.';

  @override
  String get invocation => 'forgekit add font <FontName>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <FontName>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    return addFont(rest.first, logger: _logger);
  }
}

/// `forgekit add function <feature> <name> [--method] [--path] [--no-build-runner]`
///
/// Generates a full API operation for an existing feature: the endpoint on the
/// retrofit API service, response DTO + domain model, an optional request
/// payload (both from JSON pasted at the terminal), a use case, and the wiring
/// through the repository (abstract + impl) and provider.
class _AddFunctionCommand extends Command<int> {
  _AddFunctionCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'method',
        help: 'HTTP method. Prompts if omitted.',
        allowed: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
      )
      ..addOption(
        'path',
        help: 'Endpoint path (e.g. /auth/login). Prompts if omitted.',
      )
      ..addFlag(
        'build-runner',
        help: 'Override the forgekit.yaml build_runner setting.',
      )
      ..addFlag(
        'with-tests',
        negatable: false,
        help: 'Generate a starter use case test file.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'function';

  @override
  String get description =>
      'Add an API operation (endpoint + DTO/model/payload + usecase) to a feature.';

  @override
  String get invocation =>
      'forgekit add function [<feature>] <name> [--method <m>] [--path <p>] '
      '[--with-tests] [--no-build-runner]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      _logger.info('Run this from inside a Flutter project.');
      return 1;
    }
    final config = loadForgeKitConfig(root: root);

    // Two forms:
    //   forgekit add function <feature> <name>   (from anywhere in the project)
    //   forgekit add function <name>             (from inside lib/features/<feature>/)
    final String feature;
    final String functionName;
    if (rest.length == 2) {
      feature = rest[0];
      functionName = rest[1];
    } else if (rest.length == 1) {
      final inferred = inferFeatureName(root: root);
      if (inferred == null) {
        _logger.err(
          'Could not infer the feature from the current directory.\n'
          'Either pass it explicitly ("forgekit add function <feature> ${rest[0]}") '
          'or run this from inside lib/features/<feature>/.',
        );
        return 1;
      }
      feature = inferred;
      functionName = rest[0];
      _logger.info('Using feature "$feature" (inferred from directory).');
    } else {
      _logger.err('Expected <feature> <name>, or just <name> from inside a '
          'feature folder.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final code = await addFunction(
      feature: feature,
      functionName: functionName,
      logger: _logger,
      root: root,
      method: args['method'] as String?,
      path: args['path'] as String?,
    );
    if (code != 0) return code;

    if (args['with-tests'] as bool) {
      final testCode = await addFunctionTest(
        feature: feature,
        functionName: functionName,
        logger: _logger,
        root: root,
      );
      if (testCode != 0) return testCode;
    }

    final runBuildRunner = args.wasParsed('build-runner')
        ? args['build-runner'] as bool
        : config.runBuildRunner;
    if (runBuildRunner) {
      return _runBuildRunner(_logger, workingDirectory: root.path);
    }
    _logger.info(
      'Skipped build_runner (--no-build-runner). Remember to run:\n'
      '  dart run build_runner build',
    );
    return 0;
  }
}

/// `forgekit add model [<feature>] <name> [--no-build-runner]`
///
/// Generates a domain model + `@JsonSerializable` DTO from pasted JSON. Name the
/// feature to place it there, run it from inside a feature folder to infer it,
/// or give just the name (from the project root) to put it in core.
class _AddModelCommand extends Command<int> {
  _AddModelCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'feature',
        help: 'Place the model inside this feature instead of core.',
      )
      ..addFlag(
        'build-runner',
        help: 'Override the forgekit.yaml build_runner setting.',
      )
      ..addFlag(
        'with-tests',
        negatable: false,
        help: 'Generate a starter model test file.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'model';

  @override
  String get description =>
      'Generate a domain model + DTO from pasted JSON (core or a feature).';

  @override
  String get invocation =>
      'forgekit add model [<feature>] <name> [--feature <name>] '
      '[--with-tests] [--no-build-runner]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    final config = loadForgeKitConfig(root: root);

    // Three forms, mirroring `add screen`:
    //   add model <feature> <name>   → that feature
    //   add model <name>             → --feature, else inferred from cwd, else core
    final String name;
    String? feature;
    if (rest.length == 2) {
      feature = rest[0];
      name = rest[1];
    } else if (rest.length == 1) {
      name = rest[0];
      final flag = args['feature'] as String?;
      if (flag != null) {
        feature = flag;
      } else {
        final inferred = inferFeatureName(root: root);
        if (inferred != null) {
          feature = inferred;
          _logger.info('Using feature "$feature" (inferred from directory).');
        } // else: null → core
      }
    } else {
      _logger.err('Expected [<feature>] <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final code = await addModel(
      name: name,
      logger: _logger,
      root: root,
      feature: feature,
    );
    if (code != 0) return code;

    if (args['with-tests'] as bool) {
      final testCode = await addModelTest(
        name: name,
        logger: _logger,
        root: root,
        feature: feature,
      );
      if (testCode != 0) return testCode;
    }

    final runBuildRunner = args.wasParsed('build-runner')
        ? args['build-runner'] as bool
        : config.runBuildRunner;
    if (runBuildRunner) {
      return _runBuildRunner(_logger, workingDirectory: root.path);
    }
    _logger.info(
      'Skipped build_runner (--no-build-runner). Remember to run:\n'
      '  dart run build_runner build',
    );
    return 0;
  }
}

/// `forgekit add screen [<feature>] <name>`
///
/// Adds a screen (with a static route `id`) to a feature. The feature can be
/// named explicitly or inferred from the current directory.
class _AddScreenCommand extends Command<int> {
  _AddScreenCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'screen';

  @override
  String get description => 'Add a screen (with a route id) to a feature.';

  @override
  String get invocation => 'forgekit add screen [<feature>] <name>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    final String feature;
    final String screenName;
    if (rest.length == 2) {
      feature = rest[0];
      screenName = rest[1];
    } else if (rest.length == 1) {
      final inferred = inferFeatureName(root: root);
      if (inferred == null) {
        _logger.err(
          'Could not infer the feature from the current directory.\n'
          'Pass it explicitly ("forgekit add screen <feature> ${rest[0]}") '
          'or run from inside lib/features/<feature>/.',
        );
        return 1;
      }
      feature = inferred;
      screenName = rest[0];
      _logger.info('Using feature "$feature" (inferred from directory).');
    } else {
      _logger.err('Expected [<feature>] <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    return addScreen(
      feature: feature,
      screenName: screenName,
      logger: _logger,
      root: root,
    );
  }
}

/// `forgekit add asset <path> [--dir <subfolder>]`
///
/// Copies a file into `assets/`, registers its folder in `pubspec.yaml`, and
/// adds a typed constant to `core/presentation/resources/drawables.dart`.
class _AddAssetCommand extends Command<int> {
  _AddAssetCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'dir',
        help: 'Subfolder under assets/ (default: chosen by file type / '
            'the source folder name).',
      )
      ..addFlag(
        'recursive',
        abbr: 'r',
        negatable: false,
        help: 'When given a folder, include files in nested subfolders too.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'asset';

  @override
  String get description =>
      'Add an asset file or folder: copy in, register in pubspec, and generate '
      'typed Drawables constants.';

  @override
  String get invocation =>
      'forgekit add asset <file-or-folder> [--dir <subfolder>] [-r|--recursive]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <file-or-folder>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    return addAsset(
      sourcePath: rest.first,
      logger: _logger,
      root: root,
      dir: args['dir'] as String?,
      recursive: args['recursive'] as bool,
    );
  }
}

/// `forgekit add flavor <a,b,c>`
///
/// Scaffolds Dart-side build flavors (a `FlavorConfig` + per-flavor
/// `main_<flavor>.dart` entrypoints).
class _AddFlavorCommand extends Command<int> {
  _AddFlavorCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'flavor';

  @override
  String get description =>
      'Scaffold build flavors (config + per-flavor entrypoints).';

  @override
  String get invocation => 'forgekit add flavor <dev,staging,prod>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      _logger.err('Expected a comma-separated list of flavors.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    // Accept "dev,staging" or "dev staging" (or a mix).
    final flavors = rest
        .expand((a) => a.split(','))
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    return addFlavors(flavors: flavors, logger: _logger, root: root);
  }
}

/// `forgekit add i18n <locales>`
class _AddI18nCommand extends Command<int> {
  _AddI18nCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'i18n';

  @override
  String get description =>
      'Scaffold Flutter localization with ARB files and l10n.yaml.';

  @override
  String get invocation => 'forgekit add i18n <en,fr,es>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      _logger.err('Expected a comma-separated list of locales.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    final locales = rest
        .expand((arg) => arg.split(','))
        .map((locale) => locale.trim())
        .where((locale) => locale.isNotEmpty)
        .toList();
    return addI18n(locales: locales, logger: _logger, root: root);
  }
}

/// `forgekit add string <key> <value>`
class _AddStringCommand extends Command<int> {
  _AddStringCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addOption(
      'locale',
      abbr: 'l',
      help:
          'Update only one locale, e.g. en or en_US. Defaults to all ARB files.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'string';

  @override
  String get description => 'Add a localized string to ARB files.';

  @override
  String get invocation => 'forgekit add string <key> <value> [--locale en]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      _logger.err('Expected <key> <value>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    return addLocalizedString(
      key: rest.first,
      value: rest.skip(1).join(' '),
      logger: _logger,
      root: root,
      locale: argResults!['locale'] as String?,
    );
  }
}

/// `forgekit add env <names>`
class _AddEnvCommand extends Command<int> {
  _AddEnvCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'env';

  @override
  String get description => 'Scaffold JSON-backed environment configuration.';

  @override
  String get invocation => 'forgekit add env <dev,staging,prod>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      _logger.err('Expected a comma-separated list of environments.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    final environments = rest
        .expand((arg) => arg.split(','))
        .map((env) => env.trim())
        .where((env) => env.isNotEmpty)
        .toList();
    return addEnvironments(
      environments: environments,
      logger: _logger,
      root: root,
    );
  }
}

/// `forgekit add usecase <feature> <name>`
///
/// There is no dedicated brick for a single usecase, so the file is written
/// directly from a Dart string template into
/// `lib/features/<feature>/domain/usecase/<name>_usecase.dart`.
class _AddUsecaseCommand extends Command<int> {
  _AddUsecaseCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'usecase';

  @override
  String get description =>
      'Generate a single UseCase file inside an existing feature.';

  @override
  String get invocation => 'forgekit add usecase <feature> <name>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      _logger.err('Expected two arguments: <feature> <name>.');
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
        'forgekit add usecase currently supports the clean architecture '
        'profile. This project uses ${config.architecture}.',
      );
      return 1;
    }

    final feature = _snakeCase(rest[0]);
    final rawName = rest[1];
    final name = _snakeCase(rawName);
    final className = '${_pascalCase(rawName)}Usecase';
    if (feature.isEmpty ||
        name.isEmpty ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9]*Usecase$').hasMatch(className)) {
      _logger.err(
        'Feature and use-case names must generate valid Dart identifiers.',
      );
      return 1;
    }
    final projectName = detectProjectName(root: root);
    final featureDir = Directory(
      p.join(root.path, 'lib', 'features', feature),
    );
    if (!featureDir.existsSync()) {
      _logger
          .err('Feature "$feature" not found (looked for ${featureDir.path}).');
      _logger.info('Create it first with: forgekit add feature $feature');
      return 1;
    }

    final dir = Directory(
      p.join(root.path, 'lib', 'features', feature, 'domain', 'usecase'),
    );
    final filePath = p.join(dir.path, '${name}_usecase.dart');
    final file = File(filePath);

    if (file.existsSync()) {
      _logger.err('File already exists: $filePath');
      return 1;
    }

    final progress = _logger.progress('Adding usecase "$className"');
    try {
      dir.createSync(recursive: true);
      file.writeAsStringSync(
        _useCaseTemplate(
          projectName: projectName,
          className: className,
        ),
      );
    } on FileSystemException catch (e) {
      progress.fail('Failed to write usecase file.');
      _logger.err(e.message);
      return 1;
    }

    progress.complete('Created ${p.relative(filePath, from: root.path)}');
    return 0;
  }
}

/// `forgekit add test ...`
class _AddTestCommand extends Command<int> {
  _AddTestCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_AddFeatureTestCommand(logger: _logger));
    addSubcommand(_AddModelTestCommand(logger: _logger));
    addSubcommand(_AddFunctionTestCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'test';

  @override
  String get description =>
      'Generate starter tests for existing features, models, or functions.';
}

class _AddFeatureTestCommand extends Command<int> {
  _AddFeatureTestCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Overwrite existing generated tests.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'feature';

  @override
  String get description => 'Generate state/provider tests for a feature.';

  @override
  String get invocation => 'forgekit add test feature <name> [--force]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }
    return addFeatureTests(
      feature: rest.first,
      logger: _logger,
      root: root,
      force: argResults!['force'] as bool,
    );
  }
}

class _AddModelTestCommand extends Command<int> {
  _AddModelTestCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'feature',
        help: 'Model feature. Omit for a core model.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        negatable: false,
        help: 'Overwrite an existing generated test.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'model';

  @override
  String get description => 'Generate a starter test for a model.';

  @override
  String get invocation =>
      'forgekit add test model [<feature>] <name> [--force]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    final String name;
    String? feature;
    if (rest.length == 2) {
      feature = rest[0];
      name = rest[1];
    } else if (rest.length == 1) {
      name = rest[0];
      feature =
          argResults!['feature'] as String? ?? inferFeatureName(root: root);
    } else {
      _logger.err('Expected [<feature>] <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    return addModelTest(
      name: name,
      logger: _logger,
      root: root,
      feature: feature,
      force: argResults!['force'] as bool,
    );
  }
}

class _AddFunctionTestCommand extends Command<int> {
  _AddFunctionTestCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Overwrite an existing generated test.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'function';

  @override
  String get description => 'Generate a starter test for a feature use case.';

  @override
  String get invocation =>
      'forgekit add test function <feature> <name> [--force]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      _logger.err('Expected two arguments: <feature> <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }
    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

    return addFunctionTest(
      feature: rest[0],
      functionName: rest[1],
      logger: _logger,
      root: root,
      force: argResults!['force'] as bool,
    );
  }
}

/// Runs `dart run build_runner build`.
///
/// Returns `0` on success / `1` on failure (or if `dart` is unavailable).
Future<int> _runBuildRunner(Logger logger, {String? workingDirectory}) async {
  final progress = logger.progress('Running build_runner');
  try {
    final process = await Process.start(
      'dart',
      ['run', 'build_runner', 'build'],
      mode: ProcessStartMode.inheritStdio,
      workingDirectory: workingDirectory,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      progress.fail('build_runner failed.');
      return 1;
    }
    progress.complete('build_runner finished.');
    return 0;
  } on ProcessException {
    progress.fail('Could not start the dart executable for build_runner.');
    return 1;
  }
}

bool _registerModularFeature({
  required Directory root,
  required String feature,
}) {
  final snake = _snakeCase(feature);
  final camel = _pascalCase(feature);
  final moduleName = camel.isEmpty
      ? ''
      : '${camel[0].toLowerCase()}${camel.substring(1)}Module';
  final file = File(p.join(root.path, 'lib', 'app', 'app_module.dart'));
  if (!file.existsSync() || moduleName.isEmpty) return false;

  var content = file.readAsStringSync();
  const marker = '// forgekit:modules';
  if (!content.contains(marker)) return false;

  final import = "import '../modules/$snake/${snake}_module.dart';";
  if (!content.contains(import)) {
    final imports = RegExp(r"^import '.+';\s*$", multiLine: true)
        .allMatches(content)
        .toList();
    if (imports.isEmpty) return false;
    final lastImport = imports.last;
    content = content.replaceRange(
      lastImport.end,
      lastImport.end,
      '\n$import',
    );
  }

  final registration = '..module($moduleName)';
  if (!content.contains(registration)) {
    content = content.replaceFirst(marker, '$registration\n      $marker');
  }
  file.writeAsStringSync(content);
  return true;
}

/// Renders the UseCase file contents following the spec's UseCase pattern
/// (see core/domain/usecase/use_case.dart). The generated usecase extends
/// `UseCase<dynamic, NoParams>` as a starting point that the developer fills in.
String _useCaseTemplate({
  required String projectName,
  required String className,
}) {
  return '''
import 'package:$projectName/core/domain/api/api_result.dart';
import 'package:$projectName/core/domain/usecase/use_case.dart';

/// $className
///
/// TODO: Replace the [Type] and [Params] type arguments with the concrete
/// return type and parameter type for this usecase, then inject the repository
/// it depends on.
class $className extends UseCase<dynamic, NoParams> {
  $className();

  @override
  Future<ApiResult<dynamic>> call(NoParams params) {
    // TODO: implement call by delegating to a repository.
    throw UnimplementedError();
  }
}
''';
}

/// Converts an arbitrary identifier to `snake_case`.
String _snakeCase(String input) {
  final spaced = input
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      // Insert underscore before capitals (camelCase / PascalCase -> snake).
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) {
    return '${m[1]}_${m[2]}';
  });
  return spaced
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '')
      .toLowerCase();
}

/// Converts an arbitrary identifier to `PascalCase`.
String _pascalCase(String input) {
  final parts = _snakeCase(input).split('_').where((s) => s.isNotEmpty);
  return parts.map((s) => s[0].toUpperCase() + s.substring(1)).join();
}
