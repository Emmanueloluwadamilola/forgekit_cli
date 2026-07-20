/// Turns a decoded JSON value into Dart `@JsonSerializable` DTO classes and
/// matching plain domain models (with `toModel()` / `toDto()` mappers).
///
/// Shared by `forgekit add function` and `forgekit add model`.
library;

import 'dart:convert';

/// How a field maps between JSON, the DTO, and the domain model.
enum JsonFieldKind { primitive, object, primitiveList, objectList }

class JsonField {
  JsonField({
    required this.jsonKey,
    required this.dartName,
    required this.kind,
    required this.modelType,
    required this.dtoType,
  });

  final String jsonKey;
  final String dartName;
  final JsonFieldKind kind;
  final String modelType;
  final String dtoType;

  bool get needsKey => jsonKey != dartName;
}

class JsonClass {
  JsonClass(this.name, this.fields);

  /// Domain-model class name. The DTO class name is `"<name>Dto"`.
  final String name;
  final List<JsonField> fields;
}

/// Analyzes [map] into a list of classes ([base] first, nested classes too).
List<JsonClass> analyzeJson(String base, Map<String, dynamic> map) {
  if (!_isDartTypeName(base)) {
    throw FormatException(
      '"$base" cannot be emitted as a Dart class name. Use a name that starts '
      'with a letter and contains only letters or digits.',
    );
  }
  final out = <JsonClass>[];
  _collect(base, map, out);
  final classNames = <String>{};
  for (final jsonClass in out) {
    if (!classNames.add(jsonClass.name)) {
      throw FormatException(
        'JSON properties normalize to the duplicate Dart class name '
        '"${jsonClass.name}".',
      );
    }
  }
  return out;
}

/// Analyzes a non-empty, homogeneous top-level JSON object array.
///
/// A single sample cannot safely infer optional or polymorphic fields, so
/// inconsistent records are rejected with guidance to use OpenAPI instead.
List<JsonClass> analyzeJsonObjects(String base, List<dynamic> values) {
  if (values.isEmpty || values.any((value) => value is! Map)) {
    throw const FormatException(
      'top-level JSON array must contain one or more objects',
    );
  }
  final objects =
      values.cast<Map>().map((value) => value.cast<String, dynamic>()).toList();
  final first = objects.first;
  for (final object in objects.skip(1)) {
    _validateCompatibleObjectSamples(first, object, path: r'$');
  }
  return analyzeJson(base, first);
}

void _validateCompatibleObjectSamples(
  Map<String, dynamic> expected,
  Map<String, dynamic> actual, {
  required String path,
}) {
  if (expected.keys.toSet().length != actual.keys.toSet().length ||
      !actual.keys.toSet().containsAll(expected.keys)) {
    throw FormatException(
      'objects at $path have different fields; use an OpenAPI schema for '
      'optional or polymorphic data',
    );
  }
  for (final key in expected.keys) {
    final first = expected[key];
    final next = actual[key];
    if (first is Map && next is Map) {
      _validateCompatibleObjectSamples(
        first.cast<String, dynamic>(),
        next.cast<String, dynamic>(),
        path: '$path.$key',
      );
      continue;
    }
    final firstType = _sampleType(first);
    final nextType = _sampleType(next);
    final bothNumbers = const {'int', 'double'}.contains(firstType) &&
        const {'int', 'double'}.contains(nextType);
    if (firstType != nextType && !bothNumbers) {
      throw FormatException(
        'values at $path.$key have incompatible sample types '
        '($firstType and $nextType)',
      );
    }
  }
}

String _sampleType(Object? value) => switch (value) {
      null => 'null',
      bool() => 'bool',
      int() => 'int',
      double() => 'double',
      String() => 'String',
      Map() => 'object',
      List() => 'array',
      _ => value.runtimeType.toString(),
    };

void _collect(String base, Map<String, dynamic> map, List<JsonClass> out) {
  final fieldNames = <String, String>{};
  for (final key in map.keys) {
    final name = _safeIdentifier(camelCase(key));
    if (name.isEmpty) {
      throw FormatException(
        'JSON key ${jsonEncode(key)} does not contain characters that can form '
        'a Dart identifier.',
      );
    }
    final previous = fieldNames[name];
    if (previous != null) {
      throw FormatException(
        'JSON keys ${jsonEncode(previous)} and ${jsonEncode(key)} both '
        'normalize to the Dart field "$name".',
      );
    }
    fieldNames[name] = key;
  }
  final fields = <JsonField>[];
  map.forEach((key, value) {
    fields.add(_fieldFor(base, key, value, out));
  });
  out.add(JsonClass(base, fields));
}

