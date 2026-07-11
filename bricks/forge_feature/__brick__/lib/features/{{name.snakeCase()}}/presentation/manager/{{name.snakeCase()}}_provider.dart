import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/core/presentation/manager/custom_provider.dart';
import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_state.dart';

/// Presentation manager for the {{name.pascalCase()}} feature.
///
/// Add operations with: `forgekit add function {{name.snakeCase()}} <name>`
@injectable
class {{name.pascalCase()}}Provider extends CustomProvider {
  {{name.pascalCase()}}State _state = const {{name.pascalCase()}}State();
  {{name.pascalCase()}}State get state => _state;
}
