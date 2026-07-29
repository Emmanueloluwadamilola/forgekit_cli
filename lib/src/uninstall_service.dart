import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';
import 'mason_environment.dart';

/// One removable thing, described so it can be listed before it is removed.
typedef UninstallStep = ({String label, String detail});

/// What a given set of options would remove.
///
/// Built before anything is deleted so the confirmation prompt and `--dry-run`
/// show the same list the command will act on.
class UninstallPlan {
  UninstallPlan({
    required this.registeredBricks,
    required this.forgekitHomeDir,
    required this.widgetsDir,
    required this.masonCacheDir,
    required this.projectConfig,
    required this.projectState,
    required this.keepWidgets,
    required this.removeMason,
    required this.cleanProject,
  });

  final List<String> registeredBricks;
  final Directory? forgekitHomeDir;
  final Directory? widgetsDir;
  final Directory? masonCacheDir;
  final File? projectConfig;
  final Directory? projectState;

  final bool keepWidgets;
  final bool removeMason;
  final bool cleanProject;

  /// Whether anything at all would be removed.
  bool get isEmpty => steps.isEmpty;

  /// Human-readable removal steps, in execution order.
  List<UninstallStep> get steps {
    final steps = <UninstallStep>[];

    if (registeredBricks.isNotEmpty) {
      steps.add((
        label: 'Unregister ${registeredBricks.length} Mason brick(s)',
        detail: registeredBricks.join(', '),
      ));
    }
    if (forgekitHomeDir != null) {
      steps.add((
        label: keepWidgets && widgetsDir != null
            ? 'Remove ForgeKit data, keeping the widget library'
            : 'Remove the ForgeKit data directory',
        detail: forgekitHomeDir!.path,
      ));
    }
    if (removeMason && masonCacheDir != null) {
      steps.add((
        label: 'Remove Mason CLI and its cache',
        detail: masonCacheDir!.path,
      ));
    }
    if (cleanProject && projectConfig != null) {
      steps.add((label: 'Remove', detail: projectConfig!.path));
    }
    if (cleanProject && projectState != null) {
      steps.add((label: 'Remove', detail: projectState!.path));
    }
    steps.add((
      label: 'Deactivate the forgekit executable',
      detail: 'dart pub global deactivate forgekit',
    ));
    return steps;
  }
}

/// Builds an [UninstallPlan] without changing anything.
UninstallPlan planUninstall({
  required bool keepWidgets,
  required bool removeMason,
  required bool cleanProject,
  Directory? projectRoot,
}) {
  final home = forgekitHome();
  final widgets = Directory(p.join(home.path, 'widgets'));
  final masonCache = masonGlobalDir().parent;

  File? projectConfig;
  Directory? projectState;
  if (cleanProject && projectRoot != null) {
    final config = File(p.join(projectRoot.path, forgeKitConfigFileName));
    if (config.existsSync()) projectConfig = config;
    final state = Directory(p.join(projectRoot.path, '.forgekit'));
    if (state.existsSync()) projectState = state;
  }

  return UninstallPlan(
    // Only bricks Mason actually knows about, so the plan does not promise to
    // unregister things that were never registered.
    registeredBricks:
        forgekitBricks.keys.where(isForgekitBrickRegistered).toList(),
    forgekitHomeDir: home.existsSync() ? home : null,
    widgetsDir: widgets.existsSync() ? widgets : null,
    masonCacheDir: masonCache.existsSync() ? masonCache : null,
    projectConfig: projectConfig,
    projectState: projectState,
    keepWidgets: keepWidgets,
    removeMason: removeMason,
    cleanProject: cleanProject,
  );
}

/// Refuses to delete a path that is obviously not a ForgeKit data directory.
///
/// `FORGEKIT_HOME` is user-controlled, so a stray `export FORGEKIT_HOME=$HOME`
/// would otherwise turn uninstall into `rm -rf ~`. Two guards: the path must be
/// at least two levels below the filesystem root, and it must not be the home
/// directory itself.
bool isUnsafeUninstallTarget(Directory directory) {
  final resolved = p.normalize(directory.absolute.path);
  if (p.split(resolved).length <= 2) return true;

  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (home.trim().isNotEmpty && p.normalize(home) == resolved) return true;

  return false;
}

