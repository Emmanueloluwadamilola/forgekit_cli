import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const forgeKitConfigFileName = 'forgekit.yaml';

const creatableArchitectureProfiles = ['clean', 'mvvm', 'modular'];
const supportedProfiles = ['lean', ...creatableArchitectureProfiles, 'legacy'];
const supportedStateManagement = ['provider', 'riverpod', 'bloc', 'cubit'];
const supportedRouters = ['named', 'go_router', 'modular'];
const supportedDependencyInjection = [
  'injectable',
  'flutter_modular',
];
const supportedModels = ['json_serializable'];
const supportedApiClients = ['retrofit'];

const _recognizedDependencyInjection = [
  ...supportedDependencyInjection,
  'get_it',
  'riverpod',
];
const _recognizedModels = [...supportedModels, 'freezed'];
const _recognizedApiClients = [...supportedApiClients, 'dio', 'http'];

List<String> stateManagementMasonFlags(String stateManagement) => [
      '--useProvider',
      '${stateManagement == 'provider'}',
      '--useRiverpod',
      '${stateManagement == 'riverpod'}',
      '--useBloc',
      '${stateManagement == 'bloc'}',
      '--useCubit',
      '${stateManagement == 'cubit'}',
    ];

class ForgeKitConfig {
  const ForgeKitConfig({
    this.version = 1,
    this.architecture = 'clean',
    this.stateManagement = 'provider',
    this.router = 'named',
    this.dependencyInjection = 'injectable',
    this.models = 'json_serializable',
    this.apiClient = 'retrofit',
    this.minimumCoverage = 80,
    this.format = true,
    this.runBuildRunner = true,
  });

  factory ForgeKitConfig.fromYaml(String source) {
    final Object? document;
    try {
      document = loadYaml(source);
    } on YamlException catch (error) {
      throw ConfigException('Invalid forgekit.yaml: ${error.message}');
    }
    if (document is! YamlMap) {
      throw const ConfigException('forgekit.yaml must contain a YAML map.');
    }

    final testing = document['testing'];
    final generation = document['generation'];
    final config = ForgeKitConfig(
      version: _integer(document, 'version', 1),
      architecture: _string(document, 'architecture', 'clean'),
      stateManagement: _normalizeStateManagement(
        _string(document, 'state_management', 'provider'),
      ),
      router: _string(document, 'router', 'named'),
      dependencyInjection:
          _string(document, 'dependency_injection', 'injectable'),
      models: _string(document, 'models', 'json_serializable'),
      apiClient: _string(document, 'api_client', 'retrofit'),
      minimumCoverage:
          testing is YamlMap ? _integer(testing, 'coverage', 80) : 80,
      format:
          generation is YamlMap ? _boolean(generation, 'format', true) : true,
      runBuildRunner: generation is YamlMap
          ? _boolean(generation, 'build_runner', true)
          : true,
    );
    config.validate();
    return config;
  }

  final int version;
  final String architecture;
  final String stateManagement;
  final String router;
  final String dependencyInjection;
  final String models;
  final String apiClient;
  final int minimumCoverage;
  final bool format;
  final bool runBuildRunner;

  ForgeKitConfig copyWith({
    int? version,
    String? architecture,
    String? stateManagement,
    String? router,
    String? dependencyInjection,
    String? models,
    String? apiClient,
    int? minimumCoverage,
    bool? format,
    bool? runBuildRunner,
  }) {
    return ForgeKitConfig(
      version: version ?? this.version,
      architecture: architecture ?? this.architecture,
      stateManagement: stateManagement ?? this.stateManagement,
      router: router ?? this.router,
      dependencyInjection: dependencyInjection ?? this.dependencyInjection,
      models: models ?? this.models,
      apiClient: apiClient ?? this.apiClient,
      minimumCoverage: minimumCoverage ?? this.minimumCoverage,
      format: format ?? this.format,
      runBuildRunner: runBuildRunner ?? this.runBuildRunner,
    );
  }

