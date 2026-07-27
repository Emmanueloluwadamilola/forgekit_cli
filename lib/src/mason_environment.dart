import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The bundled bricks Flutter ForgeKit CLI installs and registers globally,
/// mapped to their package-relative source directories.
///
/// This is the single source of truth for the brick set. `setup_service.dart`
/// installs from it, and [isForgekitBrickRegistered] verifies against it so a
/// missing `forgekit setup` produces an actionable message instead of a bare
/// "Failed to create app".
const forgekitBricks = <String, String>{
  'forge_app': 'bricks/forge_app',
  'forge_app_mvvm': 'bricks/forge_app_mvvm',
  'forge_app_modular': 'bricks/forge_app_modular',
  'forge_feature': 'bricks/forge_feature',
  'forge_feature_mvvm': 'bricks/forge_feature_mvvm',
  'forge_feature_modular': 'bricks/forge_feature_modular',
  'forge_widget': 'bricks/forge_widget',
  // Registered but not currently invoked by any command; `add service` is a
  // native Dart generator. Kept in the map so `forgekit setup` continues to
  // clean up registrations left by earlier releases.
  'forge_service': 'bricks/forge_service',
};

/// Resolves the directory Flutter ForgeKit CLI installs bundled bricks into.
///
/// Honours `FORGEKIT_HOME` first so tests and sandboxed environments can
/// redirect it, then falls back to the platform convention.
Directory forgekitHome() {
  final configuredHome = Platform.environment['FORGEKIT_HOME'];
  if (configuredHome != null && configuredHome.trim().isNotEmpty) {
    return Directory(configuredHome);
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return Directory(p.join(appData, 'ForgeKit'));
    }
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.trim().isNotEmpty) {
    return Directory(p.join(home, '.forgekit'));
  }

  return Directory(p.join(Directory.systemTemp.path, 'forgekit'));
}

/// Resolves Mason's global configuration directory, where `mason add -g`
/// records brick registrations.
Directory masonGlobalDir() {
  final masonCache = Platform.environment['MASON_CACHE'];
  if (masonCache != null && masonCache.trim().isNotEmpty) {
    return Directory(p.join(masonCache, 'global'));
  }

  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      final appDataCacheDir = Directory(p.join(appData, 'Mason', 'Cache'));
      if (appDataCacheDir.existsSync()) {
        return Directory(p.join(appDataCacheDir.path, 'global'));
      }
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      return Directory(p.join(localAppData, 'Mason', 'Cache', 'global'));
    }
  }

  final home = Platform.environment['HOME'];
  if (home != null && home.trim().isNotEmpty) {
    return Directory(p.join(home, '.mason-cache', 'global'));
  }

  return Directory(p.join(Directory.systemTemp.path, 'mason-cache', 'global'));
}

/// Whether [brick] appears in Mason's global registration records.
///
/// Checks all three files Mason maintains, and treats a hit in any of them as
/// registered. The check is deliberately permissive: it only ever runs after a
/// Mason invocation has already failed, so a false negative would suppress a
/// helpful hint while a false positive costs nothing.
bool isForgekitBrickRegistered(String brick) {
  final globalDir = masonGlobalDir();

  if (_jsonMapContainsKey(
    File(p.join(globalDir.path, '.mason', 'bricks.json')),
    brick,
  )) {
    return true;
  }
  if (_jsonMapContainsKey(
    File(p.join(globalDir.path, 'mason-lock.json')),
    brick,
    nestedUnderBricks: true,
  )) {
    return true;
  }
  return _masonYamlContainsBrick(
    File(p.join(globalDir.path, 'mason.yaml')),
    brick,
  );
}

/// The bundled bricks that are not currently registered with Mason.
///
/// An empty result means `forgekit setup` has been run successfully for this
/// release. Used by `forgekit doctor` to surface the problem before a
/// generation command fails.
List<String> unregisteredForgekitBricks() {
  return forgekitBricks.keys.where((brick) {
    return !isForgekitBrickRegistered(brick);
  }).toList();
}

bool _jsonMapContainsKey(
  File file,
  String key, {
  bool nestedUnderBricks = false,
}) {
  if (!file.existsSync()) return false;
  try {
    final contents = file.readAsStringSync();
    if (contents.trim().isEmpty) return false;
    final decoded = json.decode(contents);
    if (decoded is! Map<String, dynamic>) return false;
    final target = nestedUnderBricks ? decoded['bricks'] : decoded;
    if (target is! Map<String, dynamic>) return false;
    return target.containsKey(key);
  } on FormatException {
    return false;
  } on FileSystemException {
    return false;
  }
}

bool _masonYamlContainsBrick(File file, String brick) {
  if (!file.existsSync()) return false;
  try {
    final contents = file.readAsStringSync();
    if (contents.trim().isEmpty) return false;
    final document = loadYaml(contents);
    if (document is! YamlMap) return false;
    final bricks = document['bricks'];
    if (bricks is! YamlMap) return false;
    return bricks.containsKey(brick);
  } on YamlException {
    return false;
  } on FileSystemException {
    return false;
  }
}
