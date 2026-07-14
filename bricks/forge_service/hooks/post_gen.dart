import 'package:mason/mason.dart';

String _pascal(String input) {
  final parts = input
      .replaceAll(RegExp(r'[_\-\s]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty);
  return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

void run(HookContext context) {
  final name = (context.vars['name'] as String?) ?? '';
  final pascal = _pascal(name);
  final logger = context.logger;

  logger.info('');
  logger.success('${pascal}Service generated in lib/services/.');
  logger.info('');
  logger.info('Next steps:');
  logger.info(
    '  1. Add the init call to your main.dart bootstrap (after '
    'configureDependencies()):',
  );
  logger.info('');
  logger.info('       await getIt<${pascal}Service>().init();');
  logger.info('');
  logger.info('  2. Run code generation to wire up the @lazySingleton:');
  logger.info('');
  logger.info('       dart run build_runner build');
  logger.info('');
}
