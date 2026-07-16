import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config_service.dart';
import 'json_to_dart.dart';
import 'test_service.dart';
import 'utils.dart';

const _httpMethods = {
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'head',
  'options',
};

class OpenApiException implements Exception {
  const OpenApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenApiDocument {
  OpenApiDocument({
    required this.version,
    required this.title,
    required this.serverUrl,
    required this.operations,
    required Map<String, dynamic> source,
  }) : _source = source;

  final String version;
  final String title;
  final String? serverUrl;
  final List<OpenApiOperation> operations;
  final Map<String, dynamic> _source;

  Map<String, dynamic> resolve(Map<String, dynamic> value) {
    final ref = value[r'$ref'];
    if (ref is! String) return value;
    if (!ref.startsWith('#/')) {
      throw OpenApiException(
        'External OpenAPI references are not supported yet: $ref',
      );
    }

    Object? current = _source;
    for (final encoded in ref.substring(2).split('/')) {
      final segment = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is! Map<String, dynamic> || !current.containsKey(segment)) {
        throw OpenApiException('OpenAPI reference does not exist: $ref');
      }
      current = current[segment];
    }
    if (current is! Map<String, dynamic>) {
      throw OpenApiException('OpenAPI reference is not an object: $ref');
    }
    return current;
  }
}

class OpenApiOperation {
  const OpenApiOperation({
    required this.name,
    required this.method,
    required this.path,
    required this.summary,
    required this.tags,
    required this.parameters,
    required this.requestSchema,
    required this.requestRequired,
    required this.responseSchema,
    required this.responseStatus,
  });

  final String name;
  final String method;
  final String path;
  final String? summary;
  final List<String> tags;
  final List<OpenApiParameter> parameters;
  final Map<String, dynamic>? requestSchema;
  final bool requestRequired;
  final Map<String, dynamic>? responseSchema;
  final String? responseStatus;
}

class OpenApiParameter {
  const OpenApiParameter({
    required this.name,
    required this.location,
    required this.required,
    required this.schema,
  });

  final String name;
  final String location;
  final bool required;
  final Map<String, dynamic> schema;
}

Future<String> loadOpenApiSource(String source) async {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenApiException(
        'Could not download OpenAPI document (${response.statusCode}).',
      );
    }
    return response.body;
  }

  final file = File(source).absolute;
  if (!file.existsSync()) {
    throw OpenApiException('OpenAPI file not found: ${file.path}');
  }
  return file.readAsString();
}

OpenApiDocument parseOpenApi(String contents) {
  final Object? decoded;
  try {
    decoded = contents.trimLeft().startsWith('{')
        ? jsonDecode(contents)
        : loadYaml(contents);
  } on YamlException catch (error) {
    throw OpenApiException('Invalid OpenAPI YAML: ${error.message}');
  } on FormatException catch (error) {
    throw OpenApiException('Invalid OpenAPI document: ${error.message}');
  }

  final plain = _plainValue(decoded);
  if (plain is! Map<String, dynamic>) {
    throw const OpenApiException('The OpenAPI document must be an object.');
  }
  final version = plain['openapi'];
  if (version is! String || !version.startsWith('3.')) {
    throw OpenApiException(
      'Expected an OpenAPI 3.x document, received ${version ?? 'no version'}.',
    );
  }

  final info = _mapOrEmpty(plain['info']);
  final title = info['title'] is String ? info['title'] as String : 'API';
  final servers = _listOrEmpty(plain['servers']);
  final firstServer = _firstOrNull(
    servers.whereType<Map<String, dynamic>>(),
  );
  final serverUrl =
      firstServer?['url'] is String ? firstServer!['url'] as String : null;
  final document = OpenApiDocument(
    version: version,
    title: title,
    serverUrl: serverUrl,
    operations: [],
    source: plain,
  );

  final paths = _mapOrEmpty(plain['paths']);
  if (paths.isEmpty) {
    throw const OpenApiException('The OpenAPI document has no paths.');
  }

  final operations = <OpenApiOperation>[];
  for (final pathEntry in paths.entries) {
    if (!pathEntry.key.startsWith('/')) continue;
    final pathItem = document.resolve(_mapOrEmpty(pathEntry.value));
    final pathParameters = _parseParameters(
      document,
      _listOrEmpty(pathItem['parameters']),
    );
    for (final method in _httpMethods) {
      final rawOperation = pathItem[method];
      if (rawOperation is! Map<String, dynamic>) continue;
      final operation = document.resolve(rawOperation);
      final operationParameters = _parseParameters(
        document,
        _listOrEmpty(operation['parameters']),
      );
      final parameters = _mergeParameters(pathParameters, operationParameters);
      final requestBody = _parseRequestBody(document, operation['requestBody']);
      final response = _parseResponse(document, operation['responses']);
      final tags = _listOrEmpty(operation['tags'])
          .whereType<String>()
          .where((tag) => tag.trim().isNotEmpty)
          .toList();
      final operationId = operation['operationId'];
      final fallback = _operationName(method, pathEntry.key);
      final name = snakeCase(
        operationId is String && operationId.trim().isNotEmpty
            ? operationId
            : fallback,
      );
      operations.add(
        OpenApiOperation(
          name: name,
          method: method.toUpperCase(),
          path: pathEntry.key,
          summary: operation['summary'] as String?,
          tags: tags,
          parameters: parameters,
          requestSchema: requestBody?.schema,
          requestRequired: requestBody?.required ?? false,
          responseSchema: response?.schema,
          responseStatus: response?.status,
        ),
      );
    }
  }
  if (operations.isEmpty) {
    throw const OpenApiException(
      'The OpenAPI document does not contain supported HTTP operations.',
    );
  }

  return OpenApiDocument(
    version: version,
    title: title,
    serverUrl: serverUrl,
    operations: operations,
    source: plain,
  );
}

List<OpenApiParameter> _parseParameters(
  OpenApiDocument document,
  List<dynamic> values,
) {
  final result = <OpenApiParameter>[];
  for (final value in values) {
    if (value is! Map<String, dynamic>) continue;
    final parameter = document.resolve(value);
    final name = parameter['name'];
    final location = parameter['in'];
    if (name is! String || location is! String) continue;
    if (!{'path', 'query', 'header'}.contains(location)) continue;
    var schema = _mapOrEmpty(parameter['schema']);
    if (schema.isEmpty) {
      schema = _schemaFromContent(parameter['content']);
    }
    result.add(
      OpenApiParameter(
        name: name,
        location: location,
        required: location == 'path' || parameter['required'] == true,
        schema: schema,
      ),
    );
  }
  return result;
}

