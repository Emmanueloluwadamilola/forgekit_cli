import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'env_service.dart';
import 'json_to_dart.dart';
import 'mason_environment.dart';
import 'utils.dart';

/// Checks that a project conforms to the Flutter ForgeKit CLI standard.
///
/// Missing required files are reported as errors; naming / annotation drift as
/// warnings. Exit code: non-zero when there are errors, or (with [ci]) any
/// issue at all.
Future<int> runDoctor({
  required Logger logger,
  required Directory root,
  bool ci = false,
  bool fix = false,
}) async {
  final projectName = detectProjectName(root: root);
  final config = loadForgeKitConfig(root: root);
  logger.info('Flutter ForgeKit CLI doctor: checking "$projectName"');
  logger.info('');

  if (fix) {
    final fixed = await _applyFixes(
      root: root,
      logger: logger,
      stateManagement: config.stateManagement,
      architecture: config.architecture,
    );
    if (fixed > 0) {
      logger.info('');
      logger.info('Rechecking after fixes...');
      logger.info('');
    }
  }

  final issues = <_Issue>[];

  switch (config.architecture) {
    case 'mvvm':
      _checkMvvmProject(root, issues, config.stateManagement);
    case 'modular':
      _checkModularProject(root, issues);
    case 'clean':
      _checkCleanProject(root, issues, config.stateManagement);
    default:
      _checkAdoptionOnlyProject(root, issues, config.architecture);
  }
  _checkBundledEnvironmentKeys(root, issues);
  _checkBrickRegistration(issues);
  await _checkToolchain(issues);

  // --- report ---
  final errors = issues.where((i) => i.isError).toList();
  final warns = issues.where((i) => !i.isError).toList();

  for (final i in errors) {
    logger.err('  ✗ ${i.message}');
  }
  for (final i in warns) {
    logger.warn('  • ${i.message}');
  }

  logger.info('');
  if (issues.isEmpty) {
    logger.success('All checks passed — project conforms to the standard.');
    return 0;
  }
  logger.info('${errors.length} error(s), ${warns.length} warning(s).');

  if (ci) return issues.isEmpty ? 0 : 1;
  return errors.isEmpty ? 0 : 1;
}

/// Reports bundled bricks that Mason does not know about, i.e. an installation
/// where `forgekit setup` has not completed for this release.
///
/// Without this the failure only surfaces later, as a bare "Failed to add
/// feature" from whichever generation command the user tried first.
///
/// Deliberately a warning rather than an error: doctor's errors mean "this
/// project does not conform to the architecture standard", and an unregistered
/// brick is a problem with the local installation, not with the project. Raising
/// it to an error would make `doctor` fail on a perfectly well-formed project
/// just because the machine running it had not been set up. `--ci` still fails
/// on warnings, so a pipeline that needs generation to work is covered.
void _checkBrickRegistration(List<_Issue> issues) {
  final missing = unregisteredForgekitBricks();
  if (missing.isEmpty) return;

  issues.add(
    _Issue.warn(
      'Mason has no registration for ${missing.length} bundled brick(s): '
      '${missing.join(', ')}. Code generation will fail until you run: '
      'forgekit setup',
    ),
  );
}

/// Reports a toolchain that is too old to build a generated project.
///
/// Warnings for the same reason as [_checkBrickRegistration]: the toolchain is
/// an environment property, not a property of the project being checked.
Future<void> _checkToolchain(List<_Issue> issues) async {
  final toolchain = await readFlutterToolchain();
  if (toolchain == null) {
    issues.add(
      _Issue.warn(
        'Could not read the Flutter toolchain version. Verify that Flutter is '
        'installed and on your PATH.',
      ),
    );
    return;
  }

  if (toolchain.dartSdkVersion < minimumGeneratedProjectDartSdk) {
    issues.add(
      _Issue.warn(
        'Flutter ${toolchain.flutterVersion} bundles Dart '
        '${toolchain.dartSdkVersion}, below the Dart '
        '$minimumGeneratedProjectDartSdk a generated ForgeKit project '
        'requires. Run: flutter upgrade',
      ),
    );
  }
}

