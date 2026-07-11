import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'json_to_dart.dart';
import 'utils.dart';

/// Adds a full API operation ("function") to an existing feature.
///
/// Generates, from JSON pasted at the terminal:
///   * a response DTO + domain model (`toModel()` mapping),
///   * an optional request payload model + DTO (`toDto()` mapping),
///   * a `UseCase`,
/// and wires a method into the feature's API service, repository (abstract +
/// impl) and provider.
///
/// Returns `0` on success, `1` on failure.
Future<int> addFunction({
  required String feature,
  required String functionName,
  required Logger logger,
  required Directory root,
  String? method,
  String? path,
}) async {
  final featureSnake = _snake(feature);
  final fnSnake = _snake(functionName);
  final fnPascal = _pascal(functionName);
  final fnCamel = _camel(functionName);
  final projectName = detectProjectName(root: root);

  final featureDir =
      Directory(p.join(root.path, 'lib', 'features', featureSnake));
  final apiServiceFile = File(
    p.join(
      featureDir.path,
      'data',
      'remote',
      'service',
      '${featureSnake}_api_service.dart',
    ),
  );
  if (!apiServiceFile.existsSync()) {
    logger.err('Feature "$featureSnake" not found (looked for '
        '${apiServiceFile.path}).');
    logger.info('Create it first with: forgekit add feature $featureSnake');
    return 1;
  }
  final featurePascal = _pascal(featureSnake);

  // --- Gather inputs (no spinner running while we read stdin) ---
  final chosenMethod = method ??
      logger.chooseOne(
        'HTTP method?',
        choices: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
        defaultValue: 'GET',
      );
  final httpMethod = (chosenMethod ?? 'GET').toUpperCase();

  final endpoint = (path == null || path.isEmpty)
      ? logger.prompt('Endpoint path?', defaultValue: '/$fnSnake')
      : path;

  logger.info('');
  logger.info(
    'Paste the RESPONSE JSON, then press Enter on an empty line '
    '(leave empty for no typed response):',
  );
  final responseJson = _readJsonBlock();

  logger.info('');
  logger.info(
    'Paste the REQUEST payload JSON (optional), then Enter on an empty line '
    '(leave empty to skip):',
  );
  final payloadJson = _readJsonBlock();

  // --- Parse ---
  final _ResponseSpec response;
  try {
    response = _parseResponse(responseJson, fnPascal);
  } on FormatException catch (e) {
    logger.err('Could not parse the response JSON: ${e.message}');
    return 1;
  }

  final _PayloadSpec? payload;
  try {
    payload = payloadJson.trim().isEmpty
        ? null
        : _parsePayload(payloadJson, fnPascal);
  } on FormatException catch (e) {
    logger.err('Could not parse the payload JSON: ${e.message}');
    return 1;
  }

  final progress = logger.progress('Generating "$fnCamel" in "$featureSnake"');
  final written = <String>[];
  try {
    // 1. Response model + DTO files.
    if (response.classes.isNotEmpty) {
      written.add(
        _write(
          p.join(
            featureDir.path,
            'domain',
            'entity',
            'model',
            '${fnSnake}_response.dart',
          ),
          emitModels(response.classes),
        ),
      );
      written.add(
        _write(
          p.join(
            featureDir.path,
            'data',
            'remote',
            'dto',
            '${fnSnake}_response_dto.dart',
          ),
          emitDto(
            response.classes,
            partName: '${fnSnake}_response_dto',
            withToModel: true,
            modelImport:
                'package:$projectName/features/$featureSnake/domain/entity/model/${fnSnake}_response.dart',
          ),
        ),
      );
    }

    // 2. Payload model + DTO files.
    if (payload != null) {
      written.add(
        _write(
          p.join(
            featureDir.path,
            'domain',
            'entity',
            'payload',
            '${fnSnake}_payload.dart',
          ),
          emitModels(
            payload.classes,
            withToDto: true,
            dtoImport:
                'package:$projectName/features/$featureSnake/data/remote/dto/${fnSnake}_payload_dto.dart',
          ),
        ),
      );
      written.add(
        _write(
          p.join(
            featureDir.path,
            'data',
            'remote',
            'dto',
            '${fnSnake}_payload_dto.dart',
          ),
          emitDto(
            payload.classes,
            partName: '${fnSnake}_payload_dto',
          ),
        ),
      );
    }

    // 3. UseCase.
    written.add(
      _write(
        p.join(featureDir.path, 'domain', 'usecase', '${fnSnake}_usecase.dart'),
        _emitUseCase(
          projectName: projectName,
          featureSnake: featureSnake,
          featurePascal: featurePascal,
          fnSnake: fnSnake,
          fnPascal: fnPascal,
          fnCamel: fnCamel,
          response: response,
          payload: payload,
        ),
      ),
    );

    // 4. Wire the existing files.
    _wireApiService(
      apiServiceFile,
      projectName,
      featureSnake,
      fnSnake,
      fnCamel,
      httpMethod,
      endpoint,
      response,
      payload,
    );
    _wireRepository(
      featureDir,
      projectName,
      featureSnake,
      featurePascal,
      fnSnake,
      fnCamel,
      response,
      payload,
    );
    _wireRepositoryImpl(
      featureDir,
      projectName,
      featureSnake,
      featurePascal,
      fnSnake,
      fnCamel,
      response,
      payload,
    );
    _wireProvider(
      featureDir,
      projectName,
      featureSnake,
      featurePascal,
      fnSnake,
      fnPascal,
      fnCamel,
      response,
      payload,
    );
  } on _GenException catch (e) {
    progress.fail(e.message);
    return 1;
  }

  progress.complete('Added function "$fnCamel" to "$featureSnake".');
  logger.info('');
  logger.info('Generated / updated:');
  for (final f in written) {
    logger.info('  ${p.relative(f, from: root.path)}');
  }
  logger.info(
    '  (wired into api_service, repository, repository_impl, provider)',
  );
  logger.info('');
  logger.info('Next steps:');
  logger.info('  dart run build_runner build --delete-conflicting-outputs');
  return 0;
}