  ForgeKitConfig setValue(String key, String value) {
    final normalizedKey = key.trim().replaceAll('-', '_');
    final normalizedValue = value.trim().toLowerCase();
    final updated = switch (normalizedKey) {
      'architecture' => copyWith(architecture: normalizedValue),
      'state_management' => copyWith(
          stateManagement: _normalizeStateManagement(normalizedValue),
        ),
      'router' => copyWith(router: normalizedValue),
      'dependency_injection' => copyWith(dependencyInjection: normalizedValue),
      'models' => copyWith(models: normalizedValue),
      'api_client' => copyWith(apiClient: normalizedValue),
      'testing.coverage' ||
      'coverage' =>
        copyWith(minimumCoverage: _parseInteger(key, value)),
      'generation.format' ||
      'format' =>
        copyWith(format: _parseBoolean(key, value)),
      'generation.build_runner' ||
      'build_runner' =>
        copyWith(runBuildRunner: _parseBoolean(key, value)),
      _ => throw ConfigException(
          'Unknown Flutter ForgeKit CLI configuration key: $key',
        ),
    };
    updated.validate();
    return updated;
  }

  void validate() {
    if (version != 1) {
      throw ConfigException(
        'Unsupported forgekit.yaml version $version. Expected version 1.',
      );
    }
    _validateChoice('architecture', architecture, supportedProfiles);
    _validateChoice(
      'state_management',
      stateManagement,
      supportedStateManagement,
    );
    _validateChoice('router', router, supportedRouters);
    _validateGenerationBackend(
      'dependency_injection',
      dependencyInjection,
      supportedDependencyInjection,
      _recognizedDependencyInjection,
    );
    _validateGenerationBackend(
      'models',
      models,
      supportedModels,
      _recognizedModels,
    );
    _validateGenerationBackend(
      'api_client',
      apiClient,
      supportedApiClients,
      _recognizedApiClients,
    );
    final expectedDependencyInjection =
        architecture == 'modular' ? 'flutter_modular' : 'injectable';
    if (dependencyInjection != expectedDependencyInjection) {
      throw ConfigException(
        'architecture "$architecture" requires dependency_injection '
        '"$expectedDependencyInjection" in forgekit.yaml version 1. '
        'Received "$dependencyInjection".',
      );
    }
    final expectedRouter = architecture == 'modular' ? 'modular' : null;
    if (expectedRouter != null && router != expectedRouter) {
      throw ConfigException(
        'architecture "modular" requires router "modular". '
        'Received "$router".',
      );
    }
    if (architecture != 'modular' && router == 'modular') {
      throw ConfigException(
        'router "modular" requires architecture "modular". '
        'Received architecture "$architecture".',
      );
    }
    if (minimumCoverage < 0 || minimumCoverage > 100) {
      throw const ConfigException(
        'testing.coverage must be between 0 and 100.',
      );
    }
  }

  String toYaml() => '''
version: $version

architecture: $architecture
state_management: $stateManagement
router: $router
dependency_injection: $dependencyInjection
models: $models
api_client: $apiClient

testing:
  coverage: $minimumCoverage

generation:
  format: $format
  build_runner: $runBuildRunner
'''
      .trimLeft();
}

class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

ForgeKitConfig loadForgeKitConfig({
  required Directory root,
  bool allowMissing = true,
}) {
  final file = File(p.join(root.path, forgeKitConfigFileName));
  if (!file.existsSync()) {
    if (allowMissing) return const ForgeKitConfig();
    throw const ConfigException(
      'No forgekit.yaml found. Run "forgekit init" first.',
    );
  }
  return ForgeKitConfig.fromYaml(file.readAsStringSync());
}

Future<void> saveForgeKitConfig({
  required Directory root,
  required ForgeKitConfig config,
}) async {
  config.validate();
  final file = File(p.join(root.path, forgeKitConfigFileName));
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(config.toYaml(), flush: true);
  await _replaceFile(temporary, file);
}

Future<void> _replaceFile(File temporary, File destination) async {
  if (!destination.existsSync() || !Platform.isWindows) {
    await temporary.rename(destination.path);
    return;
  }
  final backup = File('${destination.path}.forgekit-backup');
  if (backup.existsSync()) await backup.delete();
  await destination.rename(backup.path);
  try {
    await temporary.rename(destination.path);
    await backup.delete();
  } catch (_) {
    if (!destination.existsSync() && backup.existsSync()) {
      await backup.rename(destination.path);
    }
    rethrow;
  }
}

