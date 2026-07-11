import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'core_module_container.config.dart';

/// The global service locator instance.
final GetIt getIt = GetIt.instance;

/// Initializes the dependency injection graph.
///
/// Call this once during app bootstrap (see `main.dart`) before `runApp`.
///
/// The implementation ([_getIt.init]) is generated into
/// `core_module_container.config.dart` by `injectable_generator`. Run:
///
///   dart run build_runner build --delete-conflicting-outputs
///
/// to (re)generate it.
@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
Future<void> configureDependencies() async {
  getIt.init();
}