JsonField _fieldFor(
  String base,
  String key,
  dynamic value,
  List<JsonClass> out,
) {
  final name = _safeIdentifier(camelCase(key));
  JsonField prim(String type) => JsonField(
        jsonKey: key,
        dartName: name,
        kind: JsonFieldKind.primitive,
        modelType: type,
        dtoType: type,
      );

  if (value is String) return prim('String');
  if (value is bool) return prim('bool');
  if (value is int) return prim('int');
  if (value is double) return prim('double');
  if (value == null) return prim('dynamic');

  if (value is Map) {
    final nested = base + pascalCase(key);
    _collect(nested, value.cast<String, dynamic>(), out);
    return JsonField(
      jsonKey: key,
      dartName: name,
      kind: JsonFieldKind.object,
      modelType: nested,
      dtoType: '${nested}Dto',
    );
  }

  if (value is List) {
    if (value.isEmpty) {
      return JsonField(
        jsonKey: key,
        dartName: name,
        kind: JsonFieldKind.primitiveList,
        modelType: 'List<dynamic>',
        dtoType: 'List<dynamic>',
      );
    }
    final elem = value.first;
    if (elem is Map) {
      if (value.any((item) => item is! Map)) {
        throw FormatException(
          'JSON array ${jsonEncode(key)} mixes objects with other value types. '
          'Use a homogeneous sample array.',
        );
      }
      final expectedKeys = elem.keys.map((item) => item.toString()).toSet();
      for (final item in value.skip(1).cast<Map>()) {
        final keys = item.keys.map((entry) => entry.toString()).toSet();
        if (keys.length != expectedKeys.length ||
            !keys.containsAll(expectedKeys)) {
          throw FormatException(
            'Objects in JSON array ${jsonEncode(key)} have different fields. '
            'Use an OpenAPI schema when fields are optional or polymorphic.',
          );
        }
      }
      final nested = base + pascalCase(singular(key));
      _collect(nested, elem.cast<String, dynamic>(), out);
      return JsonField(
        jsonKey: key,
        dartName: name,
        kind: JsonFieldKind.objectList,
        modelType: 'List<$nested>',
        dtoType: 'List<${nested}Dto>',
      );
    }
    final et = _listElementType(key, value);
    return JsonField(
      jsonKey: key,
      dartName: name,
      kind: JsonFieldKind.primitiveList,
      modelType: 'List<$et>',
      dtoType: 'List<$et>',
    );
  }
  return prim('dynamic');
}

String _listElementType(String key, List<dynamic> values) {
  final types = <String>{};
  for (final value in values) {
    final type = switch (value) {
      bool() => 'bool',
      int() => 'int',
      double() => 'double',
      String() => 'String',
      _ => null,
    };
    if (type == null) {
      throw FormatException(
        'JSON array ${jsonEncode(key)} contains null, nested arrays, or '
        'unsupported mixed values. Use a homogeneous primitive array.',
      );
    }
    types.add(type);
  }
  if (types.length == 1) return types.single;
  if (types.difference(const {'int', 'double'}).isEmpty) return 'num';
  throw FormatException(
    'JSON array ${jsonEncode(key)} mixes incompatible primitive types: '
    '${types.join(', ')}.',
  );
}

// ---------------------------------------------------------------------------
// Emitters
// ---------------------------------------------------------------------------

String _ctorParams(List<JsonField> fields) {
  if (fields.isEmpty) return '()';
  final b = StringBuffer('({\n');
  for (final f in fields) {
    b.writeln('    required this.${f.dartName},');
  }
  b.write('  })');
  return b.toString();
}

String _mapToModel(JsonField f) {
  switch (f.kind) {
    case JsonFieldKind.object:
      return '${f.dartName}.toModel()';
    case JsonFieldKind.objectList:
      return '${f.dartName}.map((e) => e.toModel()).toList()';
    case JsonFieldKind.primitive:
    case JsonFieldKind.primitiveList:
      return f.dartName;
  }
}

String _mapToDto(JsonField f) {
  switch (f.kind) {
    case JsonFieldKind.object:
      return '${f.dartName}.toDto()';
    case JsonFieldKind.objectList:
      return '${f.dartName}.map((e) => e.toDto()).toList()';
    case JsonFieldKind.primitive:
    case JsonFieldKind.primitiveList:
      return f.dartName;
  }
}