ForgeKitConfig detectForgeKitConfig({
  required Directory root,
  String? architecture,
  String? stateManagement,
}) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw const ConfigException('No pubspec.yaml found at the project root.');
  }

  final Object? document;
  try {
    document = loadYaml(pubspec.readAsStringSync());
  } on YamlException catch (error) {
    throw ConfigException('Invalid pubspec.yaml: ${error.message}');
  }
  if (document is! YamlMap) {
    throw const ConfigException('pubspec.yaml must contain a YAML map.');
  }

  final dependencies = document['dependencies'];
  final devDependencies = document['dev_dependencies'];
  final dependencyNames = <String>{
    if (dependencies is YamlMap) ...dependencies.keys.whereType<String>(),
    if (devDependencies is YamlMap) ...devDependencies.keys.whereType<String>(),
  };

  final detectedState =
      stateManagement ?? _detectStateManagement(root, dependencyNames);
  final detectedArchitecture = architecture ??
      (dependencyNames.contains('flutter_modular')
          ? 'modular'
          : _hasMvvmArchitecture(root)
              ? 'mvvm'
              : _hasCleanArchitecture(root)
                  ? 'clean'
                  : 'lean');
  final router = detectedArchitecture == 'modular'
      ? 'modular'
      : dependencyNames.contains('go_router')
          ? 'go_router'
          : 'named';
  final dependencyInjection =
      detectedArchitecture == 'modular' ? 'flutter_modular' : 'injectable';

  final config = ForgeKitConfig(
    architecture: detectedArchitecture,
    stateManagement: detectedState,
    router: router,
    dependencyInjection: dependencyInjection,
  );
  config.validate();
  return config;
}

bool _hasMvvmArchitecture(Directory root) {
  return Directory(p.join(root.path, 'lib', 'ui')).existsSync() &&
      Directory(p.join(root.path, 'lib', 'data')).existsSync();
}

String _detectStateManagement(Directory root, Set<String> dependencies) {
  if (dependencies.contains('flutter_riverpod') ||
      dependencies.contains('riverpod')) {
    return 'riverpod';
  }
  if (dependencies.contains('flutter_bloc')) {
    final lib = Directory(p.join(root.path, 'lib'));
    if (lib.existsSync()) {
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (source.contains('extends Bloc<')) return 'bloc';
      }
    }
    return 'cubit';
  }
  return 'provider';
}

bool _hasCleanArchitecture(Directory root) {
  final features = Directory(p.join(root.path, 'lib', 'features'));
  if (!features.existsSync()) return false;
  for (final feature in features.listSync().whereType<Directory>()) {
    final layers = ['data', 'domain', 'presentation'];
    if (layers.every(
      (layer) => Directory(p.join(feature.path, layer)).existsSync(),
    )) {
      return true;
    }
  }
  return false;
}

String _string(YamlMap map, String key, String fallback) {
  final value = map[key];
  if (value == null) return fallback;
  if (value is! String || value.trim().isEmpty) {
    throw ConfigException('$key must be a non-empty string.');
  }
  return value.trim().toLowerCase();
}

int _integer(YamlMap map, String key, int fallback) {
  final value = map[key];
  if (value == null) return fallback;
  if (value is! int) throw ConfigException('$key must be an integer.');
  return value;
}

bool _boolean(YamlMap map, String key, bool fallback) {
  final value = map[key];
  if (value == null) return fallback;
  if (value is! bool) throw ConfigException('$key must be true or false.');
  return value;
}

int _parseInteger(String key, String value) {
  final parsed = int.tryParse(value);
  if (parsed == null) throw ConfigException('$key must be an integer.');
  return parsed;
}

bool _parseBoolean(String key, String value) {
  return switch (value.trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => throw ConfigException('$key must be true or false.'),
  };
}

void _validateChoice(String key, String value, List<String> choices) {
  if (!choices.contains(value)) {
    throw ConfigException(
      '$key must be one of: ${choices.join(', ')}. Received "$value".',
    );
  }
}

void _validateGenerationBackend(
  String key,
  String value,
  List<String> supported,
  List<String> recognized,
) {
  if (supported.contains(value)) return;
  if (recognized.contains(value)) {
    throw ConfigException(
      '$key "$value" is recognized but is not supported for generation in '
      'forgekit.yaml version 1. Supported: ${supported.join(', ')}. ForgeKit '
      'refuses this configuration instead of emitting a mixed technology stack.',
    );
  }
  throw ConfigException(
    '$key must be one of the supported generation backends: '
    '${supported.join(', ')}. Received "$value".',
  );
}

String _normalizeStateManagement(String value) {
  // Flutter ForgeKit CLI originally exposed Provider as "forgekit".
  // Keep existing project configuration readable after the public rename.
  return value == 'forgekit' ? 'provider' : value;
}