List<OpenApiParameter> _mergeParameters(
  List<OpenApiParameter> inherited,
  List<OpenApiParameter> operation,
) {
  final merged = <String, OpenApiParameter>{};
  for (final parameter in [...inherited, ...operation]) {
    merged['${parameter.location}:${parameter.name}'] = parameter;
  }
  return merged.values.toList();
}

_BodySpec? _parseRequestBody(OpenApiDocument document, Object? value) {
  if (value is! Map<String, dynamic>) return null;
  final body = document.resolve(value);
  final schema = _schemaFromContent(body['content']);
  if (schema.isEmpty) return null;
  return _BodySpec(schema: schema, required: body['required'] == true);
}

_ResponseSpec? _parseResponse(OpenApiDocument document, Object? value) {
  final responses = _mapOrEmpty(value);
  if (responses.isEmpty) return null;
  final successful = responses.entries
      .where((entry) => RegExp(r'^2[0-9][0-9]$').hasMatch(entry.key))
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final selected = successful.isNotEmpty
      ? successful.first
      : _firstOrNull(
          responses.entries.where((entry) => entry.key == 'default'),
        );
  if (selected == null || selected.value is! Map<String, dynamic>) return null;
  final response = document.resolve(selected.value as Map<String, dynamic>);
  final schema = _schemaFromContent(response['content']);
  return _ResponseSpec(
    status: selected.key,
    schema: schema.isEmpty ? null : schema,
  );
}

Map<String, dynamic> _schemaFromContent(Object? value) {
  final content = _mapOrEmpty(value);
  if (content.isEmpty) return {};
  final media = content['application/json'] ??
      _firstOrNull(
        content.entries
            .where((entry) => entry.key.endsWith('+json'))
            .map((entry) => entry.value),
      ) ??
      content['*/*'] ??
      content.values.first;
  return _mapOrEmpty(_mapOrEmpty(media)['schema']);
}

String _operationName(String method, String path) {
  final segments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => segment.replaceAll('{', 'by_').replaceAll('}', ''));
  return '${method}_${segments.join('_')}';
}

Object? _plainValue(Object? value) {
  if (value is YamlMap || value is Map) {
    return <String, dynamic>{
      for (final entry in (value as Map).entries)
        entry.key.toString(): _plainValue(entry.value),
    };
  }
  if (value is YamlList || value is List) {
    return [for (final item in value as List) _plainValue(item)];
  }
  return value;
}

