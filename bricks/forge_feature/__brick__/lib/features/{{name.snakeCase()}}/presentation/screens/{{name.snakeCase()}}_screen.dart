import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:{{projectName}}/core/di/core_module_container.dart';
import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_provider.dart';

/// Screen for the {{name.pascalCase()}} feature.
{{#useRouter}}
// ROUTE (named routes): register this screen in core/presentation/app/app.dart
// `routes` map:
//   {{name.pascalCase()}}Screen.id: (_) => const {{name.pascalCase()}}Screen(),
{{/useRouter}}
{{^useRouter}}
// ROUTE (go_router): {{name.camelCase()}}Routes is defined in
// features/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_routes.dart.
// Spread it into your central AppRouter:
//   GoRouter(routes: [ ...{{name.camelCase()}}Routes ]);
{{/useRouter}}
class {{name.pascalCase()}}Screen extends StatelessWidget {
  const {{name.pascalCase()}}Screen({super.key});

  static const id = '/{{name.snakeCase()}}';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<{{name.pascalCase()}}Provider>(
      create: (_) => getIt<{{name.pascalCase()}}Provider>(),
      child: Scaffold(
        appBar: AppBar(title: const Text('{{name.titleCase()}}')),
        body: Consumer<{{name.pascalCase()}}Provider>(
          builder: (context, provider, _) {
            final state = provider.state;

            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.hasError) {
              return Center(
                child: Text(state.errorMessage ?? 'Something went wrong'),
              );
            }

            // TODO: build the {{name.pascalCase()}} UI.
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
