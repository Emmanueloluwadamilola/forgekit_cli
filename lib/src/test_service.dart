import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'utils.dart';

Future<int> addFeatureTests({
  required String feature,
  required Logger logger,
  required Directory root,
  bool force = false,
  String? stateManagement,
}) async {
  final config = loadForgeKitConfig(root: root);
  final selectedStateManagement = stateManagement ?? config.stateManagement;
  final architecture = config.architecture;
  final projectName = detectProjectName(root: root);
  final featureSnake = snakeCase(feature);
  final featurePascal = pascalCase(featureSnake);
  final testPath = switch (architecture) {
    'mvvm' => ['ui', featureSnake, 'view_models'],
    'modular' => ['modules', featureSnake, 'presentation'],
    _ => ['features', featureSnake, 'presentation', 'manager'],
  };
  final testDir = Directory(
    p.joinAll([root.path, 'test', ...testPath]),
  );

  final managerFile = switch (architecture) {
    'mvvm' => '${featureSnake}_view_model_test.dart',
    'modular' => '${featureSnake}_controller_test.dart',
    _ => '${featureSnake}_provider_test.dart',
  };

  final files = <String, String>{
    '${featureSnake}_state_test.dart': _featureStateTest(
      projectName: projectName,
      featureSnake: featureSnake,
      featurePascal: featurePascal,
      stateManagement: selectedStateManagement,
      architecture: architecture,
    ),
    managerFile: _featureProviderTest(
      projectName: projectName,
      featureSnake: featureSnake,
      featurePascal: featurePascal,
      stateManagement: selectedStateManagement,
      architecture: architecture,
    ),
  };

  return _writeTestFiles(
    logger: logger,
    directory: testDir,
    files: files,
    force: force,
    label: 'feature "$featureSnake"',
  );
}

Future<int> addModelTest({
  required String name,
  required Logger logger,
  required Directory root,
  String? feature,
  bool force = false,
}) async {
  final projectName = detectProjectName(root: root);
  final modelSnake = snakeCase(name);
  final modelPascal = pascalCase(modelSnake);
  final featureSnake = feature == null ? null : snakeCase(feature);
  final modelImport = featureSnake == null
      ? 'package:$projectName/core/domain/entity/model/$modelSnake.dart'
      : 'package:$projectName/features/$featureSnake/domain/entity/model/$modelSnake.dart';
  final testPathParts = [
    root.path,
    'test',
    if (featureSnake == null) ...['core'] else ...['features', featureSnake],
    'domain',
    'entity',
    'model',
  ];
  final testDir = Directory(
    p.joinAll(testPathParts),
  );

  return _writeTestFiles(
    logger: logger,
    directory: testDir,
    files: {
      '${modelSnake}_test.dart': _modelTest(
        modelImport: modelImport,
        modelPascal: modelPascal,
      ),
    },
    force: force,
    label: 'model "$modelSnake"',
  );
}

Future<int> addFunctionTest({
  required String feature,
  required String functionName,
  required Logger logger,
  required Directory root,
  bool force = false,
}) async {
  final projectName = detectProjectName(root: root);
  final featureSnake = snakeCase(feature);
  final functionSnake = snakeCase(functionName);
  final functionPascal = pascalCase(functionSnake);
  final usecaseClass = '${functionPascal}Usecase';
  final testDir = Directory(
    p.join(root.path, 'test', 'features', featureSnake, 'domain', 'usecase'),
  );

  return _writeTestFiles(
    logger: logger,
    directory: testDir,
    files: {
      '${functionSnake}_usecase_test.dart': _functionTest(
        projectName: projectName,
        featureSnake: featureSnake,
        functionSnake: functionSnake,
        usecaseClass: usecaseClass,
      ),
    },
    force: force,
    label: 'function "$functionSnake"',
  );
}

Future<int> _writeTestFiles({
  required Logger logger,
  required Directory directory,
  required Map<String, String> files,
  required bool force,
  required String label,
}) async {
  final progress = logger.progress('Adding tests for $label');
  final written = <String>[];

  try {
    await directory.create(recursive: true);

    for (final entry in files.entries) {
      final file = File(p.join(directory.path, entry.key));
      if (file.existsSync() && !force) {
        progress.fail('Test already exists: ${file.path}');
        logger.info('Run again with --force to overwrite generated tests.');
        return 1;
      }
      await file.writeAsString(entry.value);
      written.add(file.path);
    }
  } on FileSystemException catch (e) {
    progress.fail('Failed to write tests.');
    logger.err(e.message);
    return 1;
  }

  progress.complete('Added ${written.length} test file(s).');
  for (final path in written) {
    logger.info('  $path');
  }
  return 0;
}