void _checkBundledEnvironmentKeys(Directory root, List<_Issue> issues) {
  final findings = findPotentiallySensitiveBundledEnvironmentKeys(root);
  for (final entry in findings.entries) {
    issues.add(
      _Issue.warn(
        '${entry.key} contains secret-like bundled key(s): '
        '${entry.value.join(', ')}. Verify they are intentionally public and '
        'provider-restricted, or move them to runtime/server-side secret '
        'management.',
      ),
    );
  }
}

Future<int> _applyFixes({
  required Directory root,
  required Logger logger,
  required String stateManagement,
  required String architecture,
}) async {
  if (architecture != 'clean') {
    logger.info(
      'No safe automatic repairs are available for the $architecture profile.',
    );
    return 0;
  }
  final projectName = detectProjectName(root: root);
  var fixed = 0;

  final files = <String, String>{
    'lib/core/di/core_module.dart': _coreModuleTemplate(),
    'lib/core/di/core_module_container.dart': _coreModuleContainerTemplate(),
    'lib/core/domain/api/api_result.dart': _apiResultTemplate(),
    'lib/core/domain/usecase/use_case.dart': _useCaseTemplate(),
    if (stateManagement == 'provider') ...{
      'lib/core/presentation/manager/custom_provider.dart':
          _customProviderTemplate(),
      'lib/core/presentation/manager/custom_state.dart': _customStateTemplate(),
    },
  };

  for (final entry in files.entries) {
    final file = File(p.join(root.path, entry.key));
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      logger.success('Created ${entry.key}');
      fixed++;
    }
  }

  final featuresDir = Directory(p.join(root.path, 'lib', 'features'));
  if (!featuresDir.existsSync()) {
    featuresDir.createSync(recursive: true);
    logger.success('Created lib/features/');
    fixed++;
    return fixed;
  }

  final featureDirs = featuresDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final fd in featureDirs) {
    fixed += _fixFeature(
      featureDir: fd,
      projectName: projectName,
      logger: logger,
      stateManagement: stateManagement,
    );
  }

  if (fixed == 0) {
    logger.info('No safe fixes were needed.');
  }
  return fixed;
}

void _checkAdoptionOnlyProject(
  Directory root,
  List<_Issue> issues,
  String architecture,
) {
  _checkFiles(root, issues, ['lib/main.dart']);
  issues.add(
    _Issue.error(
      'The "$architecture" profile is detection-only in ForgeKit 0.1.0. '
      'Architecture generation and automatic repair require a Clean, MVVM, or '
      'Modular project.',
    ),
  );
}

void _checkCleanProject(
  Directory root,
  List<_Issue> issues,
  String stateManagement,
) {
  final coreFiles = <String>[
    'lib/core/di/core_module_container.dart',
    'lib/core/domain/api/api_result.dart',
    'lib/core/domain/usecase/use_case.dart',
    if (stateManagement == 'provider') ...[
      'lib/core/presentation/manager/custom_provider.dart',
      'lib/core/presentation/manager/custom_state.dart',
    ],
  ];
  _checkFiles(root, issues, coreFiles);

  final featuresDir = Directory(p.join(root.path, 'lib', 'features'));
  if (!featuresDir.existsSync()) {
    issues.add(_Issue.warn('No lib/features directory yet.'));
    return;
  }
  for (final directory in _sortedDirectories(featuresDir)) {
    _checkFeature(directory, issues, stateManagement);
  }
}

