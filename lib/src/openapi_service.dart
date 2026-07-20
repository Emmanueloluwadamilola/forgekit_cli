import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config_service.dart';
import 'json_to_dart.dart';
import 'route_wiring_service.dart';
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

const _maximumOpenApiDocuments = 64;
const _maximumOpenApiDocumentBytes = 5 * 1024 * 1024;

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
    required this.securitySchemes,
    required this.defaultSecurity,
    required Uri entryUri,
    required Map<Uri, Map<String, dynamic>> sources,
    required Map<Map<String, dynamic>, Uri> origins,
  })  : _entryUri = entryUri,
        _sources = sources,
        _origins = origins;

  final String version;
  final String title;
  final String? serverUrl;
  final List<OpenApiOperation> operations;
  final Map<String, OpenApiSecurityScheme> securitySchemes;
  final List<OpenApiSecurityRequirement> defaultSecurity;
  final Uri _entryUri;
  final Map<Uri, Map<String, dynamic>> _sources;
  final Map<Map<String, dynamic>, Uri> _origins;

  Map<String, dynamic> resolve(Map<String, dynamic> value) {
    return _resolve(value, <String>{});
  }

  String referenceKey(Map<String, dynamic> value) {
    final ref = value[r'$ref'];
    if (ref is! String) return '';
    final origin = _origins[value] ?? _entryUri;
    return origin.resolve(ref).toString();
  }

  Map<String, dynamic> _resolve(
    Map<String, dynamic> value,
    Set<String> chain,
  ) {
    final ref = value[r'$ref'];
    if (ref is! String) return value;
    final origin = _origins[value] ?? _entryUri;
    final targetUri = origin.resolve(ref);
    final key = targetUri.toString();
    if (!chain.add(key)) {
      throw OpenApiException(
        'Cyclic OpenAPI reference cannot be resolved directly: $key',
      );
    }

    final documentUri = targetUri.removeFragment();
    Object? current = _sources[documentUri];
    if (current == null) {
      throw OpenApiException(
        'OpenAPI reference document was not loaded: $documentUri',
      );
    }
    final fragment = targetUri.fragment;
    if (fragment.isNotEmpty && !fragment.startsWith('/')) {
      throw OpenApiException(
        'OpenAPI references must use a JSON Pointer fragment: $key',
      );
    }
    for (final encoded in fragment.isEmpty
        ? const <String>[]
        : fragment.substring(1).split('/')) {
      final segment = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is! Map<String, dynamic> || !current.containsKey(segment)) {
        throw OpenApiException('OpenAPI reference does not exist: $key');
      }
      current = current[segment];
    }
    if (current is! Map<String, dynamic>) {
      throw OpenApiException('OpenAPI reference is not an object: $key');
    }
    final resolved = _resolve(current, chain);
    if (value.length == 1) return resolved;
    return <String, dynamic>{
      ...resolved,
      for (final entry in value.entries)
        if (entry.key != r'$ref') entry.key: entry.value,
    };
  }
}

enum OpenApiSecurityType { apiKey, http, oauth2, openIdConnect, mutualTls }

class OpenApiSecurityScheme {
  const OpenApiSecurityScheme({
    required this.name,
    required this.type,
    required this.parameterName,
    required this.location,
    required this.scheme,
    required this.bearerFormat,
  });

  final String name;
  final OpenApiSecurityType type;
  final String? parameterName;
  final String? location;
  final String? scheme;
  final String? bearerFormat;
}

class OpenApiSecurityRequirement {
  const OpenApiSecurityRequirement(this.schemes);

  final Map<String, List<String>> schemes;

