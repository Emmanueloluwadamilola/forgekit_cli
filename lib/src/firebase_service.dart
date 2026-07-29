import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'config_service.dart';
import 'service_wiring_service.dart';
import 'utils.dart';

/// Firebase capabilities `forgekit add firebase` can generate today.
///
/// Order is meaningful: services are wired into `main.dart` in this sequence,
/// and each is appended ahead of the `// forgekit:service-initializers` marker.
/// Crashlytics is first so its error handlers are installed before the later
/// services can throw.
const firebaseCapabilities = <String>[
  'crashlytics',
  'analytics',
  'push',
  'remote_config',
];

/// Capabilities the command accepts but has not implemented.
///
/// Parsed rather than rejected by `--features` so the user gets a specific
/// "not available yet" message instead of a generic allowed-values error.
const plannedFirebaseCapabilities = <String>['backend'];

/// Every value `--features` accepts.
const allFirebaseCapabilityValues = <String>[
  ...firebaseCapabilities,
  ...plannedFirebaseCapabilities,
];

/// Human labels used by the interactive picker.
const firebaseCapabilityLabels = <String, String>{
  'crashlytics': 'crashlytics — crash and error reporting',
  'analytics': 'analytics — event and screen tracking',
  'push': 'push — Cloud Messaging notifications',
  'remote_config': 'remote_config — Remote Config flags and values',
};

/// The pubspec dependency each capability requires, at its tested baseline.
const _firebaseDependencies = <String, (String, String)>{
  'core': ('firebase_core', '^4.12.1'),
  'crashlytics': ('firebase_crashlytics', '^5.2.3'),
  'analytics': ('firebase_analytics', '^12.4.2'),
  'push': ('firebase_messaging', '^16.2.0'),
  'remote_config': ('firebase_remote_config', '^6.4.0'),
};

/// The result of validating a requested capability list.
typedef FirebaseCapabilitySelection = ({
  List<String> capabilities,
  String? error,
});

/// Normalises and validates `--features` values.
///
/// Returns the deduplicated, canonically ordered capability list, or an
/// actionable error message. Pure so the messages can be asserted directly.
FirebaseCapabilitySelection resolveFirebaseCapabilities(
  List<String> requested,
) {
  final normalized = requested
      .map((value) => value.trim().toLowerCase().replaceAll('-', '_'))
      .where((value) => value.isNotEmpty)
      .toList();

  if (normalized.isEmpty) {
    return (
      capabilities: const <String>[],
      error: 'Select at least one Firebase capability: '
          '${firebaseCapabilities.join(', ')}.',
    );
  }

  final planned =
      normalized.where(plannedFirebaseCapabilities.contains).toList();
  if (planned.isNotEmpty) {
    return (
      capabilities: const <String>[],
      error: 'Firebase ${planned.join(', ')} is not available yet. '
          'ForgeKit currently generates: ${firebaseCapabilities.join(', ')}.',
    );
  }

  final unknown =
      normalized.where((value) => !firebaseCapabilities.contains(value));
  if (unknown.isNotEmpty) {
    return (
      capabilities: const <String>[],
      error: 'Unknown Firebase capability "${unknown.first}". Choose from: '
          '${firebaseCapabilities.join(', ')}.',
    );
  }

  // Canonical order, so generated output does not depend on argument order.
  return (
    capabilities:
        firebaseCapabilities.where(normalized.contains).toList(growable: false),
    error: null,
  );
}

