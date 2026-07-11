import 'package:mason/mason.dart';

String _snake(String input) {
  return input
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .toLowerCase();
}

void run(HookContext context) {
  final name = (context.vars['name'] as String?) ?? '';
  final project = (context.vars['projectName'] as String?) ?? 'app';
  final snake = _snake(name);

  context.logger.success('Widget generated.');
  context.logger.info('Import it with:');
  context.logger.info('');
  context.logger.info(
    "  import 'package:$project/core/presentation/widgets/$snake.dart';",
  );
}