/// Removes ForgeKit from the machine.
///
/// Order is deliberate. Bricks are unregistered before their directories are
/// deleted, otherwise Mason's global config keeps entries pointing at paths
/// that no longer exist. Self-deactivation runs last, because it removes the
/// very executable running this code.
Future<int> runUninstall({
  required Logger logger,
  required UninstallPlan plan,
  bool runProcesses = true,
}) async {
  var failures = 0;

  // 1. Unregister bricks while Mason is still installed and the paths exist.
  if (plan.registeredBricks.isNotEmpty && runProcesses) {
    final progress = logger.progress('Unregistering Mason bricks');
    var unregistered = 0;
    for (final brick in plan.registeredBricks) {
      final code = await _runQuiet(
        'dart',
        ['pub', 'global', 'run', 'mason_cli:mason', 'remove', '-g', brick],
      );
      if (code == 0) unregistered++;
    }
    progress.complete('Unregistered $unregistered brick(s).');
  }

  // 2. ForgeKit's data directory.
  final home = plan.forgekitHomeDir;
  if (home != null) {
    if (isUnsafeUninstallTarget(home)) {
      logger.err(
        'Refusing to delete ${home.path}: it is a home or root directory, not '
        'a ForgeKit data directory. Check FORGEKIT_HOME and remove it by hand.',
      );
      failures++;
    } else if (plan.keepWidgets && plan.widgetsDir != null) {
      failures += await _removeAllBut(
        home: home,
        keep: 'widgets',
        logger: logger,
      );
      logger.info('Kept your widget library at ${plan.widgetsDir!.path}');
    } else {
      failures += await _delete(home, logger: logger);
    }
  }

  // 3. Mason, only when explicitly requested.
  if (plan.removeMason) {
    if (runProcesses) {
      final code = await _runQuiet(
        'dart',
        ['pub', 'global', 'deactivate', 'mason_cli'],
      );
      if (code != 0) {
        logger.warn(
          'Could not deactivate mason_cli. Remove it with: '
          'dart pub global deactivate mason_cli',
        );
      }
    }
    final cache = plan.masonCacheDir;
    if (cache != null && !isUnsafeUninstallTarget(cache)) {
      failures += await _delete(cache, logger: logger);
    }
  }

  // 4. Current project only. Never searches the filesystem.
  if (plan.projectConfig != null) {
    failures += await _delete(plan.projectConfig!, logger: logger);
  }
  if (plan.projectState != null) {
    failures += await _delete(plan.projectState!, logger: logger);
  }

  // 5. Last, because it removes the executable running this code.
  if (runProcesses) {
    final progress = logger.progress('Deactivating forgekit');
    final code = await _runQuiet(
      'dart',
      ['pub', 'global', 'deactivate', 'forgekit'],
    );
    if (code == 0) {
      progress.complete('Deactivated forgekit.');
    } else {
      // Expected on Windows, where a running executable cannot be deleted.
      progress.fail('Could not deactivate the forgekit executable.');
      logger.info('Finish by running:  dart pub global deactivate forgekit');
    }
  }

  logger.info('');
  if (failures > 0) {
    logger.err(
      '$failures item(s) could not be removed. Everything else is gone; see '
      'the messages above.',
    );
    return 1;
  }

  logger
    ..success('ForgeKit has been removed.')
    ..info('')
    ..info('Projects it generated are unaffected — they are plain Flutter '
        'code with ordinary pub dependencies.');
  if (!plan.cleanProject) {
    logger.info(
      'Any forgekit.yaml and .forgekit/ left in your projects are inert. '
      'Delete them whenever you like.',
    );
  }
  return 0;
}

/// Deletes every entry in [home] except [keep], then [home] itself if empty.
Future<int> _removeAllBut({
  required Directory home,
  required String keep,
  required Logger logger,
}) async {
  var failures = 0;
  for (final entity in home.listSync(followLinks: false)) {
    if (p.basename(entity.path) == keep) continue;
    failures += await _delete(entity, logger: logger);
  }
  return failures;
}

Future<int> _delete(FileSystemEntity entity, {required Logger logger}) async {
  try {
    if (entity is Directory) {
      await entity.delete(recursive: true);
    } else {
      await entity.delete();
    }
    logger.detail('Removed ${entity.path}');
    return 0;
  } on FileSystemException catch (error) {
    logger.err('Could not remove ${entity.path}: ${error.message}');
    return 1;
  }
}

/// Runs a process without forwarding its output.
///
/// Uninstall reports its own progress; Mason's per-brick chatter would bury it.
Future<int> _runQuiet(String executable, List<String> arguments) async {
  try {
    final result = await Process.run(executable, arguments);
    return result.exitCode;
  } on ProcessException {
    return 1;
  }
}
