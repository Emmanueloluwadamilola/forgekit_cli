import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

class RegistryConfig {
  const RegistryConfig({
    required this.url,
    required this.path,
  });

  final String url;
  final String path;

  Map<String, Object?> toJson() => {
        'url': url,
        'path': path,
      };

  static RegistryConfig fromJson(Map<String, dynamic> json) {
    return RegistryConfig(
      url: json['url'] as String,
      path: json['path'] as String,
    );
  }
}

Future<int> connectRegistry({
  required String url,
  required Logger logger,
  String? path,
}) async {
  final registryPath = path == null || path.trim().isEmpty
      ? p.join(_forgekitHome().path, 'registry')
      : p.normalize(p.absolute(path));
  final registryDir = Directory(registryPath);

  if (registryDir.existsSync()) {
    if (!Directory(p.join(registryDir.path, '.git')).existsSync()) {
      logger.err(
        'Registry path exists but is not a Git repository: $registryPath',
      );
      return 1;
    }
    final pullExit = await pullRegistry(logger: logger, path: registryPath);
    if (pullExit != 0) return pullExit;
  } else {
    final cloneExit = await _runGit(
      ['clone', url, registryPath],
      logger: logger,
      failureMessage: 'Failed to clone registry.',
    );
    if (cloneExit != 0) return cloneExit;
  }

  await _writeRegistryConfig(
    RegistryConfig(url: url, path: registryPath),
  );

  logger.success('Connected Flutter ForgeKit CLI registry.');
  logger.info('Registry path: $registryPath');
  return 0;
}

Future<int> pullRegistry({
  required Logger logger,
  String? path,
}) async {
  final config = path == null ? await readRegistryConfig() : null;
  final registryPath = path ?? config?.path;
  if (registryPath == null) {
    logger
        .err('No registry connected. Run: forgekit registry connect <git-url>');
    return 1;
  }

  final registryDir = Directory(registryPath);
  if (!registryDir.existsSync()) {
    logger.err('Registry folder not found: $registryPath');
    return 1;
  }

  return _runGit(
    ['-C', registryPath, 'pull', '--ff-only'],
    logger: logger,
    failureMessage: 'Failed to pull registry.',
  );
}

Future<int> pushRegistry({
  required Logger logger,
  String message = 'Sync Flutter ForgeKit CLI registry',
}) async {
  final config = await readRegistryConfig();
  if (config == null) {
    logger
        .err('No registry connected. Run: forgekit registry connect <git-url>');
    return 1;
  }

  final registryDir = Directory(config.path);
  if (!registryDir.existsSync()) {
    logger.err('Registry folder not found: ${config.path}');
    return 1;
  }

  final addExit = await _runGit(
    ['-C', config.path, 'add', 'widgets'],
    logger: logger,
    failureMessage: 'Failed to stage registry changes.',
  );
  if (addExit != 0) return addExit;

  final diff = await Process.run(
    'git',
    ['-C', config.path, 'diff', '--cached', '--quiet'],
  );
  if (diff.exitCode == 0) {
    logger.info('Registry has no changes to push.');
    return 0;
  }

  final commitExit = await _runGit(
    ['-C', config.path, 'commit', '-m', message],
    logger: logger,
    failureMessage: 'Failed to commit registry changes.',
  );
  if (commitExit != 0) return commitExit;

  return _runGit(
    ['-C', config.path, 'push'],
    logger: logger,
    failureMessage: 'Failed to push registry changes.',
  );
}

Future<int> registryStatus({required Logger logger}) async {
  final config = await readRegistryConfig();
  if (config == null) {
    logger
        .err('No registry connected. Run: forgekit registry connect <git-url>');
    return 1;
  }

  logger
    ..info('Registry URL: ${config.url}')
    ..info('Registry path: ${config.path}');

  return _runGit(
    ['-C', config.path, 'status', '--short'],
    logger: logger,
    failureMessage: 'Failed to read registry status.',
  );
}

Future<RegistryConfig?> readRegistryConfig() async {
  final file = _registryConfigFile();
  if (!file.existsSync()) return null;

  final decoded = json.decode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) return null;
  return RegistryConfig.fromJson(decoded);
}

Directory? registryWidgetsDirSync() {
  final file = _registryConfigFile();
  if (!file.existsSync()) return null;

  final decoded = json.decode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) return null;
  final config = RegistryConfig.fromJson(decoded);
  if (!Directory(config.path).existsSync()) return null;
  final dir = Directory(p.join(config.path, 'widgets'));
  return dir;
}

Future<void> _writeRegistryConfig(RegistryConfig config) async {
  final file = _registryConfigFile();
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n',
  );
}

File _registryConfigFile() {
  return File(p.join(_forgekitHome().path, 'registry.json'));
}

Directory _forgekitHome() {
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

Future<int> _runGit(
  List<String> args, {
  required Logger logger,
  required String failureMessage,
}) async {
  try {
    final process = await Process.start(
      'git',
      args,
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) logger.err(failureMessage);
    return exitCode;
  } on ProcessException catch (e) {
    logger
      ..err(failureMessage)
      ..err(e.message);
    return 1;
  }
}
