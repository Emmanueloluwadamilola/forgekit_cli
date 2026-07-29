import 'dart:io';

import 'package:forgekit/src/firebase_service.dart';
import 'package:forgekit/src/service_wiring_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Logger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_firebase_test_');
    logger = Logger(level: Level.quiet);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('resolveFirebaseCapabilities', () {
    test('accepts the supported capabilities', () {
      final result = resolveFirebaseCapabilities(['push', 'remote_config']);

      expect(result.error, isNull);
      expect(result.capabilities, ['push', 'remote_config']);
    });

    test('accepts crashlytics and analytics', () {
      final result = resolveFirebaseCapabilities(['analytics', 'crashlytics']);

      expect(result.error, isNull);
      // Crashlytics is ordered first so its error handlers install before the
      // other services can throw.
      expect(result.capabilities, ['crashlytics', 'analytics']);
    });

    test('orders a full selection so crashlytics initializes first', () {
      final result = resolveFirebaseCapabilities(
        ['remote_config', 'push', 'analytics', 'crashlytics'],
      );

      expect(result.capabilities, [
        'crashlytics',
        'analytics',
        'push',
        'remote_config',
      ]);
    });

    test('normalises case, whitespace and hyphens', () {
      final result = resolveFirebaseCapabilities([' PUSH ', 'remote-config']);

      expect(result.error, isNull);
      expect(result.capabilities, ['push', 'remote_config']);
    });

    test('returns a canonical order regardless of argument order', () {
      expect(
        resolveFirebaseCapabilities(['remote_config', 'push']).capabilities,
        ['push', 'remote_config'],
      );
    });

    test('deduplicates repeats', () {
      expect(
        resolveFirebaseCapabilities(['push', 'push']).capabilities,
        ['push'],
      );
    });

    test('rejects an empty selection', () {
      final result = resolveFirebaseCapabilities([]);

      expect(result.capabilities, isEmpty);
      expect(result.error, contains('at least one'));
    });

    test('explains that backend is deferred rather than unknown', () {
      final result = resolveFirebaseCapabilities(['backend']);

      expect(result.capabilities, isEmpty);
      expect(result.error, contains('not available yet'));
      // Must name what it can do, so the message is actionable.
      expect(result.error, contains('push'));
      expect(result.error, contains('remote_config'));
    });

    test('rejects backend even when paired with a valid capability', () {
      final result = resolveFirebaseCapabilities(['push', 'backend']);

      expect(result.capabilities, isEmpty);
      expect(result.error, contains('not available yet'));
    });

    test('rejects an unknown capability by name', () {
      final result = resolveFirebaseCapabilities(['firestore']);

      expect(result.error, contains('firestore'));
      expect(result.error, contains('Choose from'));
    });
  });

  group('addFirebase preconditions', () {
    test('refuses without lib/firebase_options.dart', () async {
      _writeCleanProject(root);

      final code = await addFirebase(
        capabilities: ['push'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 1);
      // Nothing may be written when the prerequisite is missing.
      expect(
        Directory(p.join(root.path, 'lib', 'services')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
        isNot(contains('firebase_core')),
      );
    });

    test('refuses an adoption-only architecture profile', () async {
      _writeCleanProject(root, architecture: 'lean');
      _writeFirebaseOptions(root);

      final code = await addFirebase(
        capabilities: ['push'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 1);
    });

    test('refuses when a target service file already exists', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);
      final existing = File(
        p.join(root.path, 'lib', 'services', 'push_notification_service.dart'),
      );
      existing.parent.createSync(recursive: true);
      existing.writeAsStringSync('// mine\n');

      final code = await addFirebase(
        capabilities: ['push', 'remote_config'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 1);
      expect(existing.readAsStringSync(), '// mine\n');
      // Pre-flight must run before any write, so the other capability in the
      // same invocation must not have been generated either.
      expect(
        File(p.join(root.path, 'lib', 'services', 'remote_config_service.dart'))
            .existsSync(),
        isFalse,
      );
    });
  });

  group('addFirebase generation', () {
    test('generates, registers and wires both capabilities', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      final code = await addFirebase(
        capabilities: ['push', 'remote_config'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 0);

      final push = File(
        p.join(root.path, 'lib', 'services', 'push_notification_service.dart'),
      ).readAsStringSync();
      expect(push, contains('class PushNotificationService'));
      expect(push, contains('@lazySingleton'));
      expect(push, contains("import 'package:injectable/injectable.dart';"));
      // The background handler cannot be a method.
      expect(push, contains("@pragma('vm:entry-point')"));
      expect(
        push,
        contains('Future<void> firebaseMessagingBackgroundHandler'),
      );

      final remote = File(
        p.join(root.path, 'lib', 'services', 'remote_config_service.dart'),
      ).readAsStringSync();
      expect(remote, contains('class RemoteConfigService'));
      expect(remote, contains('static const Map<String, Object> defaults'));

      final pubspec =
          File(p.join(root.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('firebase_core:'));
      expect(pubspec, contains('firebase_messaging:'));
      expect(pubspec, contains('firebase_remote_config:'));
    });

    test('generates crashlytics and analytics services', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      final code = await addFirebase(
        capabilities: ['crashlytics', 'analytics'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 0);

      final crashlytics = File(
        p.join(root.path, 'lib', 'services', 'crashlytics_service.dart'),
      ).readAsStringSync();
      expect(crashlytics, contains('class CrashlyticsService'));
      expect(crashlytics, contains('FlutterError.onError'));
      // PlatformDispatcher comes from dart:ui, which must be imported.
      expect(crashlytics, contains('PlatformDispatcher.instance.onError'));
      expect(crashlytics, contains("import 'dart:ui';"));
      expect(crashlytics, contains('setCrashlyticsCollectionEnabled'));

      final analytics = File(
        p.join(root.path, 'lib', 'services', 'analytics_service.dart'),
      ).readAsStringSync();
      expect(analytics, contains('class AnalyticsService'));
      // A single observer instance; a per-call getter would double-count
      // screen views.
      expect(analytics, contains('late final FirebaseAnalyticsObserver'));
      expect(analytics, contains('FirebaseAnalyticsObserver get observer'));

      final pubspec =
          File(p.join(root.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('firebase_crashlytics:'));
      expect(pubspec, contains('firebase_analytics:'));
    });

    test('guards every service against unsupported platforms', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      await addFirebase(
        capabilities: ['crashlytics', 'analytics', 'push', 'remote_config'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      // `create app` offers Windows and Linux, where these plugins have no
      // implementation. init() is awaited before runApp, so an unguarded call
      // would throw MissingPluginException and abort startup.
      for (final name in [
        'crashlytics_service',
        'analytics_service',
        'push_notification_service',
        'remote_config_service',
      ]) {
        final source =
            File(p.join(root.path, 'lib', 'services', '$name.dart'))
                .readAsStringSync();
        expect(
          source,
          contains('_supportedPlatforms.contains(defaultTargetPlatform)'),
          reason: '$name must guard its init()',
        );
        expect(
          source,
          contains("import 'package:flutter/foundation.dart';"),
          reason: '$name needs defaultTargetPlatform',
        );
      }

      // Crashlytics has no web implementation; the other three do.
      final crashlytics = File(
        p.join(root.path, 'lib', 'services', 'crashlytics_service.dart'),
      ).readAsStringSync();
      expect(crashlytics, contains('if (kIsWeb ||'));

      final analytics = File(
        p.join(root.path, 'lib', 'services', 'analytics_service.dart'),
      ).readAsStringSync();
      expect(analytics, contains('if (!kIsWeb &&'));
    });

    test('wires crashlytics before the other services', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      await addFirebase(
        capabilities: ['push', 'crashlytics'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      final main =
          File(p.join(root.path, 'lib', 'main.dart')).readAsStringSync();
      expect(
        main.indexOf('CrashlyticsService>().init()'),
        lessThan(main.indexOf('PushNotificationService>().init()')),
      );
    });

    test('adds only the packages the selection needs', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      await addFirebase(
        capabilities: ['remote_config'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      final pubspec =
          File(p.join(root.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('firebase_remote_config:'));
      expect(pubspec, isNot(contains('firebase_messaging:')));
      expect(pubspec, isNot(contains('firebase_crashlytics:')));
      expect(pubspec, isNot(contains('firebase_analytics:')));
      final push = File(
        p.join(root.path, 'lib', 'services', 'push_notification_service.dart'),
      );
      expect(push.existsSync(), isFalse);
    });

    test('initializes Firebase before the dependency graph', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      await addFirebase(
        capabilities: ['push'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      final main =
          File(p.join(root.path, 'lib', 'main.dart')).readAsStringSync();
      expect(main, contains('Firebase.initializeApp('));
      expect(main, contains('DefaultFirebaseOptions.currentPlatform'));
      expect(
        main,
        contains("import 'package:firebase_core/firebase_core.dart';"),
      );
      expect(main, contains('firebase_options.dart'));
      // Regression: the wiring helper appends `_service` to the name it is
      // given, so passing an already-suffixed stem produced an import of
      // `push_notification_service_service.dart` and a project that would not
      // compile.
      expect(
        main,
        contains(
          "import 'package:sample_app/services/push_notification_service.dart';",
        ),
      );
      expect(main, isNot(contains('_service_service.dart')));

      // Ordering is the contract: a lazySingleton resolved during DI setup
      // would otherwise construct before Firebase existed.
      expect(
        main.indexOf('Firebase.initializeApp('),
        lessThan(main.indexOf('await configureDependencies();')),
      );
      // The service initializer still goes after DI.
      expect(
        main.indexOf('await configureDependencies();'),
        lessThan(main.indexOf('PushNotificationService')),
      );
    });

    test('is idempotent across a second invocation', () async {
      _writeCleanProject(root);
      _writeFirebaseOptions(root);

      await addFirebase(
        capabilities: ['push'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );
      final code = await addFirebase(
        capabilities: ['remote_config'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 0);
      final main = File(p.join(root.path, 'lib', 'main.dart'))
          .readAsStringSync();
      expect(
        'Firebase.initializeApp('.allMatches(main).length,
        1,
        reason: 'core initialization must not be duplicated',
      );
      expect(
        "import 'package:firebase_core/firebase_core.dart';"
            .allMatches(main)
            .length,
        1,
      );
    });

    test('omits injectable annotations on the modular profile', () async {
      _writeModularProject(root);
      _writeFirebaseOptions(root);

      final code = await addFirebase(
        capabilities: ['push'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 0);
      final push = File(
        p.join(root.path, 'lib', 'services', 'push_notification_service.dart'),
      ).readAsStringSync();
      expect(push, isNot(contains('@lazySingleton')));
      expect(push, isNot(contains('injectable')));
      // Modular binds a top-level instance; both the module and main.dart
      // reference this exact name, so it must be declared here.
      expect(
        push,
        contains('final pushNotificationService = PushNotificationService();'),
      );

      final module = File(p.join(root.path, 'lib', 'app', 'app_module.dart'))
          .readAsStringSync();
      expect(
        module,
        contains(
          '..addInstance<PushNotificationService>(pushNotificationService)',
        ),
      );

      final main = File(p.join(root.path, 'lib', 'main.dart'))
          .readAsStringSync();
      expect(main, contains('await pushNotificationService.init();'));
    });

    test('rejects an incompatible existing dependency constraint', () async {
      _writeCleanProject(root, extraDependencies: '  firebase_core: ^1.0.0\n');
      _writeFirebaseOptions(root);

      final code = await addFirebase(
        capabilities: ['push'],
        root: root,
        logger: logger,
        runBuildRunner: false,
        runPackageCommands: false,
      );

      expect(code, 1);
    });
  });

  group('wireFirebaseCoreInitialization', () {
    test('anchors after ensureInitialized when there is no DI bootstrap', () {
      _writeModularProject(root);

      wireFirebaseCoreInitialization(root: root, projectName: 'sample_app');

      final main = File(p.join(root.path, 'lib', 'main.dart'))
          .readAsStringSync();
      expect(
        main.indexOf('WidgetsFlutterBinding.ensureInitialized();'),
        lessThan(main.indexOf('Firebase.initializeApp(')),
      );
      expect(
        main.indexOf('Firebase.initializeApp('),
        lessThan(main.indexOf('runApp(')),
      );
    });

    test('throws when main.dart is absent', () {
      Directory(p.join(root.path, 'lib')).createSync(recursive: true);

      expect(
        () => wireFirebaseCoreInitialization(
          root: root,
          projectName: 'sample_app',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

void _writeCleanProject(
  Directory root, {
  String architecture = 'clean',
  String extraDependencies = '',
}) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ">=3.8.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
$extraDependencies''');
  File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync('''
version: 1
architecture: $architecture
state_management: provider
router: named
dependency_injection: ${architecture == 'modular' ? 'flutter_modular' : 'injectable'}
models: json_serializable
api_client: retrofit
generation:
  format: false
  build_runner: true
testing:
  coverage: 80
''');
  final main = File(p.join(root.path, 'lib', 'main.dart'));
  main.parent.createSync(recursive: true);
  main.writeAsStringSync('''
import 'package:flutter/material.dart';

import 'core/di/core_module_container.dart';
import 'core/presentation/app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await configureDependencies();

  // forgekit:service-initializers

  runApp(const App());
}
''');
}

void _writeModularProject(Directory root) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ">=3.8.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
  File(p.join(root.path, 'forgekit.yaml')).writeAsStringSync('''
version: 1
architecture: modular
state_management: provider
router: modular
dependency_injection: flutter_modular
models: json_serializable
api_client: retrofit
generation:
  format: false
  build_runner: true
testing:
  coverage: 80
''');
  final main = File(p.join(root.path, 'lib', 'main.dart'));
  main.parent.createSync(recursive: true);
  main.writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'app/app.dart';
import 'app/app_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // forgekit:service-initializers

  runApp(
    ModularApp(module: appModule, child: const App()),
  );
}
''');
  final module = File(p.join(root.path, 'lib', 'app', 'app_module.dart'));
  module.parent.createSync(recursive: true);
  module.writeAsStringSync('''
import 'package:flutter_modular/flutter_modular.dart';

final appModule = Module(
  binds: (i) => i
    // forgekit:services
    ,
  routes: (r) => r
    // forgekit:routes
    ,
);
''');
}

void _writeFirebaseOptions(Directory root) {
  final file = File(p.join(root.path, 'lib', 'firebase_options.dart'));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('''
// Generated by the FlutterFire CLI in a real project.
class DefaultFirebaseOptions {
  static Object get currentPlatform => throw UnimplementedError();
}
''');
}
