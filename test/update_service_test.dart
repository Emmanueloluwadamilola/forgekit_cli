import 'package:forgekit/src/command_runner.dart';
import 'package:forgekit/src/update_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:test/test.dart';

void main() {
  const revision = '0123456789abcdef0123456789abcdef01234567';

  test('update command requires a complete immutable revision', () async {
    final runner = ForgeCommandRunner(logger: Logger(level: Level.quiet));

    expect(await runner.run(['update']), 64);
    expect(await runner.run(['update', '--ref', 'main']), 64);
    expect(await runner.run(['update', '--ref', '0123456']), 64);
  });

  test('update activates and configures the exact reviewed commit', () async {
    final calls = <(String, List<String>)>[];

    final exitCode = await runUpdate(
      revision: revision,
      logger: Logger(level: Level.quiet),
      executor: (executable, arguments) async {
        calls.add((executable, arguments));
        return 0;
      },
    );

    expect(exitCode, 0);
    expect(calls, hasLength(2));
    expect(calls.first.$1, 'dart');
    expect(calls.first.$2, containsAllInOrder(['--git-ref', revision]));
    expect(
      calls.last.$2,
      ['pub', 'global', 'run', 'forgekit:forgekit', 'setup'],
    );
  });

  test('update service rejects mutable refs before starting a process',
      () async {
    var invoked = false;
    final exitCode = await runUpdate(
      revision: 'main',
      logger: Logger(level: Level.quiet),
      executor: (_, __) async {
        invoked = true;
        return 0;
      },
    );

    expect(exitCode, 64);
    expect(invoked, isFalse);
  });
}