void _checkMvvmProject(
  Directory root,
  List<_Issue> issues,
  String stateManagement,
) {
  _checkFiles(root, issues, [
    'lib/config/di/dependencies.dart',
    'lib/utils/result.dart',
    'lib/ui/core/app/app.dart',
    'lib/ui/core/view_models/view_state.dart',
    if (stateManagement == 'provider')
      'lib/ui/core/view_models/custom_provider.dart',
  ]);

  final ui = Directory(p.join(root.path, 'lib', 'ui'));
  if (!ui.existsSync()) {
    issues.add(_Issue.error('Missing MVVM UI directory: lib/ui'));
    return;
  }
  final features = _sortedDirectories(ui)
      .where((directory) => p.basename(directory.path) != 'core')
      .toList();
  if (features.isEmpty) {
    issues.add(_Issue.warn('No MVVM features in lib/ui yet.'));
    return;
  }

  for (final directory in features) {
    final feature = p.basename(directory.path);
    final pascal = pascalCase(feature);
    _checkDeclarations(root, issues, feature, {
      'lib/ui/$feature/view_models/${feature}_view_model.dart':
          'class ${pascal}ViewModel',
      'lib/ui/$feature/view_models/${feature}_state.dart':
          'class ${pascal}State',
      'lib/ui/$feature/widgets/${feature}_screen.dart': 'class ${pascal}Screen',
      'lib/data/services/${feature}_api_service.dart':
          'class ${pascal}ApiService',
      'lib/data/repositories/${feature}_repository.dart':
          'class ${pascal}Repository',
      'lib/config/di/${feature}_module.dart': 'class ${pascal}Module',
    });
  }
}

void _checkModularProject(Directory root, List<_Issue> issues) {
  _checkFiles(root, issues, [
    'lib/app/app.dart',
    'lib/app/app_module.dart',
    'lib/core/state/view_state.dart',
  ]);

  final modules = Directory(p.join(root.path, 'lib', 'modules'));
  if (!modules.existsSync()) {
    issues.add(_Issue.warn('No modules in lib/modules yet.'));
    return;
  }
  final appModule = File(p.join(root.path, 'lib', 'app', 'app_module.dart'));
  final appModuleContent =
      appModule.existsSync() ? appModule.readAsStringSync() : '';
  for (final directory in _sortedDirectories(modules)) {
    final feature = p.basename(directory.path);
    final pascal = pascalCase(feature);
    final camel = camelCase(feature);
    _checkDeclarations(root, issues, feature, {
      'lib/modules/$feature/${feature}_module.dart': 'final ${camel}Module',
      'lib/modules/$feature/data/${feature}_api_service.dart':
          'class ${pascal}ApiService',
      'lib/modules/$feature/data/${feature}_repository.dart':
          'class ${pascal}Repository',
      'lib/modules/$feature/presentation/${feature}_controller.dart':
          'class ${pascal}Controller',
      'lib/modules/$feature/presentation/${feature}_state.dart':
          'class ${pascal}State',
      'lib/modules/$feature/presentation/${feature}_page.dart':
          'class ${pascal}Page',
    });
    if (!appModuleContent.contains('..module(${camel}Module)')) {
      issues.add(
        _Issue.error('[$feature] module is not mounted in app_module.dart'),
      );
    }
  }
}

void _checkFiles(
  Directory root,
  List<_Issue> issues,
  Iterable<String> files,
) {
  for (final relative in files) {
    if (!File(p.join(root.path, relative)).existsSync()) {
      issues.add(_Issue.error('Missing core file: $relative'));
    }
  }
}

void _checkDeclarations(
  Directory root,
  List<_Issue> issues,
  String feature,
  Map<String, String> expected,
) {
  expected.forEach((relative, declaration) {
    final file = File(p.join(root.path, relative));
    if (!file.existsSync()) {
      issues.add(_Issue.error('[$feature] missing $relative'));
    } else if (!file.readAsStringSync().contains(declaration)) {
      issues.add(
        _Issue.warn('[$feature] $relative should declare `$declaration`'),
      );
    }
  });
}

