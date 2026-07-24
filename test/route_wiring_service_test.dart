import 'dart:io';

import 'package:forgekit/src/config_service.dart';
import 'package:forgekit/src/route_wiring_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_routes_test_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('registers a Clean named route exactly once', () {
    final app = _write(
      root,
      'lib/core/presentation/app/app.dart',
      _namedApp,
    );
    const config = ForgeKitConfig(router: 'named');

    for (var i = 0; i < 2; i++) {
      registerFeatureRoute(
        root: root,
        config: config,
        projectName: 'sample_app',
        feature: 'orders',
      );
    }

    final source = app.readAsStringSync();
    expect(
      source,
      contains("import 'package:sample_app/features/orders/presentation/"
          "screens/orders_screen.dart';"),
    );
    expect(source, contains('OrdersScreen.id: (_) => const OrdersScreen(),'));
    expect(_occurrences(source, '// forgekit:route:orders'), 1);
    _expectDartParses(root, app.path);
  });

  test('registers MVVM GoRouter feature and additional screen routes', () {
    final app = _write(
      root,
      'lib/ui/core/app/app.dart',
      _goRouterApp,
    );
    const config = ForgeKitConfig(
      architecture: 'mvvm',
      router: 'go_router',
    );

    registerFeatureRoute(
      root: root,
      config: config,
      projectName: 'sample_app',
      feature: 'orders',
    );
    registerScreenRoute(
      root: root,
      config: config,
      projectName: 'sample_app',
      feature: 'orders',
      screenName: 'order_detail',
    );

    final source = app.readAsStringSync();
    expect(source, contains('...ordersRoutes,'));
    expect(source, contains('path: OrderDetailScreen.id'));
    expect(source, contains('name: OrderDetailScreen.id'));
    expect(source, contains('// forgekit:route:orders:order_detail:start'));
    _expectDartParses(root, app.path);
  });

  test('registers a child route in a Modular feature module', () {
    final module = _write(
      root,
      'lib/modules/orders/orders_module.dart',
      _modularModule,
    );
    const config = ForgeKitConfig(
      architecture: 'modular',
      router: 'modular',
      dependencyInjection: 'flutter_modular',
    );

    registerScreenRoute(
      root: root,
      config: config,
      projectName: 'sample_app',
      feature: 'orders',
      screenName: 'order_detail',
    );

    final source = module.readAsStringSync();
    expect(source, contains("import 'presentation/order_detail_screen.dart';"));
    expect(
      source,
      contains("..route('/order_detail', child: (_, _) => const "
          'OrderDetailScreen())'),
    );
    _expectDartParses(root, module.path);
  });

  test('feature cleanup removes owned routes but preserves user routes', () {
    final app = _write(
      root,
      'lib/core/presentation/app/app.dart',
      _goRouterApp,
    );
    const config = ForgeKitConfig(router: 'go_router');
    registerFeatureRoute(
      root: root,
      config: config,
      projectName: 'sample_app',
      feature: 'orders',
    );
    registerScreenRoute(
      root: root,
      config: config,
      projectName: 'sample_app',
      feature: 'orders',
      screenName: 'details',
    );
    registerFeatureRoute(
      root: root,
      config: config,
      projectName: 'sample_app',
      feature: 'orders_archive',
    );

    unregisterFeatureRoutes(
      root: root,
      config: config,
      feature: 'orders',
    );

    final source = app.readAsStringSync();
    expect(source, isNot(contains('route:orders:details')));
    expect(source, isNot(contains('...ordersRoutes')));
    expect(source, contains('...ordersArchiveRoutes'));
    expect(source, contains("path: '/manual'"));
    _expectDartParses(root, app.path);
  });

  test('feature cleanup removes a named route wrapped by dart format', () {
    final app = _write(
      root,
      'lib/core/presentation/app/app.dart',
      '''
import 'package:flutter/material.dart';
import 'package:sample_app/features/inventory/presentation/screens/inventory_screen.dart'; // forgekit:route-import:inventory
// forgekit:route-imports

final routes = <String, WidgetBuilder>{
  '/': (_) => const SizedBox(),
  InventoryScreen.id: (_) =>
      const InventoryScreen(), // forgekit:route:inventory
  // forgekit:named-routes
};
''',
    );

    unregisterFeatureRoutes(
      root: root,
      config: const ForgeKitConfig(router: 'named'),
      feature: 'inventory',
    );

    final source = app.readAsStringSync();
    expect(source, isNot(contains('InventoryScreen')));
    expect(source, isNot(contains('route:inventory')));
    expect(source, contains("'/': (_) => const SizedBox()"));
    _expectDartParses(root, app.path);
  });
}

File _write(Directory root, String relativePath, String source) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
  return file;
}

int _occurrences(String source, String pattern) =>
    RegExp(RegExp.escape(pattern)).allMatches(source).length;

void _expectDartParses(Directory root, String path) {
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['format', '--output=none', path],
    workingDirectory: root.path,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

const _namedApp = '''
import 'package:flutter/material.dart';
// forgekit:route-imports

final routes = <String, WidgetBuilder>{
  '/': (_) => const SizedBox(),
  // forgekit:named-routes
};
''';

const _goRouterApp = '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// forgekit:route-imports

final routes = <RouteBase>[
  GoRoute(path: '/', builder: (_, __) => const SizedBox()),
  GoRoute(path: '/manual', builder: (_, __) => const SizedBox()),
  // forgekit:go-routes
];
''';

const _modularModule = '''
import 'package:flutter_modular/flutter_modular.dart';

import 'presentation/orders_screen.dart';
// forgekit:route-imports

final ordersModule = createModule(
  register: (c) {
    c
      ..route('/', child: (_, __) => const OrdersScreen())
      // forgekit:routes
      ;
  },
);
''';