  bool get allowsAnonymous => schemes.isEmpty;
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
    required this.security,
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
  final List<OpenApiSecurityRequirement> security;
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

/// Loads a local or remote OpenAPI entry document and every referenced
/// document before parsing it. Remote descriptions may reference HTTPS
/// documents on the same origin. Local descriptions may reference files that
/// remain under the entry document's directory.
Future<OpenApiDocument> loadOpenApiDocument(
  String source, {
  bool allowRemoteReferences = false,
}) async {
  final entryUri = _openApiSourceUri(source).removeFragment();
  final sources = <Uri, Map<String, dynamic>>{};
  final loading = <Uri>{};
  await _loadOpenApiDocuments(
    entryUri: entryUri,
    documentUri: entryUri,
    sources: sources,
    loading: loading,
    allowRemoteReferences: allowRemoteReferences,
  );
  return _parseOpenApiSources(entryUri, sources);
}

OpenApiDocument parseOpenApi(String contents) {
  final entryUri = Uri.parse('memory:/openapi.yaml');
  return _parseOpenApiSources(
    entryUri,
    {entryUri: _decodeOpenApi(contents)},
  );
}

OpenApiDocument _parseOpenApiSources(
  Uri entryUri,
  Map<Uri, Map<String, dynamic>> sources,
) {
  final plain = sources[entryUri];
  if (plain == null) {
    throw const OpenApiException('The OpenAPI entry document was not loaded.');
  }
  final origins = HashMap<Map<String, dynamic>, Uri>.identity();
  for (final entry in sources.entries) {
    _recordMapOrigins(entry.value, entry.key, origins);
  }
  return _parseOpenApiMap(
    plain,
    entryUri: entryUri,
    sources: sources,
    origins: origins,
  );
}

Map<String, dynamic> _decodeOpenApi(String contents) {
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
  return plain;
}

OpenApiDocument _parseOpenApiMap(
  Map<String, dynamic> plain, {
  required Uri entryUri,
  required Map<Uri, Map<String, dynamic>> sources,
  required Map<Map<String, dynamic>, Uri> origins,
}) {
  final version = plain['openapi'];
  if (version is! String ||
      !(version.startsWith('3.0.') || version.startsWith('3.1.'))) {
    throw OpenApiException(
      'Expected an OpenAPI 3.0 or 3.1 document, received '
      '${version ?? 'no version'}.',
    );
  }
  if (version.startsWith('3.1.') && _containsJsonSchemaId(plain)) {
    throw const OpenApiException(
      'OpenAPI 3.1 JSON Schema `\$id` base-URI semantics are not supported. '
      'Resolve or remove `\$id` values before importing so references cannot '
      'be interpreted against the wrong document.',
    );
  }

  final info = _mapOrEmpty(plain['info']);
  final title = info['title'] is String ? info['title'] as String : 'API';
  final servers = _listOrEmpty(plain['servers']);
  final firstServer = _firstOrNull(
    servers.whereType<Map<String, dynamic>>(),
  );
  final serverUrl = _expandServerUrl(firstServer);
  final securitySchemes = <String, OpenApiSecurityScheme>{};
  final document = OpenApiDocument(
    version: version,
    title: title,
    serverUrl: serverUrl,
    operations: [],
    securitySchemes: securitySchemes,
    defaultSecurity: const [],
    entryUri: entryUri,
    sources: sources,
    origins: origins,
  );
  securitySchemes.addAll(_parseSecuritySchemes(document, plain['components']));
  final defaultSecurity = _parseSecurityRequirements(
    document,
    plain['security'],
    securitySchemes,
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
      final security = operation.containsKey('security')
          ? _parseSecurityRequirements(
              document,
              operation['security'],
              securitySchemes,
            )
          : defaultSecurity;
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
          security: security,
        ),
      );
    }
  }
  if (operations.isEmpty) {
    throw const OpenApiException(
      'The OpenAPI document does not contain supported HTTP operations.',
    );
  }

  final parsedDocument = OpenApiDocument(
    version: version,
    title: title,
    serverUrl: serverUrl,
    operations: operations,
    securitySchemes: securitySchemes,
    defaultSecurity: defaultSecurity,
    entryUri: entryUri,
    sources: sources,
    origins: origins,
  );
  for (final operation in parsedDocument.operations) {
    _buildOperation(parsedDocument, operation);
  }
  return parsedDocument;
}

String? _expandServerUrl(Map<String, dynamic>? server) {
  final rawUrl = server?['url'];
  if (rawUrl is! String || rawUrl.trim().isEmpty) return null;
  final variables = _mapOrEmpty(server?['variables']);
  return rawUrl.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
    final name = match.group(1)!;
    final variable = _mapOrEmpty(variables[name]);
    final defaultValue = variable['default'];
    if (defaultValue is! String) {
      throw OpenApiException(
        'OpenAPI server variable "$name" requires a string default value.',
      );
    }
    return defaultValue;
  });
}

Uri _openApiSourceUri(String source) {
  final parsed = Uri.tryParse(source);
  if (parsed != null && parsed.scheme == 'http') {
    throw const OpenApiException(
      'Remote OpenAPI documents require HTTPS. Download trusted local HTTP '
      'documents first and import the local file.',
    );
  }
  if (parsed != null && parsed.scheme == 'https') {
    if (parsed.userInfo.isNotEmpty) {
      throw const OpenApiException(
        'OpenAPI URLs must not contain embedded credentials.',
      );
    }
    if (_containsSensitiveUrlQuery(parsed)) {
      throw const OpenApiException(
        'OpenAPI URLs must not contain credential-like query parameters. '
        'Download the document with your authenticated client and import the '
        'local file instead.',
      );
    }
    if (parsed.fragment.isNotEmpty) {
      throw const OpenApiException(
        'The OpenAPI entry URL must identify a document, not a fragment.',
      );
    }
    return parsed;
  }
  if (parsed != null && parsed.scheme == 'file') {
    return File.fromUri(parsed).absolute.uri;
  }
  return File(source).absolute.uri;
}