/// Generates the requested Firebase capabilities and wires them into startup.
///
/// Each capability produces one service in `lib/services/`, registered in DI
/// and initialised before `runApp`, per §6 of the Architecture Standard.
/// `Firebase.initializeApp` is inserted ahead of the DI bootstrap.
Future<int> addFirebase({
  required List<String> capabilities,
  required Directory root,
  required Logger logger,
  required bool runBuildRunner,
  bool runPackageCommands = true,
}) async {
  final selection = resolveFirebaseCapabilities(capabilities);
  if (selection.error != null) {
    logger.err(selection.error!);
    return 1;
  }
  final selected = selection.capabilities;

  final config = loadForgeKitConfig(root: root);
  if (!creatableArchitectureProfiles.contains(config.architecture)) {
    logger.err(
      'Firebase generation is not available for the '
      '"${config.architecture}" adoption profile.',
    );
    return 1;
  }

  // flutterfire owns platform registration and the native config files. Refuse
  // rather than generate code that references a DefaultFirebaseOptions class
  // that does not exist, or that silently misconfigures on web.
  final optionsFile = File(p.join(root.path, 'lib', 'firebase_options.dart'));
  if (!optionsFile.existsSync()) {
    logger
      ..err('No lib/firebase_options.dart found.')
      ..err(
        'ForgeKit generates the application wiring, but Firebase project '
        'registration and the native config files belong to the FlutterFire '
        'CLI.',
      )
      ..info('')
      ..info('Run this first, then retry:')
      ..info('  dart pub global activate flutterfire_cli')
      ..info('  flutterfire configure');
    return 1;
  }

  final modular = config.architecture == 'modular';
  final projectName = detectProjectName(root: root);
  final servicesDir = Directory(p.join(root.path, 'lib', 'services'));

  // Pre-flight every target before writing anything, so a partially applicable
  // invocation fails cleanly instead of half-generating.
  final planned = <String, File>{};
  for (final capability in selected) {
    final file = File(
      p.join(servicesDir.path, '${_serviceSnake(capability)}_service.dart'),
    );
    if (file.existsSync()) {
      logger
        ..err(
          'Service already exists: '
          '${p.relative(file.path, from: root.path)}',
        )
        ..info(
          'Remove it first, or drop "$capability" from --features to keep it.',
        );
      return 1;
    }
    planned[capability] = file;
  }

  final progress = logger.progress(
    'Adding Firebase (${selected.join(', ')})',
  );

  try {
    // Every dependency edit first. A constraint conflict on the second
    // capability must not leave the first one's file already on disk.
    _addDependency(root, _firebaseDependencies['core']!);
    for (final capability in selected) {
      _addDependency(root, _firebaseDependencies[capability]!);
    }

    await servicesDir.create(recursive: true);
    for (final capability in selected) {
      await planned[capability]!.writeAsString(
        switch (capability) {
          'crashlytics' => _crashlyticsService(modular: modular),
          'analytics' => _analyticsService(modular: modular),
          'push' => _pushNotificationService(modular: modular),
          'remote_config' => _remoteConfigService(modular: modular),
          _ => throw StateError('Unhandled capability: $capability'),
        },
      );
    }

    // Core initialisation first, then each service's own registration.
    wireFirebaseCoreInitialization(root: root, projectName: projectName);

    for (final capability in selected) {
      final className = _className(capability);
      if (modular) {
        wireModularInitializedService(
          root: root,
          projectName: projectName,
          serviceSnake: _serviceSnake(capability),
          className: className,
          instanceName: _instanceName(capability),
        );
      } else {
        wireGetItInitializedService(
          root: root,
          projectName: projectName,
          serviceSnake: _serviceSnake(capability),
          className: className,
        );
      }
    }
  } on FileSystemException catch (error) {
    progress.fail('Could not generate the Firebase services.');
    logger.err(error.message);
    return 1;
  } on ArgumentError catch (error) {
    progress.fail('Could not update project configuration.');
    logger.err(error.message?.toString() ?? error.toString());
    return 1;
  } on FormatException catch (error) {
    progress.fail('Could not wire Firebase into application startup.');
    logger.err(error.message);
    return 1;
  }

  progress.complete('Added Firebase (${selected.join(', ')}).');

  if (runPackageCommands) {
    final pubGetCode = await runInheritedProjectCommand(
      'flutter',
      ['pub', 'get'],
      root: root,
      logger: logger,
      label: 'flutter pub get',
    );
    if (pubGetCode != 0) return pubGetCode;

    if (!modular && runBuildRunner) {
      final buildCode = await runInheritedProjectCommand(
        'dart',
        ['run', 'build_runner', 'build'],
        root: root,
        logger: logger,
        label: 'build_runner',
      );
      if (buildCode != 0) return buildCode;
    }
  }

  logger
    ..info('')
    ..info('Generated:');
  for (final capability in selected) {
    logger.info('  ${p.relative(planned[capability]!.path, from: root.path)}');
  }
  logger
    ..info('Updated:')
    ..info('  pubspec.yaml')
    ..info('  lib/main.dart')
    ..info(
      modular
          ? '  lib/app/app_module.dart'
          : '  Injectable dependency graph (via build_runner)',
    )
    ..info('')
    ..success('Firebase is initialized before runApp.');

  _reportNativeConfiguration(root: root, logger: logger);

  if (selected.contains('crashlytics')) {
    logger
      ..info('')
      ..info('Crashlytics needs one Gradle change ForgeKit does not make:')
      ..info('  - Add the "com.google.firebase.crashlytics" plugin to '
          'android/app/build.gradle(.kts).')
      ..info('  Without it, Dart errors still report but native Android '
          'crashes and symbol upload do not.')
      ..info('  - Reports are disabled in debug builds by default; see '
          'CrashlyticsService.init.');
  }
  if (selected.contains('analytics')) {
    logger
      ..info('')
      ..info('Analytics screen tracking is not automatic. Attach the '
          'observer to your navigator:')
      ..info('  MaterialApp(navigatorObservers: '
          '[getIt<AnalyticsService>().observer])')
      ..info('  GoRouter(observers: [getIt<AnalyticsService>().observer])');
  }
  if (selected.contains('push')) {
    logger
      ..info('')
      ..info('Push notifications need platform work ForgeKit cannot do:')
      ..info('  - iOS: enable Push Notifications and Background Modes in '
          'Xcode, and upload an APNs key in the Firebase console.')
      ..info('  - Android 13+: POST_NOTIFICATIONS is requested at runtime by '
          'the generated service.');
  }
  if (selected.contains('remote_config')) {
    logger
      ..info('')
      ..info('Set your defaults in RemoteConfigService.defaults before '
          'relying on a fetched value.');
  }

  if (!modular && !runBuildRunner) {
    logger.info(
      'Run `dart run build_runner build` before compiling the app.',
    );
  }
  return 0;
}

