import 'package:flutter/material.dart';
{{#useProvider}}import 'package:provider/provider.dart';

import 'package:{{projectName}}/core/di/core_module_container.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:{{projectName}}/core/di/core_module_container.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:{{projectName}}/core/di/core_module_container.dart';
{{/useCubit}}
import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_provider.dart';
import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_state.dart';

/// Screen for the {{name.pascalCase()}} feature.
{{#useProvider}}class {{name.pascalCase()}}Screen extends StatelessWidget {
{{/useProvider}}{{#useRiverpod}}class {{name.pascalCase()}}Screen extends ConsumerWidget {
{{/useRiverpod}}{{#useBloc}}class {{name.pascalCase()}}Screen extends StatelessWidget {
{{/useBloc}}{{#useCubit}}class {{name.pascalCase()}}Screen extends StatelessWidget {
{{/useCubit}}  const {{name.pascalCase()}}Screen({super.key});

  static const id = '/{{name.snakeCase()}}';

  @override
{{#useRiverpod}}  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch({{name.camelCase()}}Provider);
    return _{{name.pascalCase()}}View(state: state);
  }
{{/useRiverpod}}{{^useRiverpod}}  Widget build(BuildContext context) {
{{#useProvider}}    return ChangeNotifierProvider<{{name.pascalCase()}}Provider>(
      create: (_) => getIt<{{name.pascalCase()}}Provider>(),
      child: Consumer<{{name.pascalCase()}}Provider>(
        builder: (context, provider, _) =>
            _{{name.pascalCase()}}View(state: provider.state),
      ),
    );
{{/useProvider}}{{#useBloc}}    return BlocProvider<{{name.pascalCase()}}Bloc>(
      create: (_) => getIt<{{name.pascalCase()}}Bloc>(),
      child: BlocBuilder<{{name.pascalCase()}}Bloc, {{name.pascalCase()}}State>(
        builder: (context, state) => _{{name.pascalCase()}}View(state: state),
      ),
    );
{{/useBloc}}{{#useCubit}}    return BlocProvider<{{name.pascalCase()}}Cubit>(
      create: (_) => getIt<{{name.pascalCase()}}Cubit>(),
      child: BlocBuilder<{{name.pascalCase()}}Cubit, {{name.pascalCase()}}State>(
        builder: (context, state) => _{{name.pascalCase()}}View(state: state),
      ),
    );
{{/useCubit}}  }
{{/useRiverpod}}}

class _{{name.pascalCase()}}View extends StatelessWidget {
  const _{{name.pascalCase()}}View({required this.state});

  final {{name.pascalCase()}}State state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('{{name.titleCase()}}')),
      body: _body(),
    );
  }

  Widget _body() {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError) {
      return Center(
        child: Text(state.errorMessage ?? 'Something went wrong'),
      );
    }
    return const SizedBox.shrink();
  }
}