Future<void> _loadOpenApiDocuments({
  required Uri entryUri,
  required Uri documentUri,
  required Map<Uri, Map<String, dynamic>> sources,
  required Set<Uri> loading,
  required bool allowRemoteReferences,
}) async {
  final canonical = documentUri.removeFragment();
  if (sources.containsKey(canonical) || !loading.add(canonical)) return;
  if (sources.length >= _maximumOpenApiDocuments) {
    throw const OpenApiException(
      'OpenAPI input exceeds the 64-document safety limit.',
    );
  }
  final contents = await _readOpenApiUri(canonical);
  final document = _decodeOpenApi(contents);
  sources[canonical] = document;

  try {
    for (final ref in _collectOpenApiReferences(document)) {
      final target = canonical.resolve(ref);
      final targetDocument = target.removeFragment();
      if (targetDocument == canonical) continue;
      _validateExternalReference(
        entryUri,
        targetDocument,
        allowRemoteReferences: allowRemoteReferences,
      );
      await _loadOpenApiDocuments(
        entryUri: entryUri,
        documentUri: targetDocument,
        sources: sources,
        loading: loading,
        allowRemoteReferences: allowRemoteReferences,
      );
    }
  } finally {
    loading.remove(canonical);
  }
}

Future<String> _readOpenApiUri(Uri uri) async {
  if (uri.scheme == 'https') {
    if (uri.userInfo.isNotEmpty) {
      throw const OpenApiException(
        'OpenAPI reference URLs must not contain embedded credentials.',
      );
    }
    if (_containsSensitiveUrlQuery(uri)) {
      throw const OpenApiException(
        'OpenAPI reference URLs must not contain credential-like query '
        'parameters.',
      );
    }
    return _readRemoteOpenApiUri(uri);
  }
  if (uri.scheme == 'file') {
    final file = File.fromUri(uri);
    if (!file.existsSync()) {
      throw OpenApiException('OpenAPI file not found: ${file.path}');
    }
    if (file.lengthSync() > _maximumOpenApiDocumentBytes) {
      throw OpenApiException(
        'OpenAPI document exceeds the 5 MiB safety limit: ${file.path}',
      );
    }
    return file.readAsString();
  }
  throw OpenApiException(
    'Unsupported OpenAPI reference scheme "${uri.scheme}" in $uri.',
  );
}

void _validateExternalReference(
  Uri entryUri,
  Uri target, {
  required bool allowRemoteReferences,
}) {
  if (target.userInfo.isNotEmpty) {
    throw const OpenApiException(
      'OpenAPI reference URLs must not contain embedded credentials.',
    );
  }
  if (_containsSensitiveUrlQuery(target)) {
    throw const OpenApiException(
      'OpenAPI reference URLs must not contain credential-like query '
      'parameters.',
    );
  }
  if (entryUri.scheme == 'https') {
    if (target.scheme != entryUri.scheme ||
        target.host != entryUri.host ||
        target.port != entryUri.port) {
      throw OpenApiException(
        'Remote OpenAPI documents may only reference the same origin. '
        'Rejected: $target',
      );
    }
    return;
  }
  if (target.scheme == 'https') {
    if (!allowRemoteReferences) {
      throw OpenApiException(
        'Local OpenAPI documents may not fetch remote references by default. '
        'Download the referenced file locally or explicitly allow remote '
        'references. Rejected: $target',
      );
    }
    return;
  }
  if (target.scheme != 'file') {
    throw OpenApiException(
      'Local OpenAPI documents may reference local files or HTTPS documents. '
      'Rejected: $target',
    );
  }
  final root = p.dirname(File.fromUri(entryUri).absolute.path);
  final path = File.fromUri(target).absolute.path;
  if (path != root && !p.isWithin(root, path)) {
    throw OpenApiException(
      'Local OpenAPI reference escapes the entry document directory: $path',
    );
  }
}