/// Warns about native config files the FlutterFire CLI would normally place.
///
/// Reported rather than fatal: a project may legitimately target only one
/// platform, and the missing file for an unused platform is not an error.
void _reportNativeConfiguration({
  required Directory root,
  required Logger logger,
}) {
  final missing = <String>[];
  final android = Directory(p.join(root.path, 'android'));
  final ios = Directory(p.join(root.path, 'ios'));

  if (android.existsSync() &&
      !File(p.join(android.path, 'app', 'google-services.json'))
          .existsSync()) {
    missing.add('android/app/google-services.json');
  }
  if (ios.existsSync() &&
      !File(p.join(ios.path, 'Runner', 'GoogleService-Info.plist'))
          .existsSync()) {
    missing.add('ios/Runner/GoogleService-Info.plist');
  }
  if (missing.isEmpty) return;

  logger
    ..info('')
    ..warn(
      'Missing native Firebase configuration: ${missing.join(', ')}. '
      'Run `flutterfire configure` and select those platforms.',
    );
}

/// The service name *stem*, without the `_service` suffix.
///
/// `wireGetItInitializedService` and `wireModularInitializedService` append
/// `_service` themselves when building the import URI, so passing an
/// already-suffixed name here produces `..._service_service.dart`. Matches the
/// convention in `storage_service.dart` and `generic_service.dart`.
String _serviceSnake(String capability) => switch (capability) {
      'crashlytics' => 'crashlytics',
      'analytics' => 'analytics',
      'push' => 'push_notification',
      'remote_config' => 'remote_config',
      _ => throw StateError('Unhandled capability: $capability'),
    };

String _className(String capability) => switch (capability) {
      'crashlytics' => 'CrashlyticsService',
      'analytics' => 'AnalyticsService',
      'push' => 'PushNotificationService',
      'remote_config' => 'RemoteConfigService',
      _ => throw StateError('Unhandled capability: $capability'),
    };

String _instanceName(String capability) => switch (capability) {
      'crashlytics' => 'crashlyticsService',
      'analytics' => 'analyticsService',
      'push' => 'pushNotificationService',
      'remote_config' => 'remoteConfigService',
      _ => throw StateError('Unhandled capability: $capability'),
    };

void _addDependency(Directory root, (String, String) dependency) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw const FileSystemException('No pubspec.yaml at the project root.');
  }

  final editor = YamlEditor(pubspec.readAsStringSync());
  final dependencies = _tryParse(editor, ['dependencies']);

  if (dependencies is! YamlMap) {
    editor.update(['dependencies'], {dependency.$1: dependency.$2});
  } else if (!dependencies.containsKey(dependency.$1)) {
    editor.update(['dependencies', dependency.$1], dependency.$2);
  } else {
    final existing = dependencies[dependency.$1];
    if (existing is! String) {
      throw ArgumentError(
        'Existing ${dependency.$1} dependency uses a non-hosted source. '
        'Review and update it manually before generating Firebase services.',
      );
    }
    final target = Version.parse(dependency.$2.substring(1));
    final constraint = VersionConstraint.parse(existing);
    if (!constraint.allows(target)) {
      throw ArgumentError(
        'Existing ${dependency.$1} constraint "$existing" does not allow the '
        'tested ${dependency.$2} baseline. Update and migrate the dependency '
        'before generating Firebase services.',
      );
    }
    return;
  }
  pubspec.writeAsStringSync(editor.toString());
}