List<Directory> _sortedDirectories(Directory parent) {
  return parent.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

int _fixFeature({
  required Directory featureDir,
  required String projectName,
  required Logger logger,
  required String stateManagement,
}) {
  final f = p.basename(featureDir.path);
  final pascal = pascalCase(f);
  final camel = camelCase(f);
  final files = <String, String>{
    'data/remote/service/${f}_api_service.dart': _apiServiceTemplate(
      featureSnake: f,
      featurePascal: pascal,
    ),
    'data/repository/${f}_repository_impl.dart': _repositoryImplTemplate(
      projectName: projectName,
      featureSnake: f,
      featurePascal: pascal,
    ),
    'domain/repository/${f}_repository.dart': _repositoryTemplate(
      featureSnake: f,
      featurePascal: pascal,
    ),
    'presentation/manager/${f}_provider.dart': _providerTemplate(
      projectName: projectName,
      featureSnake: f,
      featurePascal: pascal,
      featureCamel: camel,
      stateManagement: stateManagement,
    ),
    'presentation/manager/${f}_state.dart': _stateTemplate(
      projectName: projectName,
      featurePascal: pascal,
      stateManagement: stateManagement,
    ),
    'di/${f}_module.dart': _moduleTemplate(
      projectName: projectName,
      featureSnake: f,
      featurePascal: pascal,
      featureCamel: camel,
    ),
  };

  var fixed = 0;
  for (final entry in files.entries) {
    final file = File(p.join(featureDir.path, entry.key));
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      logger.success('Created lib/features/$f/${entry.key}');
      fixed++;
    }
  }
  return fixed;
}

void _checkFeature(
  Directory featureDir,
  List<_Issue> issues,
  String stateManagement,
) {
  final f = p.basename(featureDir.path);
  final pascal = pascalCase(f);
  final managerDeclaration = switch (stateManagement) {
    'riverpod' => 'class ${pascal}Notifier',
    'bloc' => 'class ${pascal}Bloc',
    'cubit' => 'class ${pascal}Cubit',
    _ => 'class ${pascal}Provider',
  };

  // Required files (bare feature shape).
  final required = <String, String>{
    'data/remote/service/${f}_api_service.dart': 'class ${pascal}ApiService',
    'data/repository/${f}_repository_impl.dart':
        'class ${pascal}RepositoryImpl',
    'domain/repository/${f}_repository.dart': 'class ${pascal}Repository',
    'presentation/manager/${f}_provider.dart': managerDeclaration,
    'presentation/manager/${f}_state.dart': 'class ${pascal}State',
    'di/${f}_module.dart': 'class ${pascal}Module',
  };

  required.forEach((rel, expectedDecl) {
    final file = File(p.join(featureDir.path, rel));
    if (!file.existsSync()) {
      issues.add(_Issue.error('[$f] missing $rel'));
      return;
    }
    final content = file.readAsStringSync();
    if (!content.contains(expectedDecl)) {
      issues.add(_Issue.warn('[$f] $rel should declare `$expectedDecl`'));
    }
  });

  // Riverpod owns construction through its provider declaration. The other
  // managers use get_it and must remain injectable.
  final manager = File(
    p.join(featureDir.path, 'presentation', 'manager', '${f}_provider.dart'),
  );
  if (stateManagement != 'riverpod' &&
      manager.existsSync() &&
      !manager.readAsStringSync().contains('@injectable')) {
    issues.add(_Issue.warn('[$f] manager is not annotated @injectable'));
  }
}

class _Issue {
  _Issue.error(this.message) : isError = true;
  _Issue.warn(this.message) : isError = false;

  final String message;
  final bool isError;
}

String _coreModuleTemplate() => '''
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@module
abstract class CoreModule {
  @lazySingleton
  Dio dio() => Dio();
}
''';

String _coreModuleContainerTemplate() => '''
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async {}
''';

String _apiResultTemplate() => '''
sealed class ApiResult<T> {
  const ApiResult();
}

class Success<T> extends ApiResult<T> {
  const Success(this.data);

  final T data;
}

class Failure<T> extends ApiResult<T> {
  const Failure(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}
''';

String _useCaseTemplate() => '''
abstract class UseCase<Output, Params> {
  Future<Output> call(Params params);
}

class NoParams {
  const NoParams();
}
''';

String _customProviderTemplate() => '''
import 'package:flutter/material.dart';

class CustomProvider extends ChangeNotifier {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
''';

String _customStateTemplate() => '''
enum ViewStatus { idle, loading, success, error }

class CustomState {
  const CustomState({
    this.status = ViewStatus.idle,
    this.errorMessage,
  });

  final ViewStatus status;
  final String? errorMessage;

  bool get isLoading => status == ViewStatus.loading;
  bool get hasError => status == ViewStatus.error;
}
''';