Future<String> _readRemoteOpenApiUri(Uri initialUri) async {
  final client = http.Client();
  var current = initialUri;
  try {
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await client.send(request);
      if (response.isRedirect) {
        await response.stream.drain<void>();
        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          throw OpenApiException(
            'OpenAPI redirect from $current did not include a location.',
          );
        }
        if (redirects == 5) {
          throw OpenApiException(
            'OpenAPI download exceeded the 5-redirect safety limit: '
            '$initialUri',
          );
        }
        final next = current.resolve(location);
        if (next.scheme != 'https' ||
            next.userInfo.isNotEmpty ||
            _containsSensitiveUrlQuery(next) ||
            !_sameOrigin(initialUri, next)) {
          throw OpenApiException(
            'OpenAPI redirects must remain on the original HTTPS origin. '
            'Rejected: $next',
          );
        }
        current = next;
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw OpenApiException(
          'Could not download OpenAPI document $current '
          '(${response.statusCode}).',
        );
      }

      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.stream) {
        length += chunk.length;
        if (length > _maximumOpenApiDocumentBytes) {
          throw OpenApiException(
            'OpenAPI document exceeds the 5 MiB safety limit: $current',
          );
        }
        bytes.add(chunk);
      }
      try {
        return utf8.decode(bytes.takeBytes());
      } on FormatException {
        throw OpenApiException(
          'OpenAPI document is not valid UTF-8: $current',
        );
      }
    }
    throw OpenApiException('Could not download OpenAPI document $initialUri.');
  } finally {
    client.close();
  }
}

bool _sameOrigin(Uri first, Uri second) =>
    first.scheme == second.scheme &&
    first.host == second.host &&
    first.port == second.port;

bool _containsSensitiveUrlQuery(Uri uri) => uri.queryParameters.keys.any(
      (key) => RegExp(
        r'(token|secret|signature|credential|password|api[-_]?key|auth)',
        caseSensitive: false,
      ).hasMatch(key),
    );

Iterable<String> _collectOpenApiReferences(Object? value) sync* {
  if (value is Map<String, dynamic>) {
    final ref = value[r'$ref'];
    if (ref is String && ref.trim().isNotEmpty) yield ref;
    for (final child in value.values) {
      yield* _collectOpenApiReferences(child);
    }
  } else if (value is List<dynamic>) {
    for (final child in value) {
      yield* _collectOpenApiReferences(child);
    }
  }
}

void _recordMapOrigins(
  Object? value,
  Uri origin,
  Map<Map<String, dynamic>, Uri> origins,
) {
  if (value is Map<String, dynamic>) {
    origins[value] = origin;
    for (final child in value.values) {
      _recordMapOrigins(child, origin, origins);
    }
  } else if (value is List<dynamic>) {
    for (final child in value) {
      _recordMapOrigins(child, origin, origins);
    }
  }
}

Map<String, OpenApiSecurityScheme> _parseSecuritySchemes(
  OpenApiDocument document,
  Object? componentsValue,
) {
  final components = _mapOrEmpty(componentsValue);
  final values = _mapOrEmpty(components['securitySchemes']);
  final schemes = <String, OpenApiSecurityScheme>{};
  for (final entry in values.entries) {
    if (entry.value is! Map<String, dynamic>) {
      throw OpenApiException(
        'OpenAPI security scheme "${entry.key}" must be an object.',
      );
    }
    final value = document.resolve(entry.value as Map<String, dynamic>);
    final type = value['type'];
    switch (type) {
      case 'apiKey':
        final parameterName = value['name'];
        final location = value['in'];
        if (parameterName is! String ||
            location is! String ||
            !{'header', 'query', 'cookie'}.contains(location)) {
          throw OpenApiException(
            'API-key security scheme "${entry.key}" requires a name and a '
            'header, query, or cookie location.',
          );
        }
        schemes[entry.key] = OpenApiSecurityScheme(
          name: entry.key,
          type: OpenApiSecurityType.apiKey,
          parameterName: parameterName,
          location: location,
          scheme: null,
          bearerFormat: null,
        );
      case 'http':
        final scheme = value['scheme'];
        if (scheme is! String || scheme.trim().isEmpty) {
          throw OpenApiException(
            'HTTP security scheme "${entry.key}" requires `scheme`.',
          );
        }
        schemes[entry.key] = OpenApiSecurityScheme(
          name: entry.key,
          type: OpenApiSecurityType.http,
          parameterName: 'Authorization',
          location: 'header',
          scheme: scheme.toLowerCase(),
          bearerFormat: value['bearerFormat'] as String?,
        );
      case 'oauth2':
        if (_mapOrEmpty(value['flows']).isEmpty) {
          throw OpenApiException(
            'OAuth2 security scheme "${entry.key}" requires `flows`.',
          );
        }
        schemes[entry.key] = OpenApiSecurityScheme(
          name: entry.key,
          type: OpenApiSecurityType.oauth2,
          parameterName: 'Authorization',
          location: 'header',
          scheme: 'bearer',
          bearerFormat: null,
        );
      case 'openIdConnect':
        if (value['openIdConnectUrl'] is! String) {
          throw OpenApiException(
            'OpenID Connect security scheme "${entry.key}" requires '
            '`openIdConnectUrl`.',
          );
        }
        schemes[entry.key] = OpenApiSecurityScheme(
          name: entry.key,
          type: OpenApiSecurityType.openIdConnect,
          parameterName: 'Authorization',
          location: 'header',
          scheme: 'bearer',
          bearerFormat: null,
        );
      case 'mutualTLS':
        schemes[entry.key] = OpenApiSecurityScheme(
          name: entry.key,
          type: OpenApiSecurityType.mutualTls,
          parameterName: null,
          location: null,
          scheme: null,
          bearerFormat: null,
        );
      default:
        throw OpenApiException(
          'Unsupported OpenAPI security scheme type "$type" for '
          '"${entry.key}".',
        );
    }
  }
  return schemes;
}