YamlNode? _tryParse(YamlEditor editor, List<Object> path) {
  try {
    return editor.parseAt(path);
  } on ArgumentError {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------

String _injectableHeader({required bool modular}) =>
    modular ? '' : "import 'package:injectable/injectable.dart';\n";

String _lazySingleton({required bool modular}) =>
    modular ? '' : '@lazySingleton\n';

/// Modular projects have no Injectable graph, so the composition root binds a
/// top-level instance instead. `wireModularInitializedService` references this
/// name in both `app_module.dart` and `main.dart`, so the declaration has to
/// exist in the generated file.
String _modularInstance({
  required bool modular,
  required String className,
  required String instanceName,
}) =>
    modular ? '\nfinal $instanceName = $className();\n' : '';

/// Declared once per generated service file, above the class.
const _platformSetDeclaration = '''
/// Platforms with a native implementation of this plugin.
const _supportedPlatforms = <TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
};
''';

/// The first statement of every generated `init()`.
///
/// `create app` offers all six Flutter platforms, but no Firebase plugin
/// implements all of them. Calling into a missing implementation throws
/// `MissingPluginException`, and because `init()` is awaited before `runApp`,
/// an unguarded call would abort startup on those targets instead of quietly
/// doing nothing.
///
/// On web `defaultTargetPlatform` reports the *browser's* host platform, so it
/// can be `android` or `iOS`. `kIsWeb` therefore has to be tested separately
/// rather than inferred from the set.
String _platformGuard({required bool webSupported}) {
  final condition = webSupported
      ? '!kIsWeb && !_supportedPlatforms.contains(defaultTargetPlatform)'
      : 'kIsWeb || !_supportedPlatforms.contains(defaultTargetPlatform)';
  final unsupported =
      webSupported ? 'Windows or Linux' : 'web, Windows, or Linux';
  return '''    // Not implemented on $unsupported. init() is awaited before
    // runApp, so an unguarded call would abort startup rather than degrade.
    if ($condition) {
      return;
    }

''';
}

String _crashlyticsService({required bool modular}) => '''
import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
${_injectableHeader(modular: modular)}
$_platformSetDeclaration
/// Firebase Crashlytics.
///
/// Initialized before the other Firebase services so its error handlers are
/// installed as early as possible. Errors thrown before [init] runs — during
/// `configureDependencies()`, for example — are not captured.
${_lazySingleton(modular: modular)}class CrashlyticsService {
  CrashlyticsService();

  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  bool _initialized = false;

  /// Idempotent. Safe to call again after a hot restart.
  Future<void> init() async {
    if (_initialized) return;
${_platformGuard(webSupported: false)}    _initialized = true;

    // Debug builds would otherwise fill the dashboard with crashes you caused
    // deliberately. Flip this if you are testing the integration itself.
    await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

    // Errors raised inside the Flutter framework: build, layout, and paint.
    FlutterError.onError = _crashlytics.recordFlutterFatalError;

    // Everything outside the framework callstack, including unhandled async
    // errors. Returning true marks the error handled, which stops the platform
    // from also printing it.
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Records a handled error. Use this in a `catch` where the app recovers.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    return _crashlytics.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }

  /// Adds a breadcrumb to the next crash report.
  Future<void> log(String message) => _crashlytics.log(message);

  /// Associates crashes with a user. Use an opaque id, never an email or any
  /// other personally identifying value.
  Future<void> setUserIdentifier(String identifier) =>
      _crashlytics.setUserIdentifier(identifier);

  /// Attaches a searchable key/value pair to subsequent reports.
  Future<void> setCustomKey(String key, Object value) =>
      _crashlytics.setCustomKey(key, value);

  /// Whether the previous run ended in a crash. Useful for showing a
  /// "sorry about that" prompt on the next launch.
  Future<bool> didCrashOnPreviousExecution() =>
      _crashlytics.didCrashOnPreviousExecution();
}
${_modularInstance(
      modular: modular,
      className: 'CrashlyticsService',
      instanceName: 'crashlyticsService',
    )}''';

String _analyticsService({required bool modular}) => '''
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
${_injectableHeader(modular: modular)}
$_platformSetDeclaration
/// Firebase Analytics.
///
/// Screen tracking is not automatic. Attach [observer] to your navigator to get
/// `screen_view` events:
///
/// ```dart
/// MaterialApp(navigatorObservers: [getIt<AnalyticsService>().observer])
/// // or, with GoRouter:
/// GoRouter(observers: [getIt<AnalyticsService>().observer], ...)
/// ```
${_lazySingleton(modular: modular)}class AnalyticsService {
  AnalyticsService();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  late final FirebaseAnalyticsObserver _observer =
      FirebaseAnalyticsObserver(analytics: _analytics);

  bool _initialized = false;

  /// A single observer instance. Creating one per call would register
  /// duplicate listeners and double-count screen views.
  FirebaseAnalyticsObserver get observer => _observer;

  /// The underlying instance, for APIs this service does not wrap.
  FirebaseAnalytics get analytics => _analytics;

  /// Idempotent. Safe to call again after a hot restart.
  Future<void> init() async {
    if (_initialized) return;
${_platformGuard(webSupported: true)}    _initialized = true;

    // Debug builds still report. Use the Firebase DebugView to inspect them,
    // or pass `!kDebugMode` here to keep development traffic out entirely.
    await _analytics.setAnalyticsCollectionEnabled(true);
  }

  /// Event names must be snake_case, 1-40 characters, and must not use a
  /// reserved prefix such as `firebase_`, `google_`, or `ga_`.
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) =>
      _analytics.logEvent(name: name, parameters: parameters);

  Future<void> logScreenView(String screenName, {String? screenClass}) =>
      _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      );

  Future<void> logLogin({String? method}) =>
      _analytics.logLogin(loginMethod: method);

  Future<void> logSignUp({required String method}) =>
      _analytics.logSignUp(signUpMethod: method);

  /// Pass null on sign-out so later events are not attributed to the previous
  /// user. Use an opaque id, never an email.
  Future<void> setUserId(String? id) => _analytics.setUserId(id: id);

  /// User properties are for segmentation, not for storing data. Firebase
  /// allows 25 per project.
  Future<void> setUserProperty(String name, String? value) =>
      _analytics.setUserProperty(name: name, value: value);

  Future<void> setAnalyticsCollectionEnabled({required bool enabled}) =>
      _analytics.setAnalyticsCollectionEnabled(enabled);
}
${_modularInstance(
      modular: modular,
      className: 'AnalyticsService',
      instanceName: 'analyticsService',
    )}''';

String _pushNotificationService({required bool modular}) => '''
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
${_injectableHeader(modular: modular)}
$_platformSetDeclaration
/// Handles messages delivered while the app is backgrounded or terminated.
///
/// Must stay a top-level function annotated `@pragma('vm:entry-point')`: the
/// platform runs it in a fresh isolate that shares none of the application's
/// state, so it cannot be a method and cannot reach your DI graph.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // TODO: handle the background message. Keep this fast and side-effect free;
  // the isolate is torn down as soon as it returns.
  debugPrint('Background message: \${message.messageId}');
}

/// Firebase Cloud Messaging.
///
/// Registered in DI and initialized before `runApp`, so a token is available
/// as soon as the first screen builds.
${_lazySingleton(modular: modular)}class PushNotificationService {
  PushNotificationService();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final StreamController<RemoteMessage> _foregroundController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<RemoteMessage> _openedController =
      StreamController<RemoteMessage>.broadcast();

  StreamSubscription<RemoteMessage>? _onMessage;
  StreamSubscription<RemoteMessage>? _onMessageOpened;
  StreamSubscription<String>? _onTokenRefresh;

  bool _initialized = false;
  String? _token;

  /// Messages received while the app is in the foreground.
  ///
  /// The OS does not display these automatically. Show your own in-app banner,
  /// or pair this with a local-notifications package.
  Stream<RemoteMessage> get onMessage => _foregroundController.stream;

  /// Emits when the user taps a notification and opens the app.
  Stream<RemoteMessage> get onMessageOpenedApp => _openedController.stream;

  /// The current FCM registration token, available after [init].
  String? get token => _token;

  /// Idempotent. Safe to call again after a hot restart.
  Future<void> init() async {
    if (_initialized) return;
${_platformGuard(webSupported: true)}    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _messaging.requestPermission();

    // iOS shows nothing in the foreground unless this is set.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _token = await _messaging.getToken();

    _onMessage = FirebaseMessaging.onMessage.listen(
      _foregroundController.add,
    );
    _onMessageOpened = FirebaseMessaging.onMessageOpenedApp.listen(
      _openedController.add,
    );
    _onTokenRefresh = _messaging.onTokenRefresh.listen((refreshed) {
      _token = refreshed;
      // TODO: send the refreshed token to your backend.
    });

    // A notification that launched the app from a terminated state is not
    // delivered through onMessageOpenedApp, so it is replayed here.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _openedController.add(initialMessage);
    }
  }

  Future<void> subscribeToTopic(String topic) =>
      _messaging.subscribeToTopic(topic);

  Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  /// Invalidates the current token. Call on sign-out so a signed-out device
  /// stops receiving messages addressed to the previous user.
  Future<void> deleteToken() async {
    await _messaging.deleteToken();
    _token = null;
  }

  Future<void> dispose() async {
    await _onMessage?.cancel();
    await _onMessageOpened?.cancel();
    await _onTokenRefresh?.cancel();
    await _foregroundController.close();
    await _openedController.close();
    _initialized = false;
  }
}
${_modularInstance(
      modular: modular,
      className: 'PushNotificationService',
      instanceName: 'pushNotificationService',
    )}''';

String _remoteConfigService({required bool modular}) => '''
import 'dart:async';

// FirebaseException comes from firebase_core; firebase_remote_config only
// re-exports its own types, so importing it here is required for the catch.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
${_injectableHeader(modular: modular)}
$_platformSetDeclaration
/// Firebase Remote Config.
///
/// Registered in DI and initialized before `runApp`, so the first frame reads
/// activated values rather than defaults.
${_lazySingleton(modular: modular)}class RemoteConfigService {
  RemoteConfigService();

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  StreamSubscription<RemoteConfigUpdate>? _onConfigUpdated;
  bool _initialized = false;

  /// Values used before the first successful fetch, and whenever a key is
  /// missing from the server payload.
  ///
  /// Every key your app reads must appear here. A key that is absent both
  /// locally and remotely returns a zero value rather than throwing, which is
  /// a hard bug to trace.
  static const Map<String, Object> defaults = <String, Object>{
    // TODO: declare your Remote Config keys, for example:
    // 'welcome_message': 'Hello',
    // 'feature_x_enabled': false,
  };

  /// Idempotent. Safe to call again after a hot restart.
  Future<void> init() async {
    if (_initialized) return;
${_platformGuard(webSupported: true)}    _initialized = true;

    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Remote Config throttles aggressively in production. Keep this at
        // zero only while developing.
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ),
    );
    await _remoteConfig.setDefaults(defaults);

    try {
      await _remoteConfig.fetchAndActivate();
    } on FirebaseException catch (error) {
      // Never block startup on config. Defaults are already active.
      debugPrint('Remote Config fetch failed: \${error.code}');
    } on TimeoutException {
      debugPrint('Remote Config fetch timed out; using defaults.');
    }

    _onConfigUpdated = _remoteConfig.onConfigUpdated.listen((event) async {
      await _remoteConfig.activate();
    });
  }

  /// Emits whenever the server pushes a new config version.
  Stream<RemoteConfigUpdate> get onConfigUpdated =>
      _remoteConfig.onConfigUpdated;

  String getString(String key) => _remoteConfig.getString(key);

  bool getBool(String key) => _remoteConfig.getBool(key);

  int getInt(String key) => _remoteConfig.getInt(key);

  double getDouble(String key) => _remoteConfig.getDouble(key);

  /// All currently active values, useful for a debug screen.
  Map<String, RemoteConfigValue> getAll() => _remoteConfig.getAll();

  /// Forces a fetch outside the normal interval. Returns whether new values
  /// were activated.
  Future<bool> refresh() => _remoteConfig.fetchAndActivate();

  Future<void> dispose() async {
    await _onConfigUpdated?.cancel();
    _initialized = false;
  }
}
${_modularInstance(
      modular: modular,
      className: 'RemoteConfigService',
      instanceName: 'remoteConfigService',
    )}''';