/// Emits the plain domain-model file. When [withToDto] is set, each model also
/// gets a `toDto()` returning its `<name>Dto` (used for request payloads); pass
/// [dtoImport] so the file can reference those DTOs.
String emitModels(
  List<JsonClass> classes, {
  bool withToDto = false,
  String? dtoImport,
}) {
  final b = StringBuffer();
  if (withToDto && dtoImport != null) {
    b.writeln("import '$dtoImport';");
    b.writeln();
  }
  for (final c in classes) {
    b.writeln(
      '/// ${withToDto ? 'Request payload model' : 'Domain model'} for ${c.name}.',
    );
    b.writeln('class ${c.name} {');
    for (final f in c.fields) {
      b.writeln('  final ${f.modelType} ${f.dartName};');
    }
    if (c.fields.isNotEmpty) b.writeln();
    b.writeln('  const ${c.name}${_ctorParams(c.fields)};');
    if (withToDto) {
      b.writeln();
      b.writeln('  ${c.name}Dto toDto() => ${c.name}Dto(');
      for (final f in c.fields) {
        b.writeln('        ${f.dartName}: ${_mapToDto(f)},');
      }
      b.writeln('      );');
    }
    b.writeln('}');
    b.writeln();
  }
  return '${b.toString().trimRight()}\n';
}

/// Emits the `@JsonSerializable` DTO file. When [withToModel] is set, each DTO
/// gets a `toModel()` (used for responses); pass [modelImport] so it can
/// reference the domain models.
String emitDto(
  List<JsonClass> classes, {
  required String partName,
  String? modelImport,
  bool withToModel = false,
}) {
  final b = StringBuffer();
  b.writeln("import 'package:json_annotation/json_annotation.dart';");
  if (withToModel && modelImport != null) {
    b.writeln();
    b.writeln("import '$modelImport';");
  }
  b.writeln();
  b.writeln("part '$partName.g.dart';");
  b.writeln();
  for (final c in classes) {
    b.writeln('@JsonSerializable(explicitToJson: true)');
    b.writeln('class ${c.name}Dto {');
    for (final f in c.fields) {
      if (f.needsKey) {
        b.writeln('  @JsonKey(name: ${_dartStringLiteral(f.jsonKey)})');
      }
      b.writeln('  final ${f.dtoType} ${f.dartName};');
    }
    if (c.fields.isNotEmpty) b.writeln();
    b.writeln('  const ${c.name}Dto${_ctorParams(c.fields)};');
    b.writeln();
    b.writeln('  factory ${c.name}Dto.fromJson(Map<String, dynamic> json) =>');
    b.writeln('      _\$${c.name}DtoFromJson(json);');
    b.writeln();
    b.writeln(
      '  Map<String, dynamic> toJson() => _\$${c.name}DtoToJson(this);',
    );
    if (withToModel) {
      b.writeln();
      b.writeln('  ${c.name} toModel() => ${c.name}(');
      for (final f in c.fields) {
        b.writeln('        ${f.dartName}: ${_mapToModel(f)},');
      }
      b.writeln('      );');
    }
    b.writeln('}');
    b.writeln();
  }
  return '${b.toString().trimRight()}\n';
}

// ---------------------------------------------------------------------------
// Naming helpers (shared)
// ---------------------------------------------------------------------------

String snakeCase(String input) {
  final spaced = input
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}');
  return spaced
      .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '')
      .toLowerCase();
}

String pascalCase(String input) {
  final parts = snakeCase(input).split('_').where((s) => s.isNotEmpty);
  return parts.map((s) => s[0].toUpperCase() + s.substring(1)).join();
}

String camelCase(String input) {
  final pascal = pascalCase(input);
  if (pascal.isEmpty) return pascal;
  final camel = pascal[0].toLowerCase() + pascal.substring(1);
  if (RegExp(r'^[0-9]').hasMatch(camel)) return 'n$pascal';
  return _safeIdentifier(camel);
}

bool _isDartTypeName(String value) =>
    RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(value) &&
    !_dartKeywords.contains(value);

String _safeIdentifier(String value) =>
    _dartKeywords.contains(value) ? '${value}Value' : value;

String _dartStringLiteral(String value) =>
    jsonEncode(value).replaceAll(r'$', r'\$');

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

String singular(String key) {
  if (key.endsWith('ies') && key.length > 3) {
    return '${key.substring(0, key.length - 3)}y';
  }
  if (key.endsWith('s') && !key.endsWith('ss') && key.length > 1) {
    return key.substring(0, key.length - 1);
  }
  return key;
}
