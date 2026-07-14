import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'utils.dart';

/// Checks that a project conforms to the ForgeKit Architecture Standard.
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
  logger.info('Forge doctor — checking "$projectName"');
  logger.info('');

  if (fix) {
    final fixed = await _applyFixes(
      root: root,
      logger: logger,
      stateManagement: config.stateManagement,
    );
    if (fixed > 0) {
      logger.info('');
      logger.info('Rechecking after fixes...');
      logger.info('');
    }
  }

  final issues = <_Issue>[];

  // --- core scaffolding ---
  final coreFiles = <String>[
    'lib/core/di/core_module_container.dart',
    'lib/core/domain/api/api_result.dart',
    'lib/core/domain/usecase/use_case.dart',
    if (config.stateManagement == 'provider') ...[
      'lib/core/presentation/manager/custom_provider.dart',
      'lib/core/presentation/manager/custom_state.dart',
    ],
  ];
  for (final rel in coreFiles) {
    if (!File(p.join(root.path, rel)).existsSync()) {
      issues.add(_Issue.error('Missing core file: $rel'));
    }
  }

  // --- features ---
  final featuresDir = Directory(p.join(root.path, 'lib', 'features'));
  if (!featuresDir.existsSync()) {
    issues.add(_Issue.warn('No lib/features directory yet.'));
  } else {
    final featureDirs = featuresDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final fd in featureDirs) {
      _checkFeature(fd, issues, config.stateManagement);
    }
  }

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

Future<int> _applyFixes({
  required Directory root,
  required Logger logger,
  required String stateManagement,
}) async {
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
abstract class UseCase<Type, Params> {
  Future<Type> call(Params params);
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