List<OpenApiSecurityRequirement> _parseSecurityRequirements(
  OpenApiDocument document,
  Object? value,
  Map<String, OpenApiSecurityScheme> schemes,
) {
  if (value == null) return const [];
  final values = _listOrEmpty(value);
  final requirements = <OpenApiSecurityRequirement>[];
  for (final raw in values) {
    if (raw is! Map<String, dynamic>) {
      throw const OpenApiException(
        'OpenAPI security requirements must be objects.',
      );
    }
    final requirement = <String, List<String>>{};
    for (final entry in raw.entries) {
      if (!schemes.containsKey(entry.key)) {
        throw OpenApiException(
          'OpenAPI security requirement references undefined scheme '
          '"${entry.key}".',
        );
      }
      final scopes = _listOrEmpty(entry.value);
      if (scopes.any((scope) => scope is! String)) {
        throw OpenApiException(
          'Security scopes for "${entry.key}" must be strings.',
        );
      }
      requirement[entry.key] = scopes.cast<String>();
    }
    requirements.add(OpenApiSecurityRequirement(requirement));
  }
  return requirements;
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
    if (!{'path', 'query', 'header', 'cookie'}.contains(location)) continue;
    var schema = _mapOrEmpty(parameter['schema']);
    if (schema.isEmpty) {
      schema = _schemaFromContent(parameter['content']);
    }
    final resolvedSchema = document.resolve(schema);
    final type = _effectiveSchemaType(resolvedSchema);
    final defaultStyle = switch (location) {
      'path' || 'header' => 'simple',
      'query' || 'cookie' => 'form',
      _ => null,
    };
    final style = parameter['style'] ?? defaultStyle;
    if (style != defaultStyle) {
      throw OpenApiException(
        'Parameter "$name" uses unsupported $location style "$style". '
        'ForgeKit supports the OpenAPI default $defaultStyle style.',
      );
    }
    if ((location == 'path' || location == 'header') &&
        (type == 'array' || type == 'object')) {
      throw OpenApiException(
        '${pascalCase(location)} parameter "$name" must use a scalar schema.',
      );
    }
    if (location == 'query' && type == 'object') {
      throw OpenApiException(
        'Query parameter "$name" uses an object schema. Deep-object query '
        'serialization is not supported.',
      );
    }
    if (location == 'query' &&
        type == 'array' &&
        parameter['explode'] == false) {
      throw OpenApiException(
        'Query array parameter "$name" uses explode: false. CSV query array '
        'serialization is not supported.',
      );
    }
    if (location == 'cookie') {
      if (type == 'array' || type == 'object') {
        throw OpenApiException(
          'Cookie parameter "$name" must use a scalar schema. Array and '
          'object cookie serialization is not supported.',
        );
      }
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
  final content = _jsonContentSchema(
    body['content'],
    context: 'request body',
  );
  if (content == null) return null;
  return _BodySpec(
    schema: content.schema,
    required: body['required'] == true,
  );
}

_ResponseSpec? _parseResponse(OpenApiDocument document, Object? value) {
  final responses = _mapOrEmpty(value);
  if (responses.isEmpty) return null;
  final successful = responses.entries
      .where((entry) => RegExp(r'^2(?:[0-9][0-9]|XX)$').hasMatch(entry.key))
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final selected = successful.isNotEmpty
      ? successful.first
      : _firstOrNull(
          responses.entries.where((entry) => entry.key == 'default'),
        );
  if (selected == null || selected.value is! Map<String, dynamic>) return null;
  final response = document.resolve(selected.value as Map<String, dynamic>);
  final content = _jsonContentSchema(
    response['content'],
    context: 'response ${selected.key}',
  );
  return _ResponseSpec(
    status: selected.key,
    schema: content?.schema.isEmpty == true ? null : content?.schema,
  );
}

_ContentSchema? _jsonContentSchema(
  Object? value, {
  required String context,
}) {
  final content = _mapOrEmpty(value);
  if (content.isEmpty) return null;
  final selected = _firstOrNull(
        content.entries.where((entry) => entry.key == 'application/json'),
      ) ??
      _firstOrNull(
        content.entries.where((entry) => entry.key.endsWith('+json')),
      ) ??
      _firstOrNull(content.entries.where((entry) => entry.key == '*/*'));
  if (selected == null) {
    final mediaTypes = content.keys.toList()..sort();
    throw OpenApiException(
      'Unsupported OpenAPI $context media type(s): '
      '${mediaTypes.join(', ')}. ForgeKit generates typed JSON APIs; use '
      'application/json, a +json media type, or */*.',
    );
  }
  return _ContentSchema(
    schema: _mapOrEmpty(_mapOrEmpty(selected.value)['schema']),
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

class _ContentSchema {
  const _ContentSchema({required this.schema});

  final Map<String, dynamic> schema;
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
  bool allowRemoteReferences = false,
}) async {
  final progress = logger.progress('Reading OpenAPI document');
  late final OpenApiDocument document;
  try {
    document = await loadOpenApiDocument(
      source,
      allowRemoteReferences: allowRemoteReferences,
    );
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
      registerFeatureRoute(
        root: root,
        config: config,
        projectName: projectName,
        feature: feature,
      );
      if (generateTests) {
        final testCode = await _writeOpenApiTests(
          root: root,
          feature: feature,
          operations: specs,
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
    } on RouteWiringException catch (error) {
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
      security: operation.security,
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
    final refKey = ref is String ? document.referenceKey(raw) : '';
    if (refKey.isNotEmpty && _referenceNames.containsKey(refKey)) {
      final className = _referenceNames[refKey]!;
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
      if (properties.isEmpty && schema.containsKey('additionalProperties')) {
        return const _CompiledType(
          modelType: 'Map<String, dynamic>',
          dtoType: 'Map<String, dynamic>',
          kind: _ValueKind.primitive,
        );
      }
      final name = pascalCase(preferredName);
      final className = name.isEmpty ? 'ApiModel' : name;
      if (refKey.isNotEmpty) _referenceNames[refKey] = className;
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
    if (compositions.isNotEmpty) {
      final merged = <String, dynamic>{...resolved}..remove('allOf');
      final properties = <String, dynamic>{};
      final required = <String>{};
      for (final part in compositions) {
        if (part is! Map<String, dynamic>) continue;
        final normalized = _normalizeSchema(part);
        properties.addAll(_mapOrEmpty(normalized['properties']));
        required.addAll(
          _listOrEmpty(normalized['required']).whereType<String>(),
        );
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
      resolved = merged;
    }

    final unionKey = _listOrEmpty(resolved['oneOf']).isNotEmpty
        ? 'oneOf'
        : _listOrEmpty(resolved['anyOf']).isNotEmpty
            ? 'anyOf'
            : null;
    if (unionKey == null) return resolved;
    final variants = _listOrEmpty(resolved[unionKey])
        .whereType<Map<String, dynamic>>()
        .map(_normalizeSchema)
        .toList();
    if (variants.isEmpty) return resolved;
    final objectVariants = variants
        .where(
          (variant) =>
              variant['type'] == 'object' ||
              _mapOrEmpty(variant['properties']).isNotEmpty,
        )
        .toList();
    if (objectVariants.length == variants.length) {
      final merged = <String, dynamic>{...resolved}
        ..remove('oneOf')
        ..remove('anyOf')
        ..['type'] = 'object';
      final properties = <String, dynamic>{};
      Set<String>? requiredIntersection;
      for (final variant in objectVariants) {
        for (final property in _mapOrEmpty(variant['properties']).entries) {
          final existing = properties[property.key];
          if (existing != null &&
              !_equivalentSchema(existing, property.value)) {
            throw OpenApiException(
              'OpenAPI $unionKey variants define incompatible schemas for '
              'property "${property.key}". ForgeKit will not choose one '
              'variant silently.',
            );
          }
          properties[property.key] = property.value;
        }
        final required =
            _listOrEmpty(variant['required']).whereType<String>().toSet();
        requiredIntersection = requiredIntersection == null
            ? required
            : requiredIntersection.intersection(required);
      }
      properties.addAll(_mapOrEmpty(merged['properties']));
      merged['properties'] = properties;
      if (requiredIntersection?.isNotEmpty == true) {
        merged['required'] = requiredIntersection!.toList();
      }
      return merged;
    }
    final types = variants
        .map((variant) => _effectiveSchemaType(variant))
        .whereType<String>()
        .toSet();
    final merged = <String, dynamic>{...resolved}
      ..remove('oneOf')
      ..remove('anyOf');
    if (types.length == 1) merged['type'] = types.single;
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

bool _containsJsonSchemaId(Object? value) {
  if (value is Map<String, dynamic>) {
    if (value.containsKey(r'$id')) return true;
    return value.values.any(_containsJsonSchemaId);
  }
  if (value is List) return value.any(_containsJsonSchemaId);
  return false;
}

bool _equivalentSchema(Object? first, Object? second) =>
    jsonEncode(_canonicalJson(first)) == jsonEncode(_canonicalJson(second));

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalJson).toList();
  return value;
}

String _primitiveType(Map<String, dynamic> schema) {
  return switch (_effectiveSchemaType(schema)) {
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

String? _effectiveSchemaType(Map<String, dynamic> schema) {
  final type = schema['type'];
  if (type is String) return type;
  if (type is List) {
    return type.whereType<String>().firstWhere(
          (value) => value != 'null',
          orElse: () => 'null',
        );
  }
  final values = _listOrEmpty(schema['enum']);
  if (values.isEmpty && schema.containsKey('const')) {
    return _typeForJsonValue(schema['const']);
  }
  final inferred = values.map(_typeForJsonValue).whereType<String>().toSet();
  return inferred.length == 1 ? inferred.single : null;
}

String? _typeForJsonValue(Object? value) => switch (value) {
      String() => 'string',
      int() => 'integer',
      double() => 'number',
      bool() => 'boolean',
      List() => 'array',
      Map() => 'object',
      _ => null,
    };

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
    required this.isSecurity,
  });

  final String apiName;
  final String dartName;
  final String type;
  final bool required;
  final String location;
  final bool isSecurity;
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
      isSecurity: false,
    );
  }).toList();
  final existingInputs = {
    for (final input in inputs) '${input.location}:${input.apiName}',
  };
  for (final input in _securityInputs(document, operation, usedNames)) {
    if (existingInputs.add('${input.location}:${input.apiName}')) {
      inputs.add(input);
    }
  }
  final bodyName = usedNames.contains('payload') ? 'body' : 'payload';
  final bodyField = request == null
      ? null
      : _InputField(
          apiName: 'body',
          dartName: bodyName,
          type: _optionalType(request.modelType, operation.requestRequired),
          required: operation.requestRequired,
          location: 'body',
          isSecurity: false,
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

List<_InputField> _securityInputs(
  OpenApiDocument document,
  OpenApiOperation operation,
  Set<String> usedNames,
) {
  if (operation.security.isEmpty ||
      operation.security.any((requirement) => requirement.allowsAnonymous)) {
    // An empty alternative makes authentication optional, but optional
    // credential inputs are still useful for callers that authenticate.
  }
  final referenced = operation.security
      .expand((requirement) => requirement.schemes.keys)
      .toSet();
  final schemes = referenced
      .map((name) => document.securitySchemes[name])
      .whereType<OpenApiSecurityScheme>()
      .toList();
  final inputs = <_InputField>[];

  final authorizationSchemes = schemes
      .where(
        (scheme) =>
            scheme.type == OpenApiSecurityType.http ||
            scheme.type == OpenApiSecurityType.oauth2 ||
            scheme.type == OpenApiSecurityType.openIdConnect,
      )
      .toList();
  if (authorizationSchemes.isNotEmpty) {
    final required = _securityChannelRequired(
      operation.security,
      authorizationSchemes.map((scheme) => scheme.name).toSet(),
    );
    inputs.add(
      _InputField(
        apiName: 'Authorization',
        dartName: _uniqueInputName('authorization', usedNames),
        type: _optionalType('String', required),
        required: required,
        location: 'header',
        isSecurity: true,
      ),
    );
  }

  for (final scheme in schemes.where(
    (scheme) => scheme.type == OpenApiSecurityType.apiKey,
  )) {
    final parameterName = scheme.parameterName!;
    final location = scheme.location!;
    final required = _securityChannelRequired(
      operation.security,
      {scheme.name},
    );
    final baseName = location == 'cookie'
        ? '${camelCase(scheme.name)}Cookie'
        : camelCase(scheme.name);
    inputs.add(
      _InputField(
        apiName: parameterName,
        dartName: _uniqueInputName(baseName, usedNames),
        type: _optionalType('String', required),
        required: required,
        location: location,
        isSecurity: true,
      ),
    );
  }
  return inputs;
}

bool _securityChannelRequired(
  List<OpenApiSecurityRequirement> requirements,
  Set<String> acceptedSchemes,
) {
  if (requirements.isEmpty ||
      requirements.any((requirement) => requirement.allowsAnonymous)) {
    return false;
  }
  return requirements.every(
    (requirement) => requirement.schemes.keys.any(acceptedSchemes.contains),
  );
}

String _uniqueInputName(String preferred, Set<String> usedNames) {
  var candidate = _safeIdentifier(preferred.isEmpty ? 'credential' : preferred);
  var suffix = 2;
  while (!usedNames.add(candidate)) {
    candidate = '$preferred${suffix++}';
  }
  return candidate;
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
        _emitModels(
          operation.response.classes,
          dtoImport:
              'package:$projectName/features/$feature/data/remote/dto/${operation.snake}_response_dto.dart',
          withToDto: true,
        ),
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
          modelImport:
              'package:$projectName/features/$feature/domain/entity/payload/${operation.snake}_payload.dart',
          withToModel: true,
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
    if (field.isSecurity) {
      out.writeln(
        '  /// Runtime credential for the OpenAPI `${field.apiName}` input. '
        'Never hardcode it in generated source.',
      );
    }
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
          ? "@RestApi(baseUrl: '${_escape(encodeRetrofitUrlLiteral(baseUrl!.trim()))}')"
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
    if (operation.operation.security.isNotEmpty) {
      final metadata = jsonEncode([
        for (final requirement in operation.operation.security)
          requirement.schemes,
      ]);
      out.writeln(
        "  @Extra({'forgekit.security': '${_escape(metadata)}'})",
      );
    }
    out.writeln(
      "  @${operation.operation.method}('${_escape(encodeRetrofitUrlLiteral(operation.operation.path))}')",
    );
    final apiInputs = <String>[];
    for (final input in operation.inputs.where(
      (input) => input.location != 'cookie',
    )) {
      final annotation = switch (input.location) {
        'path' => 'Path',
        'header' => 'Header',
        _ => 'Query',
      };
      apiInputs.add(
        "@$annotation('${_escape(input.apiName)}') ${input.type} ${input.dartName}",
      );
    }
    if (operation.inputs.any((input) => input.location == 'cookie')) {
      apiInputs.add("@Header('Cookie') String? forgekitCookieHeader");
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
      for (final input in operation.inputs.where(
        (input) => input.location != 'cookie',
      ))
        'params.${input.dartName}',
      if (operation.inputs.any((input) => input.location == 'cookie'))
        _cookieHeaderExpression(operation.inputs),
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

String _cookieHeaderExpression(List<_InputField> inputs) {
  final cookies = inputs.where((input) => input.location == 'cookie').toList();
  final out = StringBuffer('(() {\n')
    ..writeln('        final values = <String>[');
  for (final cookie in cookies) {
    final value = 'params.${cookie.dartName}';
    if (cookie.required) {
      out.writeln(
        "          '${_escape(cookie.apiName)}=\${Uri.encodeComponent($value.toString())}',",
      );
    } else {
      out.writeln(
        "          if ($value != null) '${_escape(cookie.apiName)}=\${Uri.encodeComponent($value.toString())}',",
      );
    }
  }
  out
    ..writeln('        ];')
    ..writeln("        return values.isEmpty ? null : values.join('; ');")
    ..write('      })()');
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
  required String feature,
  required List<_OperationSpec> operations,
}) async {
  for (final operation in operations) {
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
  final encodedLiteral = _dartStringLiteral(encoded);
  final content = """
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/features/$feature/data/remote/dto/${operation.snake}_${suffix}_dto.dart';

void main() {
  test('$rootClass DTO serializes an OpenAPI-shaped value', () {
    final json = jsonDecode($encodedLiteral) as Map<String, dynamic>;
    final dto = ${rootClass}Dto.fromJson(json);
    final model = dto.toModel();

    expect(dto.toJson(), isA<Map<String, dynamic>>());
    expect(model.toDto().toJson(), isA<Map<String, dynamic>>());
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

String _escape(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$')
    .replaceAll('\r', r'\r')
    .replaceAll('\n', r'\n')
    .replaceAll('\t', r'\t');

String _dartStringLiteral(String value) =>
    jsonEncode(value).replaceAll(r'$', r'\$');

String _docText(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
