import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../asset_service.dart';
import '../env_service.dart';
import '../flavor_service.dart';
import '../font_service.dart';
import '../function_service.dart';
import '../i18n_service.dart';
import '../model_service.dart';
import '../screen_service.dart';
import '../test_service.dart';
import '../utils.dart';
import '../widget_registry_service.dart';

/// `forgekit add ...`
///
/// Parent command grouping the artifact-generation sub-commands that operate on
/// an existing ForgeKit project (run from the project root).
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
        defaultsTo: 'named',
      )
      ..addFlag(
        'build-runner',
        help: 'Run build_runner after generation.',
        defaultsTo: true,
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
  String get description => 'Generate a Clean Architecture feature module.';

  @override
  String get invocation =>
      'forgekit add feature <name> [--router named|go_router] [--no-build-runner]';

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
    final router = args['router'] as String;
    // The brick's `useRouter` var means "this project uses named routes" — true
    // for the default `named` style, false when go_router is chosen.
    final useRouter = router == 'named';
    final projectName = detectProjectName();

    final progress = _logger.progress('Adding feature "$name"');

    final exitCode = await runMason(
      [
        'make',
        'forge_feature',
        '--name',
        name,
        '--useRouter',
        '$useRouter',
        '--projectName',
        projectName,
        // Supply every brick var so Mason never stops for an interactive
        // prompt (a hidden prompt behind our spinner looks like a hang).
        // ForgeKit runs build_runner itself below, so the brick must not.
        '--runBuildRunner',
        'false',
        '-o',
        '.',
      ],
      logger: _logger,
    );

    if (exitCode != 0) {
      progress.fail('Failed to add feature "$name".');
      return 1;
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
      );
      if (testCode != 0) return testCode;
    }

    // Optionally run build_runner to wire up DI / serialization codegen.
    final runBuildRunner = args['build-runner'] as bool;
    if (runBuildRunner) {
      return _runBuildRunner(_logger);
    }
    _logger.info(
      'Skipped build_runner (--no-build-runner). Remember to run:\n'
      '  dart run build_runner build --delete-conflicting-outputs',
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
    final root = findProjectRoot() ?? Directory.current;

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

    final projectName = detectProjectName();
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
  _AddServiceCommand({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  @override
  String get name => 'service';

  @override
  String get description => 'Generate a cross-cutting singleton service.';

  @override
  String get invocation => 'forgekit add service <name>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      _logger.err('Expected exactly one argument: <name>.');
      _logger.info('Usage: $invocation');
      return 1;
    }

    final name = rest.first;
    final projectName = detectProjectName();
    final progress = _logger.progress('Adding service "$name"');

    final exitCode = await runMason(
      [
        'make',
        'forge_service',
        '--name',
        name,
        '--projectName',
        projectName,
        '-o',
        '.',
      ],
      logger: _logger,
    );

    if (exitCode != 0) {
      progress.fail('Failed to add service "$name".');
      return 1;
    }
    progress.complete('Added service "$name".');
    return 0;
  }
}

/// `forgekit add font <FontName>`
///
/// Downloads the font's available static weights from Google Fonts into
/// `assets/fonts/`, registers them in `pubspec.yaml`, and sets it as the app's
/// `fontFamily`. Run from the root of an existing ForgeKit project.
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
        help: 'Run build_runner after generation.',
        defaultsTo: true,
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
      'forgekit add function [<feature>] <name> [--method <m>] [--path <p>] [--no-build-runner]';

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

    if (args['build-runner'] as bool) {
      return _runBuildRunner(_logger, workingDirectory: root.path);
    }
    _logger.info(
      'Skipped build_runner (--no-build-runner). Remember to run:\n'
      '  dart run build_runner build --delete-conflicting-outputs',
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
        help: 'Run build_runner after generation.',
        defaultsTo: true,
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
      'forgekit add model [<feature>] <name> [--no-build-runner]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final rest = args.rest;

    final root = findProjectRoot();
    if (root == null) {
      _logger.err('No pubspec.yaml found in this or any parent directory.');
      return 1;
    }

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

    if (args['build-runner'] as bool) {
      return _runBuildRunner(_logger, workingDirectory: root.path);
    }
    _logger.info(
      'Skipped build_runner (--no-build-runner). Remember to run:\n'
      '  dart run build_runner build --delete-conflicting-outputs',
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

    final feature = _snakeCase(rest[0]);
    final rawName = rest[1];
    final name = _snakeCase(rawName);
    final className = '${_pascalCase(rawName)}Usecase';
    final projectName = detectProjectName();

    final dir = Directory(
      p.join('lib', 'features', feature, 'domain', 'usecase'),
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

    progress.complete('Created $filePath');
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

/// Runs `dart run build_runner build --delete-conflicting-outputs`.
///
/// Returns `0` on success / `1` on failure (or if `dart` is unavailable).
Future<int> _runBuildRunner(Logger logger, {String? workingDirectory}) async {
  final progress = logger.progress('Running build_runner');
  try {
    final process = await Process.start(
      'dart',
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
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