String _apiServiceTemplate({
  required String featureSnake,
  required String featurePascal,
}) =>
    '''
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

part '${featureSnake}_api_service.g.dart';

@RestApi()
abstract class ${featurePascal}ApiService {
  factory ${featurePascal}ApiService(Dio dio, {String baseUrl}) =
      _${featurePascal}ApiService;
}
''';

String _repositoryImplTemplate({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
}) =>
    '''
import 'package:injectable/injectable.dart';

import 'package:$projectName/features/$featureSnake/data/remote/service/${featureSnake}_api_service.dart';
import 'package:$projectName/features/$featureSnake/domain/repository/${featureSnake}_repository.dart';

@LazySingleton(as: ${featurePascal}Repository)
class ${featurePascal}RepositoryImpl implements ${featurePascal}Repository {
  ${featurePascal}RepositoryImpl(this._apiService);

  // ignore: unused_field
  final ${featurePascal}ApiService _apiService;
}
''';

String _repositoryTemplate({
  required String featureSnake,
  required String featurePascal,
}) =>
    '''
/// Abstract repository contract for the $featurePascal feature.
///
/// Methods are added by: `forgekit add function $featureSnake <name>`
abstract class ${featurePascal}Repository {}
''';

String _providerTemplate({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String featureCamel,
  required String stateManagement,
}) {
  if (stateManagement == 'riverpod') {
    return '''
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart';

final ${featureCamel}Provider = NotifierProvider<${featurePascal}Notifier, ${featurePascal}State>(
  ${featurePascal}Notifier.new,
);

class ${featurePascal}Notifier extends Notifier<${featurePascal}State> {
  @override
  ${featurePascal}State build() => const ${featurePascal}State();
}
''';
  }
  if (stateManagement == 'bloc') {
    return '''
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart';

sealed class ${featurePascal}Event {
  const ${featurePascal}Event();
}

// forgekit:event-classes

@injectable
class ${featurePascal}Bloc extends Bloc<${featurePascal}Event, ${featurePascal}State> {
  ${featurePascal}Bloc() : super(const ${featurePascal}State()) {
    // forgekit:event-registrations
  }
}
''';
  }
  if (stateManagement == 'cubit') {
    return '''
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart';

@injectable
class ${featurePascal}Cubit extends Cubit<${featurePascal}State> {
  ${featurePascal}Cubit() : super(const ${featurePascal}State());
}
''';
  }
  return '''
import 'package:injectable/injectable.dart';

import 'package:$projectName/core/presentation/manager/custom_provider.dart';
import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart';

@injectable
class ${featurePascal}Provider extends CustomProvider {
  ${featurePascal}State _state = const ${featurePascal}State();
  ${featurePascal}State get state => _state;
}
''';
}

String _stateTemplate({
  required String projectName,
  required String featurePascal,
  required String stateManagement,
}) {
  if (stateManagement != 'provider') {
    return '''
enum ${featurePascal}Status { idle, loading, success, error }

class ${featurePascal}State {
  const ${featurePascal}State({
    this.status = ${featurePascal}Status.idle,
    this.errorMessage,
  });

  final ${featurePascal}Status status;
  final String? errorMessage;

  bool get isLoading => status == ${featurePascal}Status.loading;
  bool get hasError => status == ${featurePascal}Status.error;

  ${featurePascal}State copyWith({
    ${featurePascal}Status? status,
    String? errorMessage,
  }) {
    return ${featurePascal}State(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
''';
  }
  return '''
import 'package:$projectName/core/presentation/manager/custom_state.dart';

class ${featurePascal}State extends CustomState {
  const ${featurePascal}State({
    super.status,
    super.errorMessage,
  });

  ${featurePascal}State copyWith({
    ViewStatus? status,
    String? errorMessage,
  }) {
    return ${featurePascal}State(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
''';
}

String _moduleTemplate({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String featureCamel,
}) =>
    '''
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'package:$projectName/features/$featureSnake/data/remote/service/${featureSnake}_api_service.dart';

@module
abstract class ${featurePascal}Module {
  @lazySingleton
  ${featurePascal}ApiService ${featureCamel}ApiService(Dio dio) =>
      ${featurePascal}ApiService(dio);
}
''';