String _featureStateTest({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String stateManagement,
  required String architecture,
}) {
  final isClean = architecture != 'mvvm' && architecture != 'modular';
  final statusImport = isClean
      ? stateManagement == 'provider'
          ? "import 'package:$projectName/core/presentation/manager/custom_state.dart';\n"
          : ''
      : architecture == 'mvvm'
          ? "import 'package:$projectName/ui/core/view_models/view_state.dart';\n"
          : "import 'package:$projectName/core/state/view_state.dart';\n";
  final statusType = isClean && stateManagement != 'provider'
      ? '${featurePascal}Status'
      : 'ViewStatus';
  final stateImport = switch (architecture) {
    'mvvm' =>
      'package:$projectName/ui/$featureSnake/view_models/${featureSnake}_state.dart',
    'modular' =>
      'package:$projectName/modules/$featureSnake/presentation/${featureSnake}_state.dart',
    _ =>
      'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart',
  };
  return '''
import 'package:flutter_test/flutter_test.dart';
${statusImport}import '$stateImport';

void main() {
  group('${featurePascal}State', () {
    test('starts idle', () {
      const state = ${featurePascal}State();

      expect(state.status, $statusType.idle);
      expect(state.errorMessage, isNull);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test('copyWith updates status and error message', () {
      final state = const ${featurePascal}State().copyWith(
        status: $statusType.error,
        errorMessage: 'Something went wrong',
      );

      expect(state.status, $statusType.error);
      expect(state.errorMessage, 'Something went wrong');
      expect(state.hasError, isTrue);
    });
  });
}
''';
}

String _featureProviderTest({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String stateManagement,
  required String architecture,
}) {
  if (architecture == 'mvvm' || architecture == 'modular') {
    return _profileManagerTest(
      projectName: projectName,
      featureSnake: featureSnake,
      featurePascal: featurePascal,
      stateManagement: stateManagement,
      architecture: architecture,
    );
  }
  if (stateManagement == 'riverpod') {
    return '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_provider.dart';
import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart';

void main() {
  test('${featurePascal}Notifier starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(${_camel(featureSnake)}Provider).status,
        ${featurePascal}Status.idle);
  });
}
''';
  }
  if (stateManagement == 'bloc') {
    return _blocManagerTest(
      projectName: projectName,
      featureSnake: featureSnake,
      featurePascal: featurePascal,
      managerType: '${featurePascal}Bloc',
    );
  }
  if (stateManagement == 'cubit') {
    return _blocManagerTest(
      projectName: projectName,
      featureSnake: featureSnake,
      featurePascal: featurePascal,
      managerType: '${featurePascal}Cubit',
    );
  }
  return '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/core/presentation/manager/custom_state.dart';
import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_provider.dart';

void main() {
  group('${featurePascal}Provider', () {
    test('starts with idle state', () {
      final provider = ${featurePascal}Provider();
      addTearDown(provider.dispose);

      expect(provider.state.status, ViewStatus.idle);
      expect(provider.state.errorMessage, isNull);
    });
  });
}
''';
}

String _profileManagerTest({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String stateManagement,
  required String architecture,
}) {
  final isMvvm = architecture == 'mvvm';
  final managerSuffix = isMvvm ? 'ViewModel' : 'Controller';
  final managerType = '$featurePascal$managerSuffix';
  final managerImport = isMvvm
      ? 'package:$projectName/ui/$featureSnake/view_models/${featureSnake}_view_model.dart'
      : 'package:$projectName/modules/$featureSnake/presentation/${featureSnake}_controller.dart';
  final statusImport = isMvvm
      ? 'package:$projectName/ui/core/view_models/view_state.dart'
      : 'package:$projectName/core/state/view_state.dart';
  final providerName = '${_camel(featureSnake)}${managerSuffix}Provider';

  if (stateManagement == 'riverpod') {
    return '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '$managerImport';
import '$statusImport';

void main() {
  test('$managerType starts idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read($providerName).status, ViewStatus.idle);
  });
}
''';
  }

  final tearDown = stateManagement == 'provider'
      ? 'addTearDown(manager.dispose);'
      : 'addTearDown(manager.close);';
  return '''
import 'package:flutter_test/flutter_test.dart';
import '$managerImport';
import '$statusImport';

void main() {
  test('$managerType starts idle', () {
    final manager = $managerType();
    $tearDown

    expect(manager.state.status, ViewStatus.idle);
  });
}
''';
}

String _blocManagerTest({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String managerType,
}) {
  return '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_provider.dart';
import 'package:$projectName/features/$featureSnake/presentation/manager/${featureSnake}_state.dart';

void main() {
  test('$managerType starts idle', () async {
    final manager = $managerType();
    addTearDown(manager.close);

    expect(manager.state.status, ${featurePascal}Status.idle);
  });
}
''';
}

String _camel(String input) {
  final pascal = pascalCase(input);
  return pascal.isEmpty ? '' : pascal[0].toLowerCase() + pascal.substring(1);
}

String _modelTest({
  required String modelImport,
  required String modelPascal,
}) {
  return '''
import 'package:flutter_test/flutter_test.dart';
import '$modelImport';

void main() {
  group('$modelPascal', () {
    test('model import is available', () {
      expect($modelPascal, isA<Type>());
    }, skip: 'Replace with constructor and equality checks for this model.');
  });
}
''';
}

String _functionTest({
  required String projectName,
  required String featureSnake,
  required String functionSnake,
  required String usecaseClass,
}) {
  return '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/features/$featureSnake/domain/usecase/${functionSnake}_usecase.dart';

void main() {
  group('$usecaseClass', () {
    test('use case import is available', () {
      expect($usecaseClass, isA<Type>());
    }, skip: 'Add a fake repository and assert the use case result.');
  });
}
''';
}
