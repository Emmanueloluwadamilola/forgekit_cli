import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('Provider feature state remains mutable for generated operations', () {
    final template = File(
      p.join(
        Directory.current.path,
        'bricks',
        'forge_feature',
        '__brick__',
        'lib',
        'features',
        '{{name.snakeCase()}}',
        'presentation',
        'manager',
        '{{name.snakeCase()}}_provider.dart',
      ),
    ).readAsStringSync();

    expect(
      template,
      contains(
        '{{name.pascalCase()}}State _state = '
        'const {{name.pascalCase()}}State();',
      ),
    );
    expect(
      template,
      isNot(contains('final {{name.pascalCase()}}State _state')),
    );
  });
}
