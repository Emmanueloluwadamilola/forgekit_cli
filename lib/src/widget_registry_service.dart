import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'json_to_dart.dart';
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
          p.join(
            root?.path ?? Directory.current.path,
            'lib',
            'core',
            'presentation',
            'widgets',
            '$snake.dart',
          ),
        )
      : File(p.normalize(p.absolute(sourcePath)));

  if (!sourceFile.existsSync()) {
    log.err('Widget file not found: ${sourceFile.path}');
    log.info('Create it first with: forgekit add widget $snake');
    return 1;
  }

  final projectName =
      root == null ? detectProjectName() : detectProjectName(root: root);
  final targetDir = Directory(p.join(_widgetsHome().path, snake));
  await targetDir.create(recursive: true);

  final targetFile = File(p.join(targetDir.path, '$snake.dart'));
  await sourceFile.copy(targetFile.path);

  final manifest = <String, Object?>{
    'name': snake,
    'sourceProject': projectName,
    'sourcePath': sourceFile.path,
    'syncedAt': DateTime.now().toUtc().toIso8601String(),
  };
  await File(p.join(targetDir.path, 'widget.json')).writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );

  log.success('Synced widget "$snake".');
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
  final widgetDir = Directory(p.join(_widgetsHome().path, snake));
  final sourceFile = File(p.join(widgetDir.path, '$snake.dart'));

  if (!sourceFile.existsSync()) return null;

  final targetFile = File(
    p.join(
      root.path,
      'lib',
      'core',
      'presentation',
      'widgets',
      '$snake.dart',
    ),
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
