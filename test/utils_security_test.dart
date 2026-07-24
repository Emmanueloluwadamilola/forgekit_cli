import 'package:forgekit/src/utils.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes project-relative paths for portable output', () {
    expect(toPosixPath(r'assets\env\dev.json'), 'assets/env/dev.json');
    expect(toPosixPath('lib/src/app.dart'), 'lib/src/app.dart');
  });

  test('encodes dollar signs before Retrofit generates Dart string literals',
      () {
    expect(
      encodeRetrofitUrlLiteral(r'/inventory/$tenant/{inventoryId}'),
      '/inventory/%24tenant/{inventoryId}',
    );
    expect(
      encodeRetrofitUrlLiteral(r'https://example.com/$tenant/v1'),
      'https://example.com/%24tenant/v1',
    );
  });
}
