import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'json_to_dart.dart';
import 'registry_service.dart';
import 'utils.dart';

class SyncedWidget {
  const SyncedWidget({
    required this.name,
    required this.path,
  });

  final String name;
  final String path;
}

Future<int> syncWidget({
  required String name,
  String? sourcePath,
  bool push = false,
  Logger? logger,
}) async {
  final log = logger ?? Logger();
  final snake = snakeCase(name);

  if (snake.isEmpty) {
    log.err('A widget name is required.');
    return 1;
  }

  final root = findProjectRoot();
  final sourceFile = sourcePath == null
      ? File(
          p.joinAll([
            root?.path ?? Directory.current.path,
            ..._widgetDirectorySegments(
              root == null
                  ? const ForgeKitConfig()
                  : loadForgeKitConfig(root: root),
            ),
            '$snake.dart',
          ]),
        )
      : File(p.normalize(p.absolute(sourcePath)));

  if (!sourceFile.existsSync()) {
    log.err('Widget file not found: ${sourceFile.path}');
    log.info('Create it first with: forgekit add widget $snake');
    return 1;
  }

  final projectName =
      root == null ? detectProjectName() : detectProjectName(root: root);
  final manifest = <String, Object?>{
    'name': snake,
    'sourceProject': projectName,
    'sourcePath': sourceFile.path,
    'syncedAt': DateTime.now().toUtc().toIso8601String(),
  };

  await _writeSyncedWidget(
    sourceFile: sourceFile,
    targetDir: Directory(p.join(_widgetsHome().path, snake)),
    snake: snake,
    manifest: manifest,
  );

  log.success('Synced widget "$snake".');

  if (push) {
    final registryWidgets = registryWidgetsDirSync();
    if (registryWidgets == null) {
      log.err(
        'No shared registry connected. Run: forgekit registry connect <git-url>',
      );
      return 1;
    }
    await _writeSyncedWidget(
      sourceFile: sourceFile,
      targetDir: Directory(p.join(registryWidgets.path, snake)),
      snake: snake,
      manifest: manifest,
    );
    final pushExit = await pushRegistry(
      logger: log,
      message: 'Sync widget $snake',
    );
    if (pushExit != 0) return pushExit;
    log.success('Pushed widget "$snake" to the shared registry.');
  }

  log.info('Install it in another project with: forgekit add widget $snake');
  return 0;
}

Future<SyncedWidget?> installSyncedWidget({
  required String name,
  required Directory root,
  required bool force,
  Logger? logger,
}) async {
  final log = logger ?? Logger();
  final snake = snakeCase(name);
  final widgetDir = _findWidgetDir(snake);
  if (widgetDir == null) return null;
  final sourceFile = File(p.join(widgetDir.path, '$snake.dart'));

  if (!sourceFile.existsSync()) return null;

  final targetFile = File(
    p.joinAll([
      root.path,
      ..._widgetDirectorySegments(loadForgeKitConfig(root: root)),
      '$snake.dart',
    ]),
  );

  if (targetFile.existsSync() && !force) {
    log.err('A widget named "$snake" already exists: ${targetFile.path}');
    log.info('Run again with --force to overwrite it.');
    return const SyncedWidget(name: '', path: '');
  }

  await targetFile.parent.create(recursive: true);

  final sourceProject = await _readSourceProject(widgetDir);
  final targetProject = detectProjectName(root: root);
  var contents = await sourceFile.readAsString();
  if (sourceProject != null &&
      sourceProject.isNotEmpty &&
      sourceProject != targetProject) {
    contents = contents.replaceAll(
      'package:$sourceProject/',
      'package:$targetProject/',
    );
  }

  await targetFile.writeAsString(contents);
  return SyncedWidget(name: snake, path: targetFile.path);
}

List<String> _widgetDirectorySegments(ForgeKitConfig config) =>
    switch (config.architecture) {
      'mvvm' => const ['lib', 'ui', 'core', 'widgets'],
      'modular' => const ['lib', 'core', 'widgets'],
      _ => const ['lib', 'core', 'presentation', 'widgets'],
    };

Future<void> _writeSyncedWidget({
  required File sourceFile,
  required Directory targetDir,
  required String snake,
  required Map<String, Object?> manifest,
}) async {
  await targetDir.create(recursive: true);
  await sourceFile.copy(p.join(targetDir.path, '$snake.dart'));
  await File(p.join(targetDir.path, 'widget.json')).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}

Directory? _findWidgetDir(String snake) {
  final localDir = Directory(p.join(_widgetsHome().path, snake));
  if (File(p.join(localDir.path, '$snake.dart')).existsSync()) {
    return localDir;
  }

  final registryWidgets = registryWidgetsDirSync();
  if (registryWidgets == null) return null;
  final registryDir = Directory(p.join(registryWidgets.path, snake));
  if (File(p.join(registryDir.path, '$snake.dart')).existsSync()) {
    return registryDir;
  }
  return null;
}

Future<String?> _readSourceProject(Directory widgetDir) async {
  final manifestFile = File(p.join(widgetDir.path, 'widget.json'));
  if (!manifestFile.existsSync()) return null;

  final decoded = json.decode(await manifestFile.readAsString());
  if (decoded is! Map<String, dynamic>) return null;
  final sourceProject = decoded['sourceProject'];
  return sourceProject is String ? sourceProject : null;
}

Directory _widgetsHome() => Directory(p.join(_forgekitHome().path, 'widgets'));

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
