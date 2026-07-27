import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _architectures = ['clean', 'mvvm'];
const _stateManagers = ['provider', 'riverpod', 'bloc', 'cubit'];
const _routers = ['named', 'go_router'];

final _allCases = <SmokeCase>[
  for (final architecture in _architectures)
    for (final stateManager in _stateManagers)
      for (final router in _routers)
        SmokeCase(
          architecture: architecture,
          stateManager: stateManager,
          router: router,
          storageDrivers: switch ((architecture, stateManager, router)) {
            ('clean', 'provider', 'named') => const ['shared_preferences'],
            ('mvvm', 'riverpod', 'go_router') => const [
                'flutter_secure_storage',
              ],
            _ => const [],
          },
        ),
  for (final stateManager in _stateManagers)
    SmokeCase(
      architecture: 'modular',
      stateManager: stateManager,
      router: 'modular',
      storageDrivers: stateManager == 'bloc'
          ? const ['shared_preferences', 'flutter_secure_storage']
          : const [],
    ),
];

const _quickCaseIds = {
  'clean_provider_named',
  'clean_cubit_go_router',
  'mvvm_riverpod_go_router',
  'modular_bloc',
};

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addMultiOption(
      'case',
      abbr: 'c',
      help: 'Run one or more named cases. Repeat the option or separate names '
          'with commas.',
      valueHelp: 'case-id',
      allowed: _allCases.map((testCase) => testCase.id),
      splitCommas: true,
    )
    ..addFlag(
      'all',
      negatable: false,
      help: 'Run the complete 20-case architecture/state/router matrix.',
    )
    ..addFlag(
      'keep',
      negatable: false,
      help: 'Keep generated applications after successful checks.',
    )
    ..addFlag(
      'build-android',
      negatable: false,
      help: 'Also create Android files and compile a debug APK.',
    )
    ..addOption(
      'work-dir',
      help: 'Directory in which temporary applications are generated.',
      valueHelp: 'path',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  late final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln()
      ..writeln(_usage(parser));
    exitCode = 64;
    return;
  }

  if (args['help'] as bool) {
    stdout.writeln(_usage(parser));
    return;
  }

  final requestedIds = (args['case'] as List<String>).toSet();
  if ((args['all'] as bool) && requestedIds.isNotEmpty) {
    stderr.writeln('Use either --all or --case, not both.');
    exitCode = 64;
    return;
  }

  final selectedCases = _allCases.where((testCase) {
    if (args['all'] as bool) return true;
    if (requestedIds.isNotEmpty) return requestedIds.contains(testCase.id);
    return _quickCaseIds.contains(testCase.id);
  }).toList();

  final packageRoot = Directory(
    p.normalize(p.join(p.dirname(Platform.script.toFilePath()), '..')),
  );
  final configuredWorkDir = args['work-dir'] as String?;
  final ownsWorkDir = configuredWorkDir == null;
  final workDir = ownsWorkDir
      ? await Directory.systemTemp.createTemp('forgekit_generated_smoke_')
      : Directory(p.absolute(configuredWorkDir));
  await workDir.create(recursive: true);

  final environment = <String, String>{
    ...Platform.environment,
    'FORGEKIT_HOME': p.join(workDir.path, '.forgekit'),
    'MASON_CACHE': p.join(workDir.path, '.mason-cache'),
  };
  final cli = p.join(packageRoot.path, 'bin', 'forgekit.dart');
  final startedAt = DateTime.now();
  var succeeded = false;

  stdout
    ..writeln('ForgeKit generated-app smoke tests')
    ..writeln('Workspace: ${workDir.path}')
    ..writeln(
      'Cases: ${selectedCases.map((testCase) => testCase.id).join(', ')}',
    )
    ..writeln();

  try {
    await _run(
      'Register bundled ForgeKit bricks',
      Platform.resolvedExecutable,
      [cli, 'setup'],
      workingDirectory: packageRoot.path,
      environment: environment,
    );

    for (var index = 0; index < selectedCases.length; index++) {
      final testCase = selectedCases[index];
      stdout.writeln(
        '\n========== ${index + 1}/${selectedCases.length}: ${testCase.id} ==========',
      );
      await _runCase(
        testCase,
        cli: cli,
        workDir: workDir,
        environment: environment,
        buildAndroid: args['build-android'] as bool,
      );
    }

    succeeded = true;
    final elapsed = DateTime.now().difference(startedAt);
    stdout.writeln(
      '\nAll ${selectedCases.length} generated-app smoke case(s) passed '
      'in ${_formatDuration(elapsed)}.',
    );
  } on SmokeFailure catch (error) {
    stderr
      ..writeln()
      ..writeln('SMOKE TEST FAILED: ${error.message}')
      ..writeln('Generated files were kept at ${workDir.path}');
    exitCode = error.exitCode == 0 ? 1 : error.exitCode;
  } finally {
    final keep = args['keep'] as bool;
    if (succeeded && !keep && ownsWorkDir && workDir.existsSync()) {
      await workDir.delete(recursive: true);
    } else if (succeeded) {
      stdout.writeln('Generated files kept at ${workDir.path}');
    }
  }
}

