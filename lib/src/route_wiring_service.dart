import 'dart:io';

import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';

class RouteWiringException implements Exception {
  const RouteWiringException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Registers the primary screen produced by a feature generator.
///
/// Flutter Modular features own their route table and are mounted separately,
/// so only Clean and MVVM projects need central application registration.
void registerFeatureRoute({
  required Directory root,
  required ForgeKitConfig config,
  required String projectName,
  required String feature,
}) {
  if (config.architecture == 'modular') return;

  final featureSnake = snakeCase(feature);
  final featurePascal = pascalCase(featureSnake);
  final featureCamel = camelCase(featureSnake);
  if (featureSnake.isEmpty || featurePascal.isEmpty) {
    throw const RouteWiringException('A feature name is required.');
  }

  final isMvvm = config.architecture == 'mvvm';
  if (config.router == 'named') {
    _wireApplicationRoute(
      root: root,
      config: config,
      importUri: isMvvm
          ? 'package:$projectName/ui/$featureSnake/widgets/'
              '${featureSnake}_screen.dart'
          : 'package:$projectName/features/$featureSnake/presentation/'
              'screens/${featureSnake}_screen.dart',
      registration: '$featurePascal${_screenSuffix(config)}.id: (_) => const '
          '$featurePascal${_screenSuffix(config)}(),',
      tag: featureSnake,
    );
    return;
  }

  _wireApplicationRoute(
    root: root,
    config: config,
    importUri: isMvvm
        ? 'package:$projectName/ui/$featureSnake/${featureSnake}_routes.dart'
        : 'package:$projectName/features/$featureSnake/presentation/'
            '${featureSnake}_routes.dart',
    registration: '...${featureCamel}Routes,',
    tag: featureSnake,
  );
}

/// Registers an additional screen in the configured application router.
void registerScreenRoute({
  required Directory root,
  required ForgeKitConfig config,
  required String projectName,
  required String feature,
  required String screenName,
}) {
  final featureSnake = snakeCase(feature);
  final screenSnake = snakeCase(screenName);
  final screenPascal = pascalCase(screenSnake);
  if (featureSnake.isEmpty || screenSnake.isEmpty || screenPascal.isEmpty) {
    throw const RouteWiringException(
      'Feature and screen names are required for route registration.',
    );
  }

  if (config.architecture == 'modular') {
    _wireModularScreenRoute(
      root: root,
      featureSnake: featureSnake,
      screenSnake: screenSnake,
      screenPascal: screenPascal,
    );
    return;
  }

  final isMvvm = config.architecture == 'mvvm';
  final className = '${screenPascal}Screen';
  final importUri = isMvvm
      ? 'package:$projectName/ui/$featureSnake/widgets/'
          '${screenSnake}_screen.dart'
      : 'package:$projectName/features/$featureSnake/presentation/screens/'
          '${screenSnake}_screen.dart';
  final tag = '$featureSnake:$screenSnake';
  final registration = config.router == 'named'
      ? '$className.id: (_) => const $className(),'
      : '''GoRoute(
  path: $className.id,
  name: $className.id,
  builder: (_, _) => const $className(),
),''';

  _wireApplicationRoute(
    root: root,
    config: config,
    importUri: importUri,
    registration: registration,
    tag: tag,
  );
}

void _wireApplicationRoute({
  required Directory root,
  required ForgeKitConfig config,
  required String importUri,
  required String registration,
  required String tag,
}) {
  final appFile = File(
    p.joinAll([
      root.path,
      'lib',
      if (config.architecture == 'mvvm') ...[
        'ui',
        'core',
        'app',
      ] else ...[
        'core',
        'presentation',
        'app',
      ],
      'app.dart',
    ]),
  );
  if (!appFile.existsSync()) {
    throw RouteWiringException(
      'Could not find ${p.relative(appFile.path, from: root.path)}.',
    );
  }

  var source = appFile.readAsStringSync();
  if (_containsRegistrationTag(source, tag)) return;

  source = _addTaggedImport(source, importUri, tag);
  final marker = config.router == 'named'
      ? '// forgekit:named-routes'
      : '// forgekit:go-routes';
  source = _insertTaggedRegistration(
    source,
    registration: registration,
    tag: tag,
    marker: marker,
    collectionOpening: config.router == 'named' ? '{' : '[',
  );
  appFile.writeAsStringSync(source);
}

void _wireModularScreenRoute({
  required Directory root,
  required String featureSnake,
  required String screenSnake,
  required String screenPascal,
}) {
  final moduleFile = File(
    p.join(
      root.path,
      'lib',
      'modules',
      featureSnake,
      '${featureSnake}_module.dart',
    ),
  );
  if (!moduleFile.existsSync()) {
    throw RouteWiringException(
      'Could not find ${p.relative(moduleFile.path, from: root.path)}.',
    );
  }

  final tag = '$featureSnake:$screenSnake';
  var source = moduleFile.readAsStringSync();
  if (_containsRegistrationTag(source, tag)) return;

  source = _addTaggedImport(
    source,
    'presentation/${screenSnake}_screen.dart',
    tag,
  );
  final registration = "..route('/$screenSnake', child: (_, _) => const "
      '${screenPascal}Screen())';
  source = _insertTaggedRegistration(
    source,
    registration: registration,
    tag: tag,
    marker: '// forgekit:routes',
    collectionOpening: null,
  );
  moduleFile.writeAsStringSync(source);
}

String _addTaggedImport(String source, String uri, String tag) {
  final plainImport = "import '$uri';";
  if (source.contains(plainImport)) return source;

  final import = '$plainImport // forgekit:route-import:$tag';
  const marker = '// forgekit:route-imports';
  if (source.contains(marker)) {
    return source.replaceFirst(marker, '$import\n$marker');
  }

  final imports =
      RegExp(r'''^import ['"].+['"];\s*(?://.*)?$''', multiLine: true)
          .allMatches(source)
          .toList();
  if (imports.isEmpty) {
    throw const RouteWiringException(
      'Could not locate the import section for route registration.',
    );
  }
  final last = imports.last;
  return source.replaceRange(last.end, last.end, '\n$import');
}

String _insertTaggedRegistration(
  String source, {
  required String registration,
  required String tag,
  required String marker,
  required String? collectionOpening,
}) {
  final markerIndex = source.indexOf(marker);
  if (markerIndex != -1) {
    final indent = _lineIndent(source, markerIndex);
    final tagged = _indentBlock(
      registration,
      indent,
      trailingComment: '// forgekit:route:$tag',
    );
    return source.replaceRange(markerIndex, markerIndex, '$tagged\n');
  }

  if (collectionOpening == null) {
    final routeIndex = source.indexOf('..route(');
    if (routeIndex == -1) {
      throw const RouteWiringException(
        'Could not locate the Modular route cascade.',
      );
    }
    final indent = _lineIndent(source, routeIndex);
    final tagged = _indentBlock(
      registration,
      indent,
      trailingComment: '// forgekit:route:$tag',
    );
    return source.replaceRange(routeIndex, routeIndex, '$tagged\n$indent');
  }

  final routeMatches =
      RegExp(r'^\s*routes\s*:', multiLine: true).allMatches(source).toList();
  final routesMatch = routeMatches.isEmpty ? null : routeMatches.last;
  if (routesMatch == null) {
    throw const RouteWiringException(
      'Could not locate the application routes collection.',
    );
  }
  final openingIndex = source.indexOf(collectionOpening, routesMatch.end);
  if (openingIndex == -1) {
    throw const RouteWiringException(
      'Could not locate the application routes collection opening.',
    );
  }
  final indent = '${_lineIndent(source, routesMatch.start)}  ';
  final tagged = _indentBlock(
    registration,
    indent,
    trailingComment: '// forgekit:route:$tag',
  );
  return source.replaceRange(openingIndex + 1, openingIndex + 1, '\n$tagged');
}

String _indentBlock(
  String value,
  String indent, {
  required String trailingComment,
}) {
  final lines = value.split('\n');
  if (lines.length == 1) return '$indent${lines.single} $trailingComment';
  return [
    '$indent${lines.first} $trailingComment:start',
    ...lines.skip(1).map((line) => '$indent$line'),
    '$indent$trailingComment:end',
  ].join('\n');
}

String _lineIndent(String source, int index) {
  final lineStart = source.lastIndexOf('\n', index - 1) + 1;
  return RegExp(r'^\s*').firstMatch(source.substring(lineStart, index))![0]!;
}

String _screenSuffix(ForgeKitConfig config) => 'Screen';

/// Removes only route registrations and imports owned by ForgeKit for a
/// feature. User-authored routes are deliberately left untouched.
void unregisterFeatureRoutes({
  required Directory root,
  required ForgeKitConfig config,
  required String feature,
}) {
  if (config.architecture == 'modular') return;

  final featureSnake = snakeCase(feature);
  if (featureSnake.isEmpty) {
    throw const RouteWiringException('A feature name is required.');
  }

  final appFile = File(
    p.joinAll([
      root.path,
      'lib',
      if (config.architecture == 'mvvm') ...[
        'ui',
        'core',
        'app',
      ] else ...[
        'core',
        'presentation',
        'app',
      ],
      'app.dart',
    ]),
  );
  if (!appFile.existsSync()) return;

  final lines = appFile.readAsLinesSync();
  final output = <String>[];
  var skippingBlock = false;
  for (final line in lines) {
    if (_isOwnedRouteLine(line, featureSnake)) {
      if (line.contains(':start')) skippingBlock = true;
      if (line.contains(':end')) skippingBlock = false;
      if (config.router == 'named' &&
          line.contains('// forgekit:route:') &&
          !line.contains('// forgekit:route-import:') &&
          !line.contains(':start') &&
          !line.contains(':end') &&
          !line.contains('.id:')) {
        _removeWrappedNamedRouteStart(output);
      }
      continue;
    }
    if (skippingBlock) continue;
    output.add(line);
  }

  appFile.writeAsStringSync('${output.join('\n')}\n');
}

bool _containsRegistrationTag(String source, String tag) => RegExp(
      '// forgekit:route:${RegExp.escape(tag)}(?=\\s|:start|\$)',
      multiLine: true,
    ).hasMatch(source);

bool _isOwnedRouteLine(String line, String featureSnake) => RegExp(
      '// forgekit:(?:route|route-import):${RegExp.escape(featureSnake)}'
      r'(?=[:\s]|$)',
    ).hasMatch(line);

void _removeWrappedNamedRouteStart(List<String> output) {
  for (var index = output.length - 1; index >= 0; index--) {
    final candidate = output[index].trim();
    if (RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*Screen\.id\s*:').hasMatch(
      candidate,
    )) {
      output.removeRange(index, output.length);
      return;
    }
    if (candidate.isEmpty ||
        candidate.startsWith('//') ||
        candidate.endsWith(',') ||
        candidate.endsWith('{') ||
        candidate.endsWith('[')) {
      return;
    }
  }
}
