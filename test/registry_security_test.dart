import 'package:forgekit/src/registry_service.dart';
import 'package:test/test.dart';

void main() {
  test('accepts secure registry remotes and local paths', () {
    expect(
      validateRegistryRemote('https://github.com/acme/widgets.git'),
      isNull,
    );
    expect(validateRegistryRemote('git@github.com:acme/widgets.git'), isNull);
    expect(
      validateRegistryRemote('ssh://git@github.com/acme/widgets.git'),
      isNull,
    );
    expect(validateRegistryRemote('../local-widget-registry'), isNull);
  });

  test('rejects plaintext and credential-bearing registry remotes', () {
    expect(
      validateRegistryRemote('http://github.com/acme/widgets.git'),
      contains('not allowed'),
    );
    expect(
      validateRegistryRemote('https://token@github.com/acme/widgets.git'),
      contains('must not embed'),
    );
    expect(
      validateRegistryRemote(
        'https://github.com/acme/widgets.git?access_token=secret',
      ),
      contains('query strings'),
    );
    expect(
      safeRegistryRemoteForDisplay(
        'https://token@github.com/acme/widgets.git',
      ),
      '<redacted insecure or credential-bearing remote>',
    );
  });
}