Future<void> _runCase(
  SmokeCase testCase, {
  required String cli,
  required Directory workDir,
  required Map<String, String> environment,
  required bool buildAndroid,
}) async {
  final appName = 'forgekit_smoke_${testCase.id}';
  final appDir = Directory(p.join(workDir.path, appName));
  if (appDir.existsSync()) await appDir.delete(recursive: true);

  await _run(
    'Create application',
    Platform.resolvedExecutable,
    [
      cli,
      'create',
      'app',
      appName,
      '--org',
      'dev.forgekit.smoke',
      '--architecture',
      testCase.architecture,
      '--state-management',
      testCase.stateManager,
      if (testCase.router != 'modular') ...['--router', testCase.router],
      '--platforms',
      buildAndroid ? 'web,android' : 'web',
    ],
    workingDirectory: workDir.path,
    environment: environment,
  );

  await _run(
    'Generate feature and starter tests',
    Platform.resolvedExecutable,
    [
      cli,
      'add',
      'feature',
      'smoke_feature',
      '--with-tests',
      '--no-build-runner',
    ],
    workingDirectory: appDir.path,
    environment: environment,
  );

  await _run(
    'Generate and register an additional screen',
    Platform.resolvedExecutable,
    [cli, 'add', 'screen', 'smoke_feature', 'details'],
    workingDirectory: appDir.path,
    environment: environment,
  );

  await _run(
    'Generate architecture-aware environment configuration',
    Platform.resolvedExecutable,
    [cli, 'add', 'env', 'dev,prod'],
    workingDirectory: appDir.path,
    environment: environment,
  );
  await _run(
    'Generate architecture-aware flavor entrypoints',
    Platform.resolvedExecutable,
    [cli, 'add', 'flavor', 'dev,prod'],
    workingDirectory: appDir.path,
    environment: environment,
  );

  final asset = File(p.join(workDir.path, r'smoke$asset.txt'))
    ..writeAsStringSync('ForgeKit smoke asset\n');
  await _run(
    'Generate architecture-aware asset constants',
    Platform.resolvedExecutable,
    [cli, 'add', 'asset', asset.path],
    workingDirectory: appDir.path,
    environment: environment,
  );

  await _run(
    'Generate and initialize a generic service',
    Platform.resolvedExecutable,
    [
      cli,
      'add',
      'service',
      'analytics',
      '--driver',
      'generic',
      '--no-build-runner',
    ],
    workingDirectory: appDir.path,
    environment: environment,
  );

  for (final driver in testCase.storageDrivers) {
    final service =
        driver == 'shared_preferences' ? 'local_storage' : 'secure_storage';
    await _run(
      'Generate $service service ($driver)',
      Platform.resolvedExecutable,
      [
        cli,
        'add',
        'service',
        service,
        '--driver',
        driver,
        '--no-build-runner',
      ],
      workingDirectory: appDir.path,
      environment: environment,
    );
  }

  if (testCase.architecture == 'clean') {
    await _run(
      'Generate JSON model and DTO',
      Platform.resolvedExecutable,
      [
        cli,
        'add',
        'model',
        'smoke_feature',
        'smoke_record',
        '--no-build-runner',
      ],
      workingDirectory: appDir.path,
      environment: environment,
      input: '{"id":1,"class":"safe","values":[1,2.5]}\n\n',
    );
    await _run(
      'Generate JSON API function',
      Platform.resolvedExecutable,
      [
        cli,
        'add',
        'function',
        'smoke_feature',
        'load_status',
        '--method',
        'GET',
        '--path',
        r'/status/$tenant',
        '--no-build-runner',
      ],
      workingDirectory: appDir.path,
      environment: environment,
      input: '{"status":"ok"}\n\n\n',
    );
    await _run(
      'Generate standalone use case',
      Platform.resolvedExecutable,
      [cli, 'add', 'usecase', 'smoke_feature', 'archive_record'],
      workingDirectory: appDir.path,
      environment: environment,
    );

    final openApiEntry = _writeOpenApiFixture(workDir, appName);
    await _run(
      'Import multi-document OpenAPI with authentication',
      Platform.resolvedExecutable,
      [
        cli,
        'import',
        'openapi',
        openApiEntry,
        '--no-build-runner',
      ],
      workingDirectory: appDir.path,
      environment: environment,
    );
  }

  await _run(
    'Resolve generated application dependencies',
    'flutter',
    ['pub', 'get'],
    workingDirectory: appDir.path,
    environment: environment,
  );
  await _run(
    'Run generated-code builders',
    Platform.resolvedExecutable,
    ['run', 'build_runner', 'build'],
    workingDirectory: appDir.path,
    environment: environment,
  );
  await _run(
    'Check ForgeKit architecture contract',
    Platform.resolvedExecutable,
    [cli, 'doctor', '--ci'],
    workingDirectory: appDir.path,
    environment: environment,
  );
  await _run(
    'Analyze generated application',
    'flutter',
    ['analyze'],
    workingDirectory: appDir.path,
    environment: environment,
  );
  // TODO(forgekit): assert that generated output is format-clean once the
  // `__brick__` templates have been reformatted for the tall style that applies
  // at their language version (>=3.7). Adding the check first would fail every
  // clean_* and mvvm_* case, because `create app` is not transactional and so
  // brick output never passes through ForgeKit's own `dart format`.
  await _run(
    'Run generated application tests',
    Platform.resolvedExecutable,
    [cli, 'test', '--no-coverage'],
    workingDirectory: appDir.path,
    environment: environment,
  );

  if (buildAndroid) {
    await _run(
      'Compile generated Android debug APK',
      'flutter',
      ['build', 'apk', '--debug'],
      workingDirectory: appDir.path,
      environment: environment,
    );
  }
}

