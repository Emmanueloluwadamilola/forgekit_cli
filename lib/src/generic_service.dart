import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'service_wiring_service.dart';
import 'utils.dart';

Future<int> addGenericService({
  required String name,
  required Directory root,
  required Logger logger,
  required bool runBuildRunner,
  bool runPackageCommands = true,
}) async {
  final serviceSnake = snakeCase(name);
  final servicePascal = pascalCase(name);
  final serviceCamel = camelCase(name);
  if (serviceSnake.isEmpty ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(servicePascal)) {
    logger.err(
      'Use a service name whose generated Dart type starts with a letter and '
      'contains only letters or digits.',
    );
    return 1;
  }

  final config = loadForgeKitConfig(root: root);
  if (!creatableArchitectureProfiles.contains(config.architecture)) {
    logger.err(
      'Service generation is not available for the '
      '"${config.architecture}" adoption profile.',
    );
    return 1;
  }
  final projectName = detectProjectName(root: root);
  final className = '${servicePascal}Service';
  final instanceName = '${serviceCamel}Service';
  final serviceFile = File(
    p.join(root.path, 'lib', 'services', '${serviceSnake}_service.dart'),
  );
  if (serviceFile.existsSync()) {
    logger.err(
      'Service already exists: '
      '${p.relative(serviceFile.path, from: root.path)}',
    );
    return 1;
  }

  final progress = logger.progress('Adding generic service "$serviceSnake"');
  try {
    await serviceFile.parent.create(recursive: true);
    await serviceFile.writeAsString(
      _genericService(
        className: className,
        instanceName: instanceName,
        modular: config.architecture == 'modular',
      ),
    );
    if (config.architecture == 'modular') {
      wireModularInitializedService(
        root: root,
        projectName: projectName,
        serviceSnake: serviceSnake,
        className: className,
        instanceName: instanceName,
      );
    } else {
      wireGetItInitializedService(
        root: root,
        projectName: projectName,
        serviceSnake: serviceSnake,
        className: className,
      );
    }
  } on FileSystemException catch (error) {
    progress.fail('Could not generate the service.');
    logger.err(error.message);
    return 1;
  } on FormatException catch (error) {
    progress.fail('Could not wire the service into application startup.');
    logger.err(error.message);
    return 1;
  }
  progress.complete('Added and initialized $className.');

  if (runPackageCommands &&
      config.architecture != 'modular' &&
      runBuildRunner) {
    final code = await runInheritedProjectCommand(
      'dart',
      ['run', 'build_runner', 'build'],
      root: root,
      logger: logger,
      label: 'build_runner',
    );
    if (code != 0) return code;
  }

  logger
    ..info('')
    ..info('Generated:')
    ..info('  ${p.relative(serviceFile.path, from: root.path)}')
    ..info('Updated:')
    ..info('  lib/main.dart')
    ..info(
      config.architecture == 'modular'
          ? '  lib/app/app_module.dart'
          : '  Injectable dependency graph (via build_runner)',
    )
    ..info('')
    ..success('$className is initialized before runApp.');

  if (config.architecture != 'modular' && !runBuildRunner) {
    logger.info('Run `dart run build_runner build` before compiling the app.');
  }
  return 0;
}

String _genericService({
  required String className,
  required String instanceName,
  required bool modular,
}) =>
    '''
${modular ? '' : "import 'package:injectable/injectable.dart';\n\n"}/// Cross-cutting application service with explicit startup initialization.
${modular ? '' : '@lazySingleton\n'}class $className {
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    // TODO: configure SDKs, permissions, subscriptions, or other resources.
    _initialized = true;
  }
}
${modular ? '\nfinal $instanceName = $className();\n' : ''}''';
