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

  static RegistryConfig? tryFromJson(Map<String, dynamic> json) {
    final url = json['url'];
    final path = json['path'];
    if (url is! String ||
        path is! String ||
        path.trim().isEmpty ||
        !p.isAbsolute(path) ||
        validateRegistryRemote(url) != null) {
      return null;
    }
    return RegistryConfig(
      url: url,
      path: p.normalize(path),
    );
  }
}

Future<int> connectRegistry({
  required String url,
  required Logger logger,
  String? path,
}) async {
  final normalizedUrl = url.trim();
  final validationError = validateRegistryRemote(normalizedUrl);
  if (validationError != null) {
    logger.err(validationError);
    return 1;
  }
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
    final remote = await Process.run(
      'git',
      ['-C', registryPath, 'remote', 'get-url', 'origin'],
    );
    if (remote.exitCode != 0 ||
        remote.stdout.toString().trim() != normalizedUrl) {
      logger.err(
        'Registry path is connected to a different or unreadable origin. '
        'Use a new --path or pass its exact existing origin URL.',
      );
      return 1;
    }
    final pullExit = await pullRegistry(logger: logger, path: registryPath);
    if (pullExit != 0) return pullExit;
  } else {
    final cloneExit = await _runGit(
      ['clone', normalizedUrl, registryPath],
      logger: logger,
      failureMessage: 'Failed to clone registry.',
    );
    if (cloneExit != 0) return cloneExit;
  }

  await _writeRegistryConfig(
    RegistryConfig(url: normalizedUrl, path: registryPath),
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
    ..info('Registry URL: ${safeRegistryRemoteForDisplay(config.url)}')
    ..info('Registry path: ${config.path}');

  return _runGit(
    ['-C', config.path, 'status', '--short'],
    logger: logger,
    failureMessage: 'Failed to read registry status.',
  );
}

/// Validates a registry remote without performing network access.
///
/// HTTPS and SSH remotes are accepted, as are local paths and `file:` URLs.
/// Credential-bearing URLs, URL query strings, and plaintext network
/// transports are rejected so secrets are not written to registry.json.
String? validateRegistryRemote(String remote) {
  if (remote.trim().isEmpty) {
    return 'A registry Git URL or local path is required.';
  }
  if (RegExp(r'^[^@\s]+@[^:\s]+:.+$').hasMatch(remote)) return null;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(remote) || remote.startsWith(r'\\')) {
    return null;
  }

  final uri = Uri.tryParse(remote);
  if (uri == null) return 'Registry remote is not a valid URL or local path.';
  if (uri.scheme.isEmpty) return null;
  if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
    return 'Registry URLs must not contain query strings or fragments because '
        'they can expose credentials in local configuration and process logs.';
  }
  switch (uri.scheme.toLowerCase()) {
    case 'https':
      if (uri.host.isEmpty) return 'HTTPS registry URL must include a host.';
      if (uri.userInfo.isNotEmpty) {
        return 'Registry URLs must not embed usernames, passwords, or tokens. '
            'Use the Git credential manager or SSH agent.';
      }
      return null;
    case 'ssh':
      if (uri.host.isEmpty) return 'SSH registry URL must include a host.';
      if (uri.userInfo.contains(':')) {
        return 'SSH registry URLs must not embed passwords. Use an SSH agent.';
      }
      return null;
    case 'file':
      return null;
    default:
      return 'Registry transport "${uri.scheme}" is not allowed. Use HTTPS, '
          'SSH, or a local path; plaintext HTTP and git:// are rejected.';
  }
}

String safeRegistryRemoteForDisplay(String remote) {
  return validateRegistryRemote(remote) == null
      ? remote
      : '<redacted insecure or credential-bearing remote>';
}

Future<RegistryConfig?> readRegistryConfig() async {
  final file = _registryConfigFile();
  if (!file.existsSync()) return null;

  try {
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    return RegistryConfig.tryFromJson(decoded);
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

Directory? registryWidgetsDirSync() {
  final file = _registryConfigFile();
  if (!file.existsSync()) return null;

  try {
    final decoded = json.decode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    final config = RegistryConfig.tryFromJson(decoded);
    if (config == null || !Directory(config.path).existsSync()) return null;
    return Directory(p.join(config.path, 'widgets'));
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
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
