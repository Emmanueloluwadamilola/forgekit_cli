import 'dart:io';

import 'package:mason/mason.dart';

String _pascal(String input) {
  final parts = input
      .replaceAll(RegExp(r'[_\-\s]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty);
  return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

String _snake(String input) {
  return input
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .toLowerCase();
}

Future<void> run(HookContext context) async {
  final name = (context.vars['name'] as String?) ?? '';
  final pascal = _pascal(name);
  final snake = _snake(name);
  // camelCase name used for the go_router routes list (e.g. orderHistoryRoutes).
  final camel =
      pascal.isEmpty ? '' : pascal[0].toLowerCase() + pascal.substring(1);
  final useRouter = context.vars['useRouter'] == true;
  final runBuildRunner = context.vars['runBuildRunner'] == true;

  final logger = context.logger;

  logger.info('');
  logger.success('Feature "$pascal" generated.');
  logger.info('');
  logger.info('Next steps:');

  // The go_router routes file is templated for both modes but only has content
  // when go_router is selected. For named routes it renders empty, so remove it.
  final routesFile = File(
    'lib/features/$snake/presentation/${snake}_routes.dart',
  );

  if (useRouter) {
    if (routesFile.existsSync() &&
        routesFile.readAsStringSync().trim().isEmpty) {
      routesFile.deleteSync();
    }
    logger.info('  1. The forgekit command registers ${pascal}Screen in the '
        'named route table. Direct Mason use must integrate it separately.');
  } else {
    logger.info('  1. The forgekit command registers ${camel}Routes in the '
        'central GoRouter. Direct Mason use must integrate it separately.');
  }

  logger.info(
    '  2. Run code generation:',
  );
  logger.info('');
  logger.info('       dart run build_runner build');
  logger.info('');

  if (runBuildRunner) {
    logger.info('Running build_runner...');
    try {
      final result = await Process.run(
        'dart',
        ['run', 'build_runner', 'build'],
      );
      if (result.exitCode == 0) {
        logger.success('build_runner completed successfully.');
      } else {
        logger.err('build_runner exited with code ${result.exitCode}.');
        final out = result.stdout.toString();
        final errOut = result.stderr.toString();
        if (out.trim().isNotEmpty) logger.detail(out);
        if (errOut.trim().isNotEmpty) logger.detail(errOut);
      }
    } catch (e) {
      logger.err(
        'Could not run build_runner automatically ($e). '
        'Please run it manually.',
      );
    }
  }
}
