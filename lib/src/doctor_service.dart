import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'json_to_dart.dart';
import 'utils.dart';

/// Checks that a project conforms to the ForgeKit Architecture Standard.
///
/// Missing required files are reported as errors; naming / annotation drift as
/// warnings. Exit code: non-zero when there are errors, or (with [ci]) any
/// issue at all.
Future<int> runDoctor({
  required Logger logger,
  required Directory root,
  bool ci = false,
}) async {
  final projectName = detectProjectName(root: root);
  logger.info('Forge doctor — checking "$projectName"');
  logger.info('');

  final issues = <_Issue>[];

  // --- core scaffolding ---
  const coreFiles = [
    'lib/core/di/core_module_container.dart',
    'lib/core/domain/api/api_result.dart',
    'lib/core/domain/usecase/use_case.dart',
    'lib/core/presentation/manager/custom_provider.dart',
    'lib/core/presentation/manager/custom_state.dart',
  ];
  for (final rel in coreFiles) {
    if (!File(p.join(root.path, rel)).existsSync()) {
      issues.add(_Issue.error('Missing core file: $rel'));
    }
  }

  // --- features ---
  final featuresDir = Directory(p.join(root.path, 'lib', 'features'));
  if (!featuresDir.existsSync()) {
    issues.add(_Issue.warn('No lib/features directory yet.'));
  } else {
    final featureDirs = featuresDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final fd in featureDirs) {
      _checkFeature(fd, issues);
    }
  }

  // --- report ---
  final errors = issues.where((i) => i.isError).toList();
  final warns = issues.where((i) => !i.isError).toList();

  for (final i in errors) {
    logger.err('  ✗ ${i.message}');
  }
  for (final i in warns) {
    logger.warn('  • ${i.message}');
  }

  logger.info('');
  if (issues.isEmpty) {
    logger.success('All checks passed — project conforms to the standard.');
    return 0;
  }
  logger.info('${errors.length} error(s), ${warns.length} warning(s).');

  if (ci) return issues.isEmpty ? 0 : 1;
  return errors.isEmpty ? 0 : 1;
}

void _checkFeature(Directory featureDir, List<_Issue> issues) {
  final f = p.basename(featureDir.path);
  final pascal = pascalCase(f);

  // Required files (bare feature shape).
  final required = <String, String>{
    'data/remote/service/${f}_api_service.dart': 'class ${pascal}ApiService',
    'data/repository/${f}_repository_impl.dart':
        'class ${pascal}RepositoryImpl',
    'domain/repository/${f}_repository.dart': 'class ${pascal}Repository',
    'presentation/manager/${f}_provider.dart': 'class ${pascal}Provider',
    'presentation/manager/${f}_state.dart': 'class ${pascal}State',
    'di/${f}_module.dart': 'class ${pascal}Module',
  };

  required.forEach((rel, expectedDecl) {
    final file = File(p.join(featureDir.path, rel));
    if (!file.existsSync()) {
      issues.add(_Issue.error('[$f] missing $rel'));
      return;
    }
    final content = file.readAsStringSync();
    if (!content.contains(expectedDecl)) {
      issues.add(_Issue.warn('[$f] $rel should declare `$expectedDecl`'));
    }
  });

  // Provider should be @injectable so get_it can construct it.
  final provider = File(
    p.join(featureDir.path, 'presentation', 'manager', '${f}_provider.dart'),
  );
  if (provider.existsSync() &&
      !provider.readAsStringSync().contains('@injectable')) {
    issues.add(_Issue.warn('[$f] provider is not annotated @injectable'));
  }
}

class _Issue {
  _Issue.error(this.message) : isError = true;
  _Issue.warn(this.message) : isError = false;

  final String message;
  final bool isError;
}