String _writeOpenApiFixture(Directory workDir, String appName) {
  final directory = Directory(p.join(workDir.path, '${appName}_openapi'))
    ..createSync(recursive: true);
  File(p.join(directory.path, 'schemas.yaml')).writeAsStringSync(r'''
InventoryBase:
  type: object
  required: [id, name]
  properties:
    id: {type: integer}
    name: {type: string}
PhysicalInventory:
  allOf:
    - $ref: '#/InventoryBase'
    - type: object
      required: [weight]
      properties:
        weight: {type: number}
DigitalInventory:
  allOf:
    - $ref: '#/InventoryBase'
    - type: object
      required: [downloadUrl]
      properties:
        downloadUrl: {type: string, format: uri}
InventoryItem:
  oneOf:
    - $ref: '#/PhysicalInventory'
    - $ref: '#/DigitalInventory'
  discriminator:
    propertyName: kind
InventoryInput:
  type: object
  required: [name]
  properties:
    name: {type: string}
    metadata:
      type: object
      additionalProperties: true
''');
  final entry = File(p.join(directory.path, 'openapi.yaml'));
  entry.writeAsStringSync(r'''
openapi: 3.1.1
info: {title: ForgeKit Smoke API, version: '1'}
servers:
  - url: https://api.example.com/v1
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    sessionCookie:
      type: apiKey
      in: cookie
      name: forgekit_session
  parameters:
    InventoryId:
      name: inventoryId
      in: path
      required: true
      schema: {type: integer}
    LocaleCookie:
      name: locale
      in: cookie
      schema: {type: string}
  requestBodies:
    InventoryBody:
      required: true
      content:
        application/json:
          schema: {$ref: 'schemas.yaml#/InventoryInput'}
  responses:
    InventoryResponse:
      description: Inventory item
      content:
        application/json:
          schema: {$ref: 'schemas.yaml#/InventoryItem'}
security:
  - bearerAuth: []
    sessionCookie: []
paths:
  /inventory/$tenant/{inventoryId}:
    parameters:
      - $ref: '#/components/parameters/InventoryId'
      - $ref: '#/components/parameters/LocaleCookie'
    get:
      operationId: getInventory
      tags: [Inventory]
      responses:
        '200': {$ref: '#/components/responses/InventoryResponse'}
    put:
      operationId: updateInventory
      tags: [Inventory]
      requestBody: {$ref: '#/components/requestBodies/InventoryBody'}
      responses:
        '200': {$ref: '#/components/responses/InventoryResponse'}
''');
  return entry.path;
}