Map<String, dynamic> _mapOrEmpty(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<dynamic> _listOrEmpty(Object? value) =>
    value is List<dynamic> ? value : <dynamic>[];

T? _firstOrNull<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

class _BodySpec {
  const _BodySpec({required this.schema, required this.required});

  final Map<String, dynamic> schema;
  final bool required;
}

class _ResponseSpec {
  const _ResponseSpec({required this.status, required this.schema});

  final String status;
  final Map<String, dynamic>? schema;
}

Future<int> importOpenApi({
  required String source,
  required Directory root,
  required Logger logger,
  required ForgeKitConfig config,
  List<String> tags = const [],
  String? featureOverride,
  String? baseUrlOverride,
  bool generateTests = true,
  bool force = false,
}) async {
  final progress = logger.progress('Reading OpenAPI document');
  late final OpenApiDocument document;
  try {
    document = parseOpenApi(await loadOpenApiSource(source));
  } on OpenApiException catch (error) {
    progress.fail(error.message);
    return 1;
  } on http.ClientException catch (error) {
    progress.fail('Could not download OpenAPI document: ${error.message}');
    return 1;
  } on FileSystemException catch (error) {
    progress.fail('Could not read OpenAPI document: ${error.message}');
    return 1;
  }

  final selectedTags = tags
      .expand((tag) => tag.split(','))
      .map((tag) => tag.trim().toLowerCase())
      .where((tag) => tag.isNotEmpty)
      .toSet();
  final operations = selectedTags.isEmpty
      ? document.operations
      : document.operations
          .where(
            (operation) => operation.tags.any(
              (tag) => selectedTags.contains(tag.toLowerCase()),
            ),
          )
          .toList();
  if (operations.isEmpty) {
    progress.fail('No OpenAPI operations matched the selected tags.');
    final available = document.operations.expand((op) => op.tags).toSet();
    if (available.isNotEmpty) {
      logger.info('Available tags: ${available.join(', ')}');
    }
    return 1;
  }

  final grouped = <String, List<OpenApiOperation>>{};
  for (final operation in operations) {
    final rawFeature = featureOverride?.trim().isNotEmpty == true
        ? featureOverride!
        : operation.tags.isNotEmpty
            ? operation.tags.first
            : _featureFromPath(operation.path);
    final feature = snakeCase(rawFeature);
    grouped.putIfAbsent(feature.isEmpty ? 'api' : feature, () => []).add(
          operation,
        );
  }
  for (final entry in grouped.entries) {
    _makeOperationNamesUnique(entry.value);
    final featureDir = Directory(
      p.join(root.path, 'lib', 'features', entry.key),
    );
    if (featureDir.existsSync() && !force) {
      progress.fail('Feature "${entry.key}" already exists.');
      logger.info('Run again with --force to replace generated features.');
      return 1;
    }
  }
  progress.complete(
    'Loaded ${document.title} (${operations.length} operations).',
  );

  final projectName = detectProjectName(root: root);
  final generated = <String>[];
  for (final entry in grouped.entries) {
    final feature = entry.key;
    final featureDir = Directory(
      p.join(root.path, 'lib', 'features', feature),
    );
    if (featureDir.existsSync()) await featureDir.delete(recursive: true);

    final featureProgress =
        logger.progress('Generating API feature "$feature"');
    final masonCode = await runMason(
      [
        'make',
        'forge_feature',
        '--name',
        feature,
        '--useRouter',
        '${config.router == 'named'}',
        '--projectName',
        projectName,
        ...stateManagementMasonFlags(config.stateManagement),
        '--runBuildRunner',
        'false',
        '-o',
        '.',
      ],
      logger: logger,
      workingDirectory: root.path,
    );
    if (masonCode != 0) {
      featureProgress.fail('Could not scaffold feature "$feature".');
      return 1;
    }

    try {
      final specs = entry.value
          .map((operation) => _buildOperation(document, operation))
          .toList();
      _writeApiFeature(
        root: root,
        feature: feature,
        operations: specs,
        projectName: projectName,
        stateManagement: config.stateManagement,
        baseUrl: baseUrlOverride ?? document.serverUrl,
      );
      if (generateTests) {
        final testCode = await _writeOpenApiTests(
          root: root,
          logger: logger,
          feature: feature,
          operations: specs,
          force: force,
        );
        if (testCode != 0) {
          featureProgress.fail('Could not generate tests for "$feature".');
          return 1;
        }
      }
      generated.add(feature);
      featureProgress.complete(
        'Generated "$feature" with ${specs.length} operation(s).',
      );
    } on OpenApiException catch (error) {
      featureProgress.fail(error.message);
      return 1;
    } on FileSystemException catch (error) {
      featureProgress
          .fail('Could not write generated feature: ${error.message}');
      return 1;
    }
  }

  logger.info('Generated API features: ${generated.join(', ')}');
  return 0;
}

String _featureFromPath(String path) {
  return path.split('/').firstWhere(
        (segment) => segment.isNotEmpty && !segment.startsWith('{'),
        orElse: () => 'api',
      );
}

void _makeOperationNamesUnique(List<OpenApiOperation> operations) {
  final counts = <String, int>{};
  for (var index = 0; index < operations.length; index++) {
    final operation = operations[index];
    final count = (counts[operation.name] ?? 0) + 1;
    counts[operation.name] = count;
    if (count == 1) continue;
    operations[index] = OpenApiOperation(
      name: '${operation.name}_$count',
      method: operation.method,
      path: operation.path,
      summary: operation.summary,
      tags: operation.tags,
      parameters: operation.parameters,
      requestSchema: operation.requestSchema,
      requestRequired: operation.requestRequired,
      responseSchema: operation.responseSchema,
      responseStatus: operation.responseStatus,
    );
  }
}

enum _ValueKind { primitive, object, objectList, primitiveList }

class _ApiField {
  const _ApiField({
    required this.jsonName,
    required this.dartName,
    required this.modelType,
    required this.dtoType,
    required this.required,
    required this.kind,
  });

  final String jsonName;
  final String dartName;
  final String modelType;
  final String dtoType;
  final bool required;
  final _ValueKind kind;
}

class _ApiClass {
  _ApiClass(this.name, this.fields);

  final String name;
  final List<_ApiField> fields;
}

class _SchemaOutput {
  const _SchemaOutput({
    required this.classes,
    required this.modelType,
    required this.dtoType,
    required this.kind,
    required this.rootClassName,
    required this.sampleJson,
  });

  final List<_ApiClass> classes;
  final String modelType;
  final String dtoType;
  final _ValueKind kind;
  final String? rootClassName;
  final Object? sampleJson;

  bool get hasClasses => classes.isNotEmpty;
}

class _CompiledType {
  const _CompiledType({
    required this.modelType,
    required this.dtoType,
    required this.kind,
    this.rootClassName,
  });

  final String modelType;
  final String dtoType;
  final _ValueKind kind;
  final String? rootClassName;
}

class _SchemaCompiler {
  _SchemaCompiler(this.document);

  final OpenApiDocument document;
  final Map<String, _ApiClass> _classes = {};
  final Map<String, String> _referenceNames = {};

  _SchemaOutput compile(Map<String, dynamic> schema, String preferredName) {
    final type = _compile(schema, preferredName);
    return _SchemaOutput(
      classes: _classes.values.toList(),
      modelType: type.modelType,
      dtoType: type.dtoType,
      kind: type.kind,
      rootClassName: type.rootClassName,
      sampleJson: _sampleForSchema(schema),
    );
  }

  _CompiledType _compile(Map<String, dynamic> raw, String preferredName) {
    final ref = raw[r'$ref'];
    if (ref is String && _referenceNames.containsKey(ref)) {
      final className = _referenceNames[ref]!;
      return _CompiledType(
        modelType: className,
        dtoType: '${className}Dto',
        kind: _ValueKind.object,
        rootClassName: className,
      );
    }
    final schema = _normalizeSchema(raw);
    final type = schema['type'];
    final properties = _mapOrEmpty(schema['properties']);
    if (type == 'object' || properties.isNotEmpty) {
      final name = pascalCase(preferredName);
      final className = name.isEmpty ? 'ApiModel' : name;
      if (ref is String) _referenceNames[ref] = className;
      if (!_classes.containsKey(className)) {
        final target = _ApiClass(className, []);
        _classes[className] = target;
        final requiredNames =
            _listOrEmpty(schema['required']).whereType<String>().toSet();
        for (final property in properties.entries) {
          final fieldSchema = _mapOrEmpty(property.value);
          final nested = _compile(
            fieldSchema,
            '$className${pascalCase(property.key)}',
          );
          final isRequired =
              requiredNames.contains(property.key) && !_isNullable(fieldSchema);
          target.fields.add(
            _ApiField(
              jsonName: property.key,
              dartName: _safeIdentifier(camelCase(property.key)),
              modelType: _optionalType(nested.modelType, isRequired),
              dtoType: _optionalType(nested.dtoType, isRequired),
              required: isRequired,
              kind: nested.kind,
            ),
          );
        }
      }
      return _CompiledType(
        modelType: className,
        dtoType: '${className}Dto',
        kind: _ValueKind.object,
        rootClassName: className,
      );
    }
    if (type == 'array') {
      final item = _compile(
        _mapOrEmpty(schema['items']),
        singular(preferredName),
      );
      return _CompiledType(
        modelType: 'List<${item.modelType}>',
        dtoType: 'List<${item.dtoType}>',
        kind: item.kind == _ValueKind.object
            ? _ValueKind.objectList
            : _ValueKind.primitiveList,
        rootClassName: item.rootClassName,
      );
    }
    final primitive = _primitiveType(schema);
    return _CompiledType(
      modelType: primitive,
      dtoType: primitive,
      kind: _ValueKind.primitive,
    );
  }

  Map<String, dynamic> _normalizeSchema(Map<String, dynamic> raw) {
    var resolved = document.resolve(raw);
    final compositions = _listOrEmpty(resolved['allOf']);
    if (compositions.isEmpty) return resolved;
    final merged = <String, dynamic>{...resolved}..remove('allOf');
    final properties = <String, dynamic>{};
    final required = <String>{};
    for (final part in compositions) {
      if (part is! Map<String, dynamic>) continue;
      final normalized = _normalizeSchema(part);
      properties.addAll(_mapOrEmpty(normalized['properties']));
      required.addAll(_listOrEmpty(normalized['required']).whereType<String>());
      for (final entry in normalized.entries) {
        if (entry.key != 'properties' && entry.key != 'required') {
          merged.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    properties.addAll(_mapOrEmpty(merged['properties']));
    required.addAll(_listOrEmpty(merged['required']).whereType<String>());
    if (properties.isNotEmpty) merged['properties'] = properties;
    if (required.isNotEmpty) merged['required'] = required.toList();
    return merged;
  }

  Object? _sampleForSchema(Map<String, dynamic> raw, [Set<String>? seen]) {
    final refs = seen ?? <String>{};
    final ref = raw[r'$ref'];
    if (ref is String && !refs.add(ref)) return null;
    final schema = _normalizeSchema(raw);
    final properties = _mapOrEmpty(schema['properties']);
    if (schema['type'] == 'object' || properties.isNotEmpty) {
      return <String, dynamic>{
        for (final property in properties.entries)
          property.key: _sampleForSchema(
            _mapOrEmpty(property.value),
            {...refs},
          ),
      };
    }
    if (schema['type'] == 'array') {
      return [
        _sampleForSchema(_mapOrEmpty(schema['items']), {...refs}),
      ];
    }
    final example = schema['example'] ?? schema['default'];
    if (example != null) return example;
    final enumValues = _listOrEmpty(schema['enum']);
    if (enumValues.isNotEmpty) return enumValues.first;
    return switch (schema['type']) {
      'integer' => 1,
      'number' => 1.5,
      'boolean' => true,
      'string' => schema['format'] == 'date-time'
          ? '2026-01-01T00:00:00.000Z'
          : schema['format'] == 'date'
              ? '2026-01-01'
              : 'value',
      _ => null,
    };
  }
}

String _primitiveType(Map<String, dynamic> schema) {
  return switch (schema['type']) {
    'integer' => 'int',
    'number' => 'double',
    'boolean' => 'bool',
    'string' when schema['format'] == 'date-time' => 'DateTime',
    'string' when schema['format'] == 'date' => 'DateTime',
    'string' => 'String',
    'object' => 'Map<String, dynamic>',
    _ => 'dynamic',
  };
}

bool _isNullable(Map<String, dynamic> schema) {
  if (schema['nullable'] == true) return true;
  final type = schema['type'];
  return type is List && type.contains('null');
}

String _optionalType(String type, bool required) {
  if (required || type == 'dynamic' || type.endsWith('?')) return type;
  return '$type?';
}

const _dartKeywords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'type',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

String _safeIdentifier(String value) {
  final candidate = value.isEmpty ? 'value' : value;
  return _dartKeywords.contains(candidate) ? '${candidate}Value' : candidate;
}

class _InputField {
  const _InputField({
    required this.apiName,
    required this.dartName,
    required this.type,
    required this.required,
    required this.location,
  });

  final String apiName;
  final String dartName;
  final String type;
  final bool required;
  final String location;
}

class _OperationSpec {
  const _OperationSpec({
    required this.operation,
    required this.snake,
    required this.camel,
    required this.pascal,
    required this.response,
    required this.request,
    required this.inputs,
    required this.bodyField,
  });

  final OpenApiOperation operation;
  final String snake;
  final String camel;
  final String pascal;
  final _SchemaOutput response;
  final _SchemaOutput? request;
  final List<_InputField> inputs;
  final _InputField? bodyField;

  bool get hasParams => inputs.isNotEmpty || bodyField != null;
  String get paramsType => hasParams ? '${pascal}Params' : 'NoParams';
}

_OperationSpec _buildOperation(
  OpenApiDocument document,
  OpenApiOperation operation,
) {
  final snake = snakeCase(operation.name);
  final pascal = pascalCase(snake);
  final response = operation.responseSchema == null
      ? const _SchemaOutput(
          classes: [],
          modelType: 'dynamic',
          dtoType: 'dynamic',
          kind: _ValueKind.primitive,
          rootClassName: null,
          sampleJson: null,
        )
      : _SchemaCompiler(document).compile(
          operation.responseSchema!,
          '${pascal}Response',
        );
  final request = operation.requestSchema == null
      ? null
      : _SchemaCompiler(document).compile(
          operation.requestSchema!,
          '${pascal}Payload',
        );
  final usedNames = <String>{};
  final inputs = operation.parameters.map((parameter) {
    var name = _safeIdentifier(camelCase(parameter.name));
    if (!usedNames.add(name)) {
      name = '$name${pascalCase(parameter.location)}';
      usedNames.add(name);
    }
    final schema = document.resolve(parameter.schema);
    final type = schema['type'] == 'array'
        ? 'List<${_primitiveType(document.resolve(_mapOrEmpty(schema['items'])))}>'
        : _primitiveType(schema);
    return _InputField(
      apiName: parameter.name,
      dartName: name,
      type: _optionalType(type, parameter.required),
      required: parameter.required,
      location: parameter.location,
    );
  }).toList();
  final bodyName = usedNames.contains('payload') ? 'body' : 'payload';
  final bodyField = request == null
      ? null
      : _InputField(
          apiName: 'body',
          dartName: bodyName,
          type: _optionalType(request.modelType, operation.requestRequired),
          required: operation.requestRequired,
          location: 'body',
        );
  return _OperationSpec(
    operation: operation,
    snake: snake,
    camel: camelCase(snake),
    pascal: pascal,
    response: response,
    request: request,
    inputs: inputs,
    bodyField: bodyField,
  );
}

void _writeApiFeature({
  required Directory root,
  required String feature,
  required List<_OperationSpec> operations,
  required String projectName,
  required String stateManagement,
  required String? baseUrl,
}) {
  final featureDir = p.join(root.path, 'lib', 'features', feature);
  for (final operation in operations) {
    if (operation.response.hasClasses) {
      _writeGenerated(
        p.join(
          featureDir,
          'domain',
          'entity',
          'model',
          '${operation.snake}_response.dart',
        ),
        _emitModels(operation.response.classes),
      );
      _writeGenerated(
        p.join(
          featureDir,
          'data',
          'remote',
          'dto',
          '${operation.snake}_response_dto.dart',
        ),
        _emitDtos(
          operation.response.classes,
          partName: '${operation.snake}_response_dto',
          modelImport:
              'package:$projectName/features/$feature/domain/entity/model/${operation.snake}_response.dart',
          withToModel: true,
        ),
      );
    }
    if (operation.request?.hasClasses == true) {
      _writeGenerated(
        p.join(
          featureDir,
          'domain',
          'entity',
          'payload',
          '${operation.snake}_payload.dart',
        ),
        _emitModels(
          operation.request!.classes,
          dtoImport:
              'package:$projectName/features/$feature/data/remote/dto/${operation.snake}_payload_dto.dart',
          withToDto: true,
        ),
      );
      _writeGenerated(
        p.join(
          featureDir,
          'data',
          'remote',
          'dto',
          '${operation.snake}_payload_dto.dart',
        ),
        _emitDtos(
          operation.request!.classes,
          partName: '${operation.snake}_payload_dto',
        ),
      );
    }
    if (operation.hasParams) {
      _writeGenerated(
        p.join(
          featureDir,
          'domain',
          'entity',
          'payload',
          '${operation.snake}_params.dart',
        ),
        _emitParams(
          operation,
          projectName: projectName,
          feature: feature,
        ),
      );
    }
    _writeGenerated(
      p.join(
        featureDir,
        'domain',
        'usecase',
        '${operation.snake}_usecase.dart',
      ),
      _emitUseCase(
        operation,
        projectName: projectName,
        feature: feature,
      ),
    );
  }

  _writeGenerated(
    p.join(
      featureDir,
      'data',
      'remote',
      'service',
      '${feature}_api_service.dart',
    ),
    _emitApiService(
      feature: feature,
      operations: operations,
      projectName: projectName,
      baseUrl: baseUrl,
    ),
  );
  _writeGenerated(
    p.join(
      featureDir,
      'domain',
      'repository',
      '${feature}_repository.dart',
    ),
    _emitRepository(
      feature: feature,
      operations: operations,
      projectName: projectName,
    ),
  );
  _writeGenerated(
    p.join(
      featureDir,
      'data',
      'repository',
      '${feature}_repository_impl.dart',
    ),
    _emitRepositoryImpl(
      feature: feature,
      operations: operations,
      projectName: projectName,
    ),
  );
  _writeGenerated(
    p.join(
      featureDir,
      'presentation',
      'manager',
      '${feature}_provider.dart',
    ),
    _emitManager(
      feature: feature,
      operations: operations,
      projectName: projectName,
      stateManagement: stateManagement,
    ),
  );
}

void _writeGenerated(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${contents.trimRight()}\n');
}

String _emitModels(
  List<_ApiClass> classes, {
  String? dtoImport,
  bool withToDto = false,
}) {
  final out = StringBuffer();
  if (withToDto && dtoImport != null) {
    out.writeln("import '$dtoImport';");
    out.writeln();
  }
  for (final apiClass in classes) {
    out.writeln('class ${apiClass.name} {');
    for (final field in apiClass.fields) {
      out.writeln('  final ${field.modelType} ${field.dartName};');
    }
    if (apiClass.fields.isNotEmpty) out.writeln();
    out.writeln('  const ${apiClass.name}(${_constructor(apiClass.fields)});');
    if (withToDto) {
      out.writeln();
      out.writeln('  ${apiClass.name}Dto toDto() => ${apiClass.name}Dto(');
      for (final field in apiClass.fields) {
        out.writeln(
          '        ${field.dartName}: ${_mapField(field, toDto: true)},',
        );
      }
      out.writeln('      );');
    }
    out.writeln('}');
    out.writeln();
  }
  return out.toString();
}

String _emitDtos(
  List<_ApiClass> classes, {
  required String partName,
  String? modelImport,
  bool withToModel = false,
}) {
  final out = StringBuffer()
    ..writeln("import 'package:json_annotation/json_annotation.dart';");
  if (withToModel && modelImport != null) {
    out
      ..writeln()
      ..writeln("import '$modelImport';");
  }
  out
    ..writeln()
    ..writeln("part '$partName.g.dart';")
    ..writeln();
  for (final apiClass in classes) {
    out.writeln('@JsonSerializable(explicitToJson: true)');
    out.writeln('class ${apiClass.name}Dto {');
    for (final field in apiClass.fields) {
      if (field.jsonName != field.dartName) {
        out.writeln("  @JsonKey(name: '${_escape(field.jsonName)}')");
      }
      out.writeln('  final ${field.dtoType} ${field.dartName};');
    }
    if (apiClass.fields.isNotEmpty) out.writeln();
    out.writeln(
      '  const ${apiClass.name}Dto(${_constructor(apiClass.fields)});',
    );
    out
      ..writeln()
      ..writeln(
        '  factory ${apiClass.name}Dto.fromJson(Map<String, dynamic> json) =>',
      )
      ..writeln('      _\$${apiClass.name}DtoFromJson(json);')
      ..writeln()
      ..writeln(
        '  Map<String, dynamic> toJson() => _\$${apiClass.name}DtoToJson(this);',
      );
    if (withToModel) {
      out
        ..writeln()
        ..writeln('  ${apiClass.name} toModel() => ${apiClass.name}(');
      for (final field in apiClass.fields) {
        out.writeln(
          '        ${field.dartName}: ${_mapField(field, toDto: false)},',
        );
      }
      out.writeln('      );');
    }
    out
      ..writeln('}')
      ..writeln();
  }
  return out.toString();
}

String _constructor(List<_ApiField> fields) {
  if (fields.isEmpty) return '';
  final out = StringBuffer('{\n');
  for (final field in fields) {
    out.writeln(
      '    ${field.required ? 'required ' : ''}this.${field.dartName},',
    );
  }
  out.write('  }');
  return out.toString();
}

String _mapField(_ApiField field, {required bool toDto}) {
  final name = field.dartName;
  final optional = !field.required;
  return switch (field.kind) {
    _ValueKind.object =>
      '$name${optional ? '?' : ''}.${toDto ? 'toDto' : 'toModel'}()',
    _ValueKind.objectList => optional
        ? '$name?.map((item) => item.${toDto ? 'toDto' : 'toModel'}()).toList()'
        : '$name.map((item) => item.${toDto ? 'toDto' : 'toModel'}()).toList()',
    _ValueKind.primitive || _ValueKind.primitiveList => name,
  };
}

String _emitParams(
  _OperationSpec operation, {
  required String projectName,
  required String feature,
}) {
  final out = StringBuffer();
  if (operation.request?.hasClasses == true) {
    out
      ..writeln(
        "import 'package:$projectName/features/$feature/domain/entity/payload/${operation.snake}_payload.dart';",
      )
      ..writeln();
  }
  final fields = [
    ...operation.inputs,
    if (operation.bodyField != null) operation.bodyField!,
  ];
  out.writeln('class ${operation.paramsType} {');
  for (final field in fields) {
    out.writeln('  final ${field.type} ${field.dartName};');
  }
  out
    ..writeln()
    ..writeln('  const ${operation.paramsType}({');
  for (final field in fields) {
    out.writeln(
      '    ${field.required ? 'required ' : ''}this.${field.dartName},',
    );
  }
  out
    ..writeln('  });')
    ..writeln('}');
  return out.toString();
}

String _emitUseCase(
  _OperationSpec operation, {
  required String projectName,
  required String feature,
}) {
  final featurePascal = pascalCase(feature);
  final out = StringBuffer()
    ..writeln("import 'package:injectable/injectable.dart';")
    ..writeln()
    ..writeln("import 'package:$projectName/core/domain/api/api_result.dart';")
    ..writeln(
      "import 'package:$projectName/core/domain/usecase/use_case.dart';",
    )
    ..writeln(
      "import 'package:$projectName/features/$feature/domain/repository/${feature}_repository.dart';",
    );
  if (operation.response.hasClasses) {
    out.writeln(
      "import 'package:$projectName/features/$feature/domain/entity/model/${operation.snake}_response.dart';",
    );
  }
  if (operation.hasParams) {
    out.writeln(
      "import 'package:$projectName/features/$feature/domain/entity/payload/${operation.snake}_params.dart';",
    );
  }
  out
    ..writeln()
    ..writeln('@injectable')
    ..writeln(
      'class ${operation.pascal}Usecase extends UseCase<${operation.response.modelType}, ${operation.paramsType}> {',
    )
    ..writeln('  final ${featurePascal}Repository _repository;')
    ..writeln()
    ..writeln('  ${operation.pascal}Usecase(this._repository);')
    ..writeln()
    ..writeln('  @override')
    ..writeln(
      '  Future<ApiResult<${operation.response.modelType}>> call(${operation.paramsType} params) {',
    )
    ..writeln(
      '    return _repository.${operation.camel}(${operation.hasParams ? 'params' : ''});',
    )
    ..writeln('  }')
    ..writeln('}');
  return out.toString();
}

String _emitApiService({
  required String feature,
  required List<_OperationSpec> operations,
  required String projectName,
  required String? baseUrl,
}) {
  final featurePascal = pascalCase(feature);
  final out = StringBuffer()
    ..writeln("import 'package:dio/dio.dart';")
    ..writeln("import 'package:retrofit/retrofit.dart';");
  for (final operation in operations) {
    if (operation.response.hasClasses) {
      out.writeln(
        "import 'package:$projectName/features/$feature/data/remote/dto/${operation.snake}_response_dto.dart';",
      );
    }
    if (operation.request?.hasClasses == true) {
      out.writeln(
        "import 'package:$projectName/features/$feature/data/remote/dto/${operation.snake}_payload_dto.dart';",
      );
    }
  }
  out
    ..writeln()
    ..writeln("part '${feature}_api_service.g.dart';")
    ..writeln()
    ..writeln(
      baseUrl?.trim().isNotEmpty == true
          ? "@RestApi(baseUrl: '${_escape(baseUrl!.trim())}')"
          : '@RestApi()',
    )
    ..writeln('abstract class ${featurePascal}ApiService {')
    ..writeln(
      '  factory ${featurePascal}ApiService(Dio dio, {String baseUrl}) =',
    )
    ..writeln('      _${featurePascal}ApiService;');
  for (final operation in operations) {
    out.writeln();
    if (operation.operation.summary?.trim().isNotEmpty == true) {
      out.writeln('  /// ${_docText(operation.operation.summary!)}');
    }
    out.writeln(
      "  @${operation.operation.method}('${_escape(operation.operation.path)}')",
    );
    final apiInputs = <String>[];
    for (final input in operation.inputs) {
      final annotation = switch (input.location) {
        'path' => 'Path',
        'header' => 'Header',
        _ => 'Query',
      };
      apiInputs.add(
        "@$annotation('${_escape(input.apiName)}') ${input.type} ${input.dartName}",
      );
    }
    final body = operation.bodyField;
    if (body != null) {
      final dtoType = operation.request!.dtoType;
      apiInputs.add(
        '@Body() ${_optionalType(dtoType, body.required)} ${body.dartName}',
      );
    }
    out.writeln(
      '  Future<${operation.response.dtoType}> ${operation.camel}(${apiInputs.join(', ')});',
    );
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

String _emitRepository({
  required String feature,
  required List<_OperationSpec> operations,
  required String projectName,
}) {
  final out = StringBuffer()
    ..writeln("import 'package:$projectName/core/domain/api/api_result.dart';");
  for (final operation in operations) {
    if (operation.response.hasClasses) {
      out.writeln(
        "import 'package:$projectName/features/$feature/domain/entity/model/${operation.snake}_response.dart';",
      );
    }
    if (operation.hasParams) {
      out.writeln(
        "import 'package:$projectName/features/$feature/domain/entity/payload/${operation.snake}_params.dart';",
      );
    }
  }
  out
    ..writeln()
    ..writeln('abstract class ${pascalCase(feature)}Repository {');
  for (final operation in operations) {
    final parameter =
        operation.hasParams ? '${operation.paramsType} params' : '';
    out.writeln(
      '  Future<ApiResult<${operation.response.modelType}>> ${operation.camel}($parameter);',
    );
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

String _emitRepositoryImpl({
  required String feature,
  required List<_OperationSpec> operations,
  required String projectName,
}) {
  final featurePascal = pascalCase(feature);
  final out = StringBuffer()
    ..writeln("import 'package:dio/dio.dart';")
    ..writeln("import 'package:injectable/injectable.dart';")
    ..writeln()
    ..writeln("import 'package:$projectName/core/domain/api/api_result.dart';")
    ..writeln(
      "import 'package:$projectName/features/$feature/data/remote/service/${feature}_api_service.dart';",
    )
    ..writeln(
      "import 'package:$projectName/features/$feature/domain/repository/${feature}_repository.dart';",
    );
  for (final operation in operations) {
    if (operation.response.hasClasses) {
      out.writeln(
        "import 'package:$projectName/features/$feature/domain/entity/model/${operation.snake}_response.dart';",
      );
    }
    if (operation.hasParams) {
      out.writeln(
        "import 'package:$projectName/features/$feature/domain/entity/payload/${operation.snake}_params.dart';",
      );
    }
  }
  out
    ..writeln()
    ..writeln('@LazySingleton(as: ${featurePascal}Repository)')
    ..writeln(
      'class ${featurePascal}RepositoryImpl implements ${featurePascal}Repository {',
    )
    ..writeln('  final ${featurePascal}ApiService _apiService;')
    ..writeln()
    ..writeln('  ${featurePascal}RepositoryImpl(this._apiService);');
  for (final operation in operations) {
    final parameter =
        operation.hasParams ? '${operation.paramsType} params' : '';
    final arguments = <String>[
      for (final input in operation.inputs) 'params.${input.dartName}',
      if (operation.bodyField != null)
        _requestMapping(
          'params.${operation.bodyField!.dartName}',
          operation.request!,
          optional: !operation.bodyField!.required,
        ),
    ];
    final responseMapping = _responseMapping('result', operation.response);
    out
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  Future<ApiResult<${operation.response.modelType}>> ${operation.camel}($parameter) async {',
      )
      ..writeln('    try {')
      ..writeln(
        '      final result = await _apiService.${operation.camel}(${arguments.join(', ')});',
      )
      ..writeln('      return Success($responseMapping);')
      ..writeln('    } on DioException catch (error) {')
      ..writeln('      return Failure(')
      ..writeln("        error.message ?? 'Network error',")
      ..writeln('        statusCode: error.response?.statusCode,')
      ..writeln('      );')
      ..writeln('    } catch (error) {')
      ..writeln('      return Failure(error.toString());')
      ..writeln('    }')
      ..writeln('  }');
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

String _requestMapping(
  String expression,
  _SchemaOutput schema, {
  required bool optional,
}) {
  return switch (schema.kind) {
    _ValueKind.object => '$expression${optional ? '?' : ''}.toDto()',
    _ValueKind.objectList => optional
        ? '$expression?.map((item) => item.toDto()).toList()'
        : '$expression.map((item) => item.toDto()).toList()',
    _ValueKind.primitive || _ValueKind.primitiveList => expression,
  };
}

String _responseMapping(String expression, _SchemaOutput schema) {
  return switch (schema.kind) {
    _ValueKind.object => '$expression.toModel()',
    _ValueKind.objectList =>
      '$expression.map((item) => item.toModel()).toList()',
    _ValueKind.primitive || _ValueKind.primitiveList => expression,
  };
}

String _emitManager({
  required String feature,
  required List<_OperationSpec> operations,
  required String projectName,
  required String stateManagement,
}) {
  final featurePascal = pascalCase(feature);
  final featureCamel = camelCase(feature);
  final out = StringBuffer();
  if (stateManagement == 'provider') {
    out
      ..writeln("import 'package:injectable/injectable.dart';")
      ..writeln()
      ..writeln(
        "import 'package:$projectName/core/presentation/manager/custom_provider.dart';",
      )
      ..writeln(
        "import 'package:$projectName/core/presentation/manager/custom_state.dart';",
      );
  } else if (stateManagement == 'riverpod') {
    out.writeln("import 'package:flutter_riverpod/flutter_riverpod.dart';");
  } else {
    out
      ..writeln("import 'package:flutter_bloc/flutter_bloc.dart';")
      ..writeln("import 'package:injectable/injectable.dart';");
  }
  out
    ..writeln()
    ..writeln(
      "import 'package:$projectName/core/di/core_module_container.dart';",
    )
    ..writeln("import 'package:$projectName/core/domain/api/api_result.dart';");
  if (operations.any((operation) => !operation.hasParams)) {
    out.writeln(
      "import 'package:$projectName/core/domain/usecase/use_case.dart';",
    );
  }
  out.writeln(
    "import 'package:$projectName/features/$feature/presentation/manager/${feature}_state.dart';",
  );
  for (final operation in operations) {
    out.writeln(
      "import 'package:$projectName/features/$feature/domain/usecase/${operation.snake}_usecase.dart';",
    );
    if (operation.response.hasClasses) {
      out.writeln(
        "import 'package:$projectName/features/$feature/domain/entity/model/${operation.snake}_response.dart';",
      );
    }
    if (operation.hasParams) {
      out.writeln(
        "import 'package:$projectName/features/$feature/domain/entity/payload/${operation.snake}_params.dart';",
      );
    }
  }
  out.writeln();

  if (stateManagement == 'bloc') {
    out.writeln('sealed class ${featurePascal}Event {');
    out.writeln('  const ${featurePascal}Event();');
    out.writeln('}');
    out.writeln();
    for (final operation in operations) {
      out.writeln(
        'class ${operation.pascal}Requested extends ${featurePascal}Event {',
      );
      out.writeln(
        '  const ${operation.pascal}Requested(${operation.hasParams ? 'this.params' : ''});',
      );
      if (operation.hasParams) {
        out.writeln('  final ${operation.paramsType} params;');
      }
      out.writeln('}');
      out.writeln();
    }
  }

  if (stateManagement == 'provider') {
    out
      ..writeln('@injectable')
      ..writeln('class ${featurePascal}Provider extends CustomProvider {')
      ..writeln(
        '  ${featurePascal}State _state = const ${featurePascal}State();',
      )
      ..writeln('  ${featurePascal}State get state => _state;');
  } else if (stateManagement == 'riverpod') {
    out
      ..writeln(
        'final ${featureCamel}Provider = NotifierProvider<${featurePascal}Notifier, ${featurePascal}State>(',
      )
      ..writeln('  ${featurePascal}Notifier.new,')
      ..writeln(');')
      ..writeln()
      ..writeln(
        'class ${featurePascal}Notifier extends Notifier<${featurePascal}State> {',
      )
      ..writeln('  @override')
      ..writeln(
        '  ${featurePascal}State build() => const ${featurePascal}State();',
      );
  } else if (stateManagement == 'bloc') {
    out
      ..writeln('@injectable')
      ..writeln(
        'class ${featurePascal}Bloc extends Bloc<${featurePascal}Event, ${featurePascal}State> {',
      )
      ..writeln(
        '  ${featurePascal}Bloc() : super(const ${featurePascal}State()) {',
      );
    for (final operation in operations) {
      out.writeln(
        '    on<${operation.pascal}Requested>(_on${operation.pascal});',
      );
    }
    out.writeln('  }');
  } else {
    out
      ..writeln('@injectable')
      ..writeln(
        'class ${featurePascal}Cubit extends Cubit<${featurePascal}State> {',
      )
      ..writeln(
        '  ${featurePascal}Cubit() : super(const ${featurePascal}State());',
      );
  }

  for (final operation in operations) {
    _emitManagerOperation(
      out,
      operation: operation,
      featurePascal: featurePascal,
      stateManagement: stateManagement,
    );
  }
  out
    ..writeln('}')
    ..writeln();
  return out.toString();
}

void _emitManagerOperation(
  StringBuffer out, {
  required _OperationSpec operation,
  required String featurePascal,
  required String stateManagement,
}) {
  final resultType = operation.response.modelType == 'dynamic'
      ? 'dynamic'
      : '${operation.response.modelType}?';
  final paramsDeclaration =
      operation.hasParams ? '${operation.paramsType} params' : '';
  final useCaseArgument = operation.hasParams ? 'params' : 'const NoParams()';
  final statusType =
      stateManagement == 'provider' ? 'ViewStatus' : '${featurePascal}Status';

  out
    ..writeln()
    ..writeln('  $resultType ${operation.camel}Result;');
  if (stateManagement == 'bloc') {
    out
      ..writeln()
      ..writeln(
        '  void ${operation.camel}($paramsDeclaration) => add(${operation.pascal}Requested(${operation.hasParams ? 'params' : ''}));',
      )
      ..writeln()
      ..writeln('  Future<void> _on${operation.pascal}(')
      ..writeln('    ${operation.pascal}Requested event,')
      ..writeln('    Emitter<${featurePascal}State> emit,')
      ..writeln('  ) async {')
      ..writeln(
        '    emit(state.copyWith(status: $statusType.loading, errorMessage: null));',
      )
      ..writeln(
        '    final result = await getIt<${operation.pascal}Usecase>()(${operation.hasParams ? 'event.params' : useCaseArgument});',
      )
      ..writeln('    switch (result) {')
      ..writeln('      case Success(:final data):')
      ..writeln('        ${operation.camel}Result = data;')
      ..writeln(
        '        emit(state.copyWith(status: $statusType.success));',
      )
      ..writeln('      case Failure(:final message):')
      ..writeln(
        '        emit(state.copyWith(status: $statusType.error, errorMessage: message));',
      )
      ..writeln('    }')
      ..writeln('  }');
    return;
  }

  out
    ..writeln()
    ..writeln('  Future<void> ${operation.camel}($paramsDeclaration) async {');
  if (stateManagement == 'provider') {
    out
      ..writeln(
        '    _state = _state.copyWith(status: $statusType.loading, errorMessage: null);',
      )
      ..writeln('    notifyListeners();');
  } else if (stateManagement == 'riverpod') {
    out.writeln(
      '    state = state.copyWith(status: $statusType.loading, errorMessage: null);',
    );
  } else {
    out.writeln(
      '    emit(state.copyWith(status: $statusType.loading, errorMessage: null));',
    );
  }
  out
    ..writeln(
      '    final result = await getIt<${operation.pascal}Usecase>()($useCaseArgument);',
    )
    ..writeln('    switch (result) {')
    ..writeln('      case Success(:final data):')
    ..writeln('        ${operation.camel}Result = data;');
  if (stateManagement == 'provider') {
    out.writeln(
      '        _state = _state.copyWith(status: $statusType.success);',
    );
  } else if (stateManagement == 'riverpod') {
    out.writeln(
      '        state = state.copyWith(status: $statusType.success);',
    );
  } else {
    out.writeln(
      '        emit(state.copyWith(status: $statusType.success));',
    );
  }
  out.writeln('      case Failure(:final message):');
  if (stateManagement == 'provider') {
    out.writeln(
      '        _state = _state.copyWith(status: $statusType.error, errorMessage: message);',
    );
  } else if (stateManagement == 'riverpod') {
    out.writeln(
      '        state = state.copyWith(status: $statusType.error, errorMessage: message);',
    );
  } else {
    out.writeln(
      '        emit(state.copyWith(status: $statusType.error, errorMessage: message));',
    );
  }
  out.writeln('    }');
  if (stateManagement == 'provider') out.writeln('    notifyListeners();');
  out.writeln('  }');
}

Future<int> _writeOpenApiTests({
  required Directory root,
  required Logger logger,
  required String feature,
  required List<_OperationSpec> operations,
  required bool force,
}) async {
  var code = await addFeatureTests(
    feature: feature,
    logger: logger,
    root: root,
    force: force,
  );
  if (code != 0) return code;
  for (final operation in operations) {
    code = await addFunctionTest(
      feature: feature,
      functionName: operation.snake,
      logger: logger,
      root: root,
      force: force,
    );
    if (code != 0) return code;
    if (operation.response.hasClasses) {
      _writeSerializationTest(
        root: root,
        feature: feature,
        operation: operation,
        schema: operation.response,
        suffix: 'response',
      );
    }
    if (operation.request?.hasClasses == true) {
      _writeSerializationTest(
        root: root,
        feature: feature,
        operation: operation,
        schema: operation.request!,
        suffix: 'payload',
      );
    }
  }
  return 0;
}

void _writeSerializationTest({
  required Directory root,
  required String feature,
  required _OperationSpec operation,
  required _SchemaOutput schema,
  required String suffix,
}) {
  final projectName = detectProjectName(root: root);
  final rootClass = schema.rootClassName;
  if (rootClass == null) return;
  var sample = schema.sampleJson;
  if (schema.kind == _ValueKind.objectList && sample is List) {
    sample = sample.isEmpty ? <String, dynamic>{} : sample.first;
  }
  if (sample is! Map) return;
  final encoded = jsonEncode(sample);
  final content = """
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/features/$feature/data/remote/dto/${operation.snake}_${suffix}_dto.dart';

void main() {
  test('$rootClass DTO serializes an OpenAPI-shaped value', () {
    final json = jsonDecode(r'''$encoded''') as Map<String, dynamic>;
    final dto = ${rootClass}Dto.fromJson(json);

    expect(dto.toJson(), isA<Map<String, dynamic>>());
  });
}
""";
  _writeGenerated(
    p.join(
      root.path,
      'test',
      'features',
      feature,
      'data',
      'remote',
      'dto',
      '${operation.snake}_${suffix}_dto_test.dart',
    ),
    content,
  );
}

String _escape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

String _docText(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