// ---------------------------------------------------------------------------
// Input helpers
// ---------------------------------------------------------------------------

/// Reads lines from stdin until a blank line (or EOF). Returns the joined text.
String _readJsonBlock() {
  final lines = <String>[];
  while (true) {
    final line = stdin.readLineSync();
    if (line == null) break;
    if (line.trim().isEmpty) break;
    lines.add(line);
  }
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Request/response spec (feature-function specific; the JSON→Dart engine lives
// in json_to_dart.dart)
// ---------------------------------------------------------------------------

/// A parsed response: a list of classes plus how it is returned.
class _ResponseSpec {
  _ResponseSpec({
    required this.classes,
    required this.modelType, // e.g. LoginResponse / List<LoginResponse> / dynamic
    required this.dtoType, // e.g. LoginResponseDto / List<LoginResponseDto> / dynamic
    required this.isList,
    required this.hasBody,
  });

  final List<JsonClass> classes;
  final String modelType;
  final String dtoType;
  final bool isList;
  final bool hasBody;
}

class _PayloadSpec {
  _PayloadSpec({required this.classes, required this.rootName});
  final List<JsonClass> classes;
  final String rootName; // e.g. LoginPayload
}

_ResponseSpec _parseResponse(String jsonText, String fnPascal) {
  if (jsonText.trim().isEmpty) {
    return _ResponseSpec(
      classes: const [],
      modelType: 'dynamic',
      dtoType: 'dynamic',
      isList: false,
      hasBody: false,
    );
  }
  final decoded = jsonDecode(jsonText);
  final base = '${fnPascal}Response';

  if (decoded is Map) {
    return _ResponseSpec(
      classes: analyzeJson(base, decoded.cast<String, dynamic>()),
      modelType: base,
      dtoType: '${base}Dto',
      isList: false,
      hasBody: true,
    );
  }
  if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
    return _ResponseSpec(
      classes:
          analyzeJson(base, (decoded.first as Map).cast<String, dynamic>()),
      modelType: 'List<$base>',
      dtoType: 'List<${base}Dto>',
      isList: true,
      hasBody: true,
    );
  }
  // Primitive or list-of-primitive root → no generated classes.
  final t = decoded is List ? 'List<dynamic>' : 'dynamic';
  return _ResponseSpec(
    classes: const [],
    modelType: t,
    dtoType: t,
    isList: decoded is List,
    hasBody: true,
  );
}

_PayloadSpec _parsePayload(String jsonText, String fnPascal) {
  final decoded = jsonDecode(jsonText);
  final base = '${fnPascal}Payload';
  if (decoded is! Map) {
    throw const FormatException('payload must be a JSON object');
  }
  return _PayloadSpec(
    classes: analyzeJson(base, decoded.cast<String, dynamic>()),
    rootName: base,
  );
}

String _emitUseCase({
  required String projectName,
  required String featureSnake,
  required String featurePascal,
  required String fnSnake,
  required String fnPascal,
  required String fnCamel,
  required _ResponseSpec response,
  required _PayloadSpec? payload,
}) {
  final paramsType = payload == null ? 'NoParams' : payload.rootName;
  final b = StringBuffer();
  b.writeln("import 'package:injectable/injectable.dart';");
  b.writeln();
  b.writeln("import 'package:$projectName/core/domain/api/api_result.dart';");
  b.writeln("import 'package:$projectName/core/domain/usecase/use_case.dart';");
  b.writeln(
    "import 'package:$projectName/features/$featureSnake/domain/repository/${featureSnake}_repository.dart';",
  );
  if (response.classes.isNotEmpty) {
    b.writeln(
      "import 'package:$projectName/features/$featureSnake/domain/entity/model/${fnSnake}_response.dart';",
    );
  }
  if (payload != null) {
    b.writeln(
      "import 'package:$projectName/features/$featureSnake/domain/entity/payload/${fnSnake}_payload.dart';",
    );
  }
  b.writeln();
  b.writeln('/// $fnPascal use case.');
  b.writeln('@injectable');
  b.writeln(
    'class ${fnPascal}Usecase extends UseCase<${response.modelType}, $paramsType> {',
  );
  b.writeln('  final ${featurePascal}Repository _repository;');
  b.writeln();
  b.writeln('  ${fnPascal}Usecase(this._repository);');
  b.writeln();
  b.writeln('  @override');
  b.writeln(
    '  Future<ApiResult<${response.modelType}>> call($paramsType params) {',
  );
  b.writeln(
    '    return _repository.$fnCamel(${payload == null ? '' : 'params'});',
  );
  b.writeln('  }');
  b.writeln('}');
  return b.toString();
}

// ---------------------------------------------------------------------------
// Wiring existing files
// ---------------------------------------------------------------------------

void _wireApiService(
  File file,
  String projectName,
  String featureSnake,
  String fnSnake,
  String fnCamel,
  String httpMethod,
  String endpoint,
  _ResponseSpec response,
  _PayloadSpec? payload,
) {
  final imports = <String>[];
  if (response.classes.isNotEmpty) {
    imports.add(
      'package:$projectName/features/$featureSnake/data/remote/dto/${fnSnake}_response_dto.dart',
    );
  }
  final body = payload == null ? '' : '@Body() ${payload.rootName}Dto payload';
  if (payload != null) {
    imports.add(
      'package:$projectName/features/$featureSnake/data/remote/dto/${fnSnake}_payload_dto.dart',
    );
  }

  final method = StringBuffer()
    ..writeln()
    ..writeln("  @$httpMethod('$endpoint')")
    ..writeln('  Future<${response.dtoType}> $fnCamel($body);');

  var content = _addImports(file.readAsStringSync(), imports);
  content = _insertBeforeLastBrace(content, method.toString());
  file.writeAsStringSync(content);
}

void _wireRepository(
  Directory featureDir,
  String projectName,
  String featureSnake,
  String featurePascal,
  String fnSnake,
  String fnCamel,
  _ResponseSpec response,
  _PayloadSpec? payload,
) {
  final file = File(
    p.join(
      featureDir.path,
      'domain',
      'repository',
      '${featureSnake}_repository.dart',
    ),
  );
  if (!file.existsSync()) throw _GenException('Missing ${file.path}');

  final imports = <String>[
    'package:$projectName/core/domain/api/api_result.dart',
    if (response.classes.isNotEmpty)
      'package:$projectName/features/$featureSnake/domain/entity/model/${fnSnake}_response.dart',
    if (payload != null)
      'package:$projectName/features/$featureSnake/domain/entity/payload/${fnSnake}_payload.dart',
  ];
  final param = payload == null ? '' : '${payload.rootName} payload';
  final method = StringBuffer()
    ..writeln()
    ..writeln('  Future<ApiResult<${response.modelType}>> $fnCamel($param);');

  var content = _addImports(file.readAsStringSync(), imports);
  content = _insertBeforeLastBrace(content, method.toString());
  file.writeAsStringSync(content);
}

void _wireRepositoryImpl(
  Directory featureDir,
  String projectName,
  String featureSnake,
  String featurePascal,
  String fnSnake,
  String fnCamel,
  _ResponseSpec response,
  _PayloadSpec? payload,
) {
  final file = File(
    p.join(
      featureDir.path,
      'data',
      'repository',
      '${featureSnake}_repository_impl.dart',
    ),
  );
  if (!file.existsSync()) throw _GenException('Missing ${file.path}');

  final imports = <String>[
    'package:dio/dio.dart',
    'package:$projectName/core/domain/api/api_result.dart',
    if (response.classes.isNotEmpty)
      'package:$projectName/features/$featureSnake/domain/entity/model/${fnSnake}_response.dart',
    if (payload != null)
      'package:$projectName/features/$featureSnake/domain/entity/payload/${fnSnake}_payload.dart',
  ];

  final param = payload == null ? '' : '${payload.rootName} payload';
  final callArg = payload == null ? '' : 'payload.toDto()';
  final String mapExpr;
  if (response.isList && response.classes.isNotEmpty) {
    mapExpr = 'result.map((e) => e.toModel()).toList()';
  } else if (response.classes.isNotEmpty) {
    mapExpr = 'result.toModel()';
  } else {
    mapExpr = 'result';
  }

  final method = StringBuffer()
    ..writeln()
    ..writeln('  @override')
    ..writeln(
      '  Future<ApiResult<${response.modelType}>> $fnCamel($param) async {',
    )
    ..writeln('    try {')
    ..writeln('      final result = await _apiService.$fnCamel($callArg);')
    ..writeln('      return Success($mapExpr);')
    ..writeln('    } on DioException catch (e) {')
    ..writeln('      return Failure(')
    ..writeln("        e.message ?? 'Network error',")
    ..writeln('        statusCode: e.response?.statusCode,')
    ..writeln('      );')
    ..writeln('    } catch (e) {')
    ..writeln('      return Failure(e.toString());')
    ..writeln('    }')
    ..writeln('  }');

  var content = _addImports(file.readAsStringSync(), imports);
  // The bare impl marks _apiService as ignored/unused; now it is used.
  content = content.replaceAll('  // ignore: unused_field\n', '');
  content = _insertBeforeLastBrace(content, method.toString());
  file.writeAsStringSync(content);
}

void _wireProvider(
  Directory featureDir,
  String projectName,
  String featureSnake,
  String featurePascal,
  String fnSnake,
  String fnPascal,
  String fnCamel,
  _ResponseSpec response,
  _PayloadSpec? payload,
) {
  final file = File(
    p.join(
      featureDir.path,
      'presentation',
      'manager',
      '${featureSnake}_provider.dart',
    ),
  );
  if (!file.existsSync()) throw _GenException('Missing ${file.path}');

  final imports = <String>[
    'package:$projectName/core/di/core_module_container.dart',
    'package:$projectName/core/domain/api/api_result.dart',
    'package:$projectName/core/presentation/manager/custom_state.dart',
    'package:$projectName/features/$featureSnake/domain/usecase/${fnSnake}_usecase.dart',
    if (response.classes.isNotEmpty)
      'package:$projectName/features/$featureSnake/domain/entity/model/${fnSnake}_response.dart',
    if (payload == null)
      'package:$projectName/core/domain/usecase/use_case.dart'
    else
      'package:$projectName/features/$featureSnake/domain/entity/payload/${fnSnake}_payload.dart',
  ];

  final param = payload == null ? '' : '${payload.rootName} payload';
  final callArg = payload == null ? 'const NoParams()' : 'payload';
  final fieldType =
      response.modelType == 'dynamic' ? 'dynamic' : '${response.modelType}?';

  final snippet = StringBuffer()
    ..writeln()
    ..writeln('  /// Result of the most recent [$fnCamel] call.')
    ..writeln('  $fieldType ${fnCamel}Result;')
    ..writeln()
    ..writeln('  Future<void> $fnCamel($param) async {')
    ..writeln(
      '    _state = _state.copyWith(status: ViewStatus.loading, errorMessage: null);',
    )
    ..writeln('    notifyListeners();')
    ..writeln()
    ..writeln('    final result = await getIt<${fnPascal}Usecase>()($callArg);')
    ..writeln()
    ..writeln('    switch (result) {')
    ..writeln('      case Success(:final data):')
    ..writeln('        ${fnCamel}Result = data;')
    ..writeln('        _state = _state.copyWith(status: ViewStatus.success);')
    ..writeln('      case Failure(:final message):')
    ..writeln(
      '        _state = _state.copyWith(status: ViewStatus.error, errorMessage: message);',
    )
    ..writeln('    }')
    ..writeln('    notifyListeners();')
    ..writeln('  }');

  var content = _addImports(file.readAsStringSync(), imports);
  content = _insertBeforeLastBrace(content, snippet.toString());
  file.writeAsStringSync(content);
}

// ---------------------------------------------------------------------------
// File-editing primitives
// ---------------------------------------------------------------------------

String _write(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return path;
}

/// Inserts [snippet] immediately before the file's final `}` (the class body).
String _insertBeforeLastBrace(String content, String snippet) {
  final idx = content.lastIndexOf('}');
  if (idx == -1) throw const _GenException('No class body found to extend.');
  return content.substring(0, idx) + snippet + content.substring(idx);
}

/// Adds `import` directives for any [uris] not already present.
String _addImports(String content, List<String> uris) {
  final existing = RegExp(r'''^import\s+['"]([^'"]+)['"]''', multiLine: true)
      .allMatches(content)
      .map((m) => m.group(1))
      .toSet();

  final toAdd = uris.where((u) => !existing.contains(u)).toSet().toList()
    ..sort();
  if (toAdd.isEmpty) return content;

  final block = toAdd.map((u) => "import '$u';").join('\n');

  final importLines = RegExp(r'''^import\s+.*$''', multiLine: true)
      .allMatches(content)
      .toList();
  if (importLines.isNotEmpty) {
    final last = importLines.last;
    return '${content.substring(0, last.end)}\n$block${content.substring(last.end)}';
  }
  // No imports yet — put them at the very top.
  return '$block\n\n$content';
}

// ---------------------------------------------------------------------------
// Naming helpers
// ---------------------------------------------------------------------------

String _snake(String input) => snakeCase(input);
String _pascal(String input) => pascalCase(input);
String _camel(String input) => camelCase(input);

class _GenException implements Exception {
  const _GenException(this.message);
  final String message;
}