Future<void> _run(
  String label,
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  String? input,
}) async {
  final stopwatch = Stopwatch()..start();
  stdout
    ..writeln('\n→ $label')
    ..writeln('  ${_displayCommand(executable, arguments)}');

  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: false,
    mode:
        input == null ? ProcessStartMode.inheritStdio : ProcessStartMode.normal,
    runInShell: Platform.isWindows,
  );
  final outputPipes = <Future<void>>[];
  if (input != null) {
    outputPipes
      ..add(process.stdout.listen(stdout.add).asFuture<void>())
      ..add(process.stderr.listen(stderr.add).asFuture<void>());
    process.stdin.write(input);
    await process.stdin.close();
  }
  final result = await process.exitCode;
  await Future.wait(outputPipes);
  stopwatch.stop();
  if (result != 0) {
    throw SmokeFailure('$label exited with code $result.', result);
  }
  stdout.writeln('✓ $label (${_formatDuration(stopwatch.elapsed)})');
}

String _usage(ArgParser parser) => '''
Compile and test real Flutter applications generated by ForgeKit.

Usage:
  dart run tool/generated_app_smoke.dart
  dart run tool/generated_app_smoke.dart --case clean_provider_named
  dart run tool/generated_app_smoke.dart --all

With no selection option, the four representative quick cases run.

${parser.usage}
''';

String _displayCommand(String executable, List<String> arguments) {
  String quote(String value) => value.contains(' ') ? '"$value"' : value;
  return [quote(executable), ...arguments.map(quote)].join(' ');
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0 ? '${seconds}s' : '${minutes}m ${seconds}s';
}

class SmokeCase {
  const SmokeCase({
    required this.architecture,
    required this.stateManager,
    required this.router,
    this.storageDrivers = const [],
  });

  final String architecture;
  final String stateManager;
  final String router;
  final List<String> storageDrivers;

  String get id => router == 'modular'
      ? '${architecture}_$stateManager'
      : '${architecture}_${stateManager}_$router';
}

class SmokeFailure implements Exception {
  const SmokeFailure(this.message, this.exitCode);

  final String message;
  final int exitCode;
}
