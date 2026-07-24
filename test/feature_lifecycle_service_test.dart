import 'dart:io';

import 'package:forgekit/src/feature_lifecycle_service.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('forgekit_lifecycle_test_');
    _write(root, 'forgekit.yaml', '''
version: 1
architecture: clean
state_management: provider
router: named
dependency_injection: injectable
models: json_serializable
api_client: retrofit
generation:
  format: true
  build_runner: true
testing:
  coverage: 80
''');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('rename updates code references without changing string contracts',
      () async {
    _write(
      root,
      'lib/features/orders/data/remote/service/orders_api_service.dart',
      '''
import 'package:sample_app/features/orders/domain/orders_repository.dart';

class OrdersApiService {
  static const endpoint = '/orders';
  static const userCopy = 'Orders are ready';
  final String ordersRepository = 'orders_repository';
}
''',
    );
    _write(
      root,
      'lib/core/presentation/app/app.dart',
      '''
import 'package:sample_app/features/orders/presentation/screens/orders_screen.dart'; // forgekit:route-import:orders

final ordersScreen = OrdersScreen.id; // forgekit:route:orders
''',
    );

    final result = await renameFeature(
      root: root,
      from: 'orders',
      to: 'purchases',
      logger: Logger(level: Level.quiet),
    );

    expect(result, 0);
    final service = File(
      p.join(
        root.path,
        'lib/features/purchases/data/remote/service/purchases_api_service.dart',
      ),
    );
    expect(service.existsSync(), isTrue);
    final serviceSource = service.readAsStringSync();
    expect(serviceSource, contains('class PurchasesApiService'));
    expect(serviceSource, contains('purchasesRepository'));
    expect(
      serviceSource,
      contains('features/purchases/domain/purchases_repository.dart'),
    );
    expect(serviceSource, contains("endpoint = '/orders'"));
    expect(serviceSource, contains("'Orders are ready'"));
    expect(serviceSource, contains("'orders_repository'"));

    final appSource = File(
      p.join(root.path, 'lib/core/presentation/app/app.dart'),
    ).readAsStringSync();
    expect(appSource, contains('PurchasesScreen.id'));
    expect(appSource, contains('route-import:purchases'));
    expect(appSource, contains('route:purchases'));
  });
}

File _write(Directory root, String relativePath, String source) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
  return file;
}
