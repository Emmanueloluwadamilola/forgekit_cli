import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'config_service.dart';
import 'json_to_dart.dart';
import 'service_wiring_service.dart';
import 'utils.dart';

const storageServiceDrivers = [
  'shared_preferences',
  'flutter_secure_storage',
];

/// Generates a complete storage service and wires it into app startup.
///
/// Package commands can be disabled by tests and other programmatic callers.
/// The CLI enables them so a successful command leaves the project ready to
/// compile and run.
Future<int> addStorageService({
  required String name,
  required String driver,
  required Directory root,
  required Logger logger,
  required bool runBuildRunner,
  bool runPackageCommands = true,
}) async {
  final selectedDriver = driver.trim().toLowerCase();
  if (!storageServiceDrivers.contains(selectedDriver)) {
    logger.err(
      'Unsupported storage driver "$driver". Choose one of: '
      '${storageServiceDrivers.join(', ')}.',
    );
    return 1;
  }

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

  final className = '${servicePascal}Service';
  final instanceName = '${serviceCamel}Service';
  final progress = logger.progress(
    'Adding $selectedDriver service "$serviceSnake"',
  );

  try {
    _addDependency(root, selectedDriver);
    await serviceFile.parent.create(recursive: true);
    await serviceFile.writeAsString(
      switch (selectedDriver) {
        'shared_preferences' => _sharedPreferencesService(
            className: className,
            instanceName: instanceName,
            modular: config.architecture == 'modular',
          ),
        'flutter_secure_storage' => _secureStorageService(
            className: className,
            instanceName: instanceName,
            modular: config.architecture == 'modular',
          ),
        _ => throw StateError('Unsupported driver: $selectedDriver'),
      },
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
    progress.fail('Could not generate the storage service.');
    logger.err(error.message);
    return 1;
  } on ArgumentError catch (error) {
    progress.fail('Could not update project configuration.');
    logger.err(error.message ?? error.toString());
    return 1;
  } on FormatException catch (error) {
    progress.fail('Could not update project configuration.');
    logger.err(error.message);
    return 1;
  }

  progress.complete('Added $className with $selectedDriver.');

  if (runPackageCommands) {
    final pubGetCode = await runInheritedProjectCommand(
      'flutter',
      ['pub', 'get'],
      root: root,
      logger: logger,
      label: 'flutter pub get',
    );
    if (pubGetCode != 0) return pubGetCode;

    if (config.architecture != 'modular' && runBuildRunner) {
      final buildCode = await runInheritedProjectCommand(
        'dart',
        ['run', 'build_runner', 'build'],
        root: root,
        logger: logger,
        label: 'build_runner',
      );
      if (buildCode != 0) return buildCode;
    }
  }

  logger
    ..info('')
    ..info('Generated:')
    ..info('  ${p.relative(serviceFile.path, from: root.path)}')
    ..info('Updated:')
    ..info('  pubspec.yaml')
    ..info('  lib/main.dart')
    ..info(
      config.architecture == 'modular'
          ? '  lib/app/app_module.dart'
          : '  Injectable dependency graph (via build_runner)',
    )
    ..info('')
    ..success('$className is initialized before runApp.');

  if (config.architecture != 'modular' && !runBuildRunner) {
    logger.info(
      'Run `dart run build_runner build` before compiling the app.',
    );
  }
  return 0;
}

void _addDependency(Directory root, String driver) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw const FileSystemException('No pubspec.yaml at the project root.');
  }

  final editor = YamlEditor(pubspec.readAsStringSync());
  final dependency = switch (driver) {
    'shared_preferences' => ('shared_preferences', '^2.5.5'),
    'flutter_secure_storage' => ('flutter_secure_storage', '^10.3.1'),
    _ => throw ArgumentError.value(driver, 'driver'),
  };

  final dependencies = _tryParse(editor, ['dependencies']);
  if (dependencies is! YamlMap) {
    editor.update(['dependencies'], {dependency.$1: dependency.$2});
  } else if (!dependencies.containsKey(dependency.$1)) {
    editor.update(['dependencies', dependency.$1], dependency.$2);
  } else {
    final existing = dependencies[dependency.$1];
    if (existing is! String) {
      throw ArgumentError(
        'Existing ${dependency.$1} dependency uses a non-hosted source. '
        'Review and update it manually before generating this service.',
      );
    }
    final target = Version.parse(dependency.$2.substring(1));
    final constraint = VersionConstraint.parse(existing);
    if (!constraint.allows(target)) {
      throw ArgumentError(
        'Existing ${dependency.$1} constraint "$existing" does not allow the '
        'tested ${dependency.$2} baseline. Update and migrate the dependency '
        'before generating this service.',
      );
    }
  }
  pubspec.writeAsStringSync(editor.toString());
}

