import 'package:injectable/injectable.dart';

/// Cross-cutting singleton: {{name.titleCase()}} Service.
///
/// Registered in DI as a [lazySingleton]. Resolve it anywhere via
/// `getIt<{{name.pascalCase()}}Service>()`. Call [init] once during app bootstrap.
@lazySingleton
class {{name.pascalCase()}}Service {
  /// One-time initialization. Call from `main.dart` before `runApp`.
  Future<void> init() async {
    // TODO: implement {{name.pascalCase()}}Service initialization
    // (e.g. request permissions, configure SDK, subscribe to streams).
  }
}