YamlNode? _tryParse(YamlEditor editor, List<Object> path) {
  try {
    return editor.parseAt(path);
  } on ArgumentError {
    return null;
  }
}

String _sharedPreferencesService({
  required String className,
  required String instanceName,
  required bool modular,
}) =>
    '''
${modular ? '' : "import 'package:injectable/injectable.dart';\n"}import 'package:shared_preferences/shared_preferences.dart';

/// Stores non-sensitive application preferences on the device.
///
/// Call [init] once during app startup so platform failures happen before UI.
${modular ? '' : '@lazySingleton\n'}class $className {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await _preferences.getKeys();
    _initialized = true;
  }

  Future<Object?> get(String key) async {
    _ensureInitialized();
    final values = await _preferences.getAll(allowList: {key});
    return values[key];
  }

  Future<String?> getString(String key) {
    _ensureInitialized();
    return _preferences.getString(key);
  }

  Future<bool?> getBool(String key) {
    _ensureInitialized();
    return _preferences.getBool(key);
  }

  Future<int?> getInt(String key) {
    _ensureInitialized();
    return _preferences.getInt(key);
  }

  Future<double?> getDouble(String key) {
    _ensureInitialized();
    return _preferences.getDouble(key);
  }

  Future<List<String>?> getStringList(String key) {
    _ensureInitialized();
    return _preferences.getStringList(key);
  }

  Future<void> setString(String key, String value) {
    _ensureInitialized();
    return _preferences.setString(key, value);
  }

  Future<void> setBool(String key, bool value) {
    _ensureInitialized();
    return _preferences.setBool(key, value);
  }

  Future<void> setInt(String key, int value) {
    _ensureInitialized();
    return _preferences.setInt(key, value);
  }

  Future<void> setDouble(String key, double value) {
    _ensureInitialized();
    return _preferences.setDouble(key, value);
  }

  Future<void> setStringList(String key, List<String> value) {
    _ensureInitialized();
    return _preferences.setStringList(key, value);
  }

  Future<bool> containsKey(String key) {
    _ensureInitialized();
    return _preferences.containsKey(key);
  }

  Future<Set<String>> getKeys() {
    _ensureInitialized();
    return _preferences.getKeys();
  }

  Future<void> remove(String key) {
    _ensureInitialized();
    return _preferences.remove(key);
  }

  Future<void> clear({Set<String>? allowList}) {
    _ensureInitialized();
    return _preferences.clear(allowList: allowList);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('$className.init() must be called before use.');
    }
  }
}
${modular ? '\nfinal $instanceName = $className();\n' : ''}''';

String _secureStorageService({
  required String className,
  required String instanceName,
  required bool modular,
}) =>
    '''
import 'dart:convert';

${modular ? '' : "import 'package:injectable/injectable.dart';\n"}import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores sensitive values using the platform's encrypted storage.
///
/// Call [init] once during app startup before reading or writing values.
${modular ? '' : '@lazySingleton\n'}class $className {
  $className() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    // Access the platform store once so initialization failures occur before
    // runApp rather than during the first user interaction.
    await _storage.readAll();
    _initialized = true;
  }

  Future<void> setString(String key, String value) {
    _ensureInitialized();
    return _storage.write(key: key, value: value);
  }

  Future<String?> getString(String key) {
    _ensureInitialized();
    return _storage.read(key: key);
  }

  Future<void> setBool(String key, bool value) {
    return setString(key, value.toString());
  }

  Future<bool?> getBool(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }

  Future<void> setInt(String key, int value) {
    return setString(key, value.toString());
  }

  Future<int?> getInt(String key) async {
    return int.tryParse(await getString(key) ?? '');
  }

  Future<void> setDouble(String key, double value) {
    return setString(key, value.toString());
  }

  Future<double?> getDouble(String key) async {
    return double.tryParse(await getString(key) ?? '');
  }

  Future<void> setStringList(String key, List<String> value) {
    return setString(key, jsonEncode(value));
  }

  Future<List<String>?> getStringList(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return decoded.whereType<String>().toList(growable: false);
    } on FormatException {
      return null;
    }
  }

  Future<bool> containsKey(String key) {
    _ensureInitialized();
    return _storage.containsKey(key: key);
  }

  Future<Map<String, String>> readAll() {
    _ensureInitialized();
    return _storage.readAll();
  }

  Future<void> remove(String key) {
    _ensureInitialized();
    return _storage.delete(key: key);
  }

  Future<void> clear() {
    _ensureInitialized();
    return _storage.deleteAll();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('$className.init() must be called before use.');
    }
  }
}
${modular ? '\nfinal $instanceName = $className();\n' : ''}''';
