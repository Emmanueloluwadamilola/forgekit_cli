import 'package:flutter/material.dart';
{{#useProvider}}import 'package:provider/provider.dart';

import 'package:{{projectName}}/config/di/dependencies.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:{{projectName}}/config/di/dependencies.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:{{projectName}}/config/di/dependencies.dart';
{{/useCubit}}
import 'package:{{projectName}}/ui/{{name.snakeCase()}}/view_models/{{name.snakeCase()}}_state.dart';
import 'package:{{projectName}}/ui/{{name.snakeCase()}}/view_models/{{name.snakeCase()}}_view_model.dart';
import 'package:{{projectName}}/ui/core/view_models/view_state.dart';

{{#useProvider}}class {{name.pascalCase()}}Screen extends StatelessWidget {
{{/useProvider}}{{#useRiverpod}}class {{name.pascalCase()}}Screen extends ConsumerWidget {
{{/useRiverpod}}{{#useBloc}}class {{name.pascalCase()}}Screen extends StatelessWidget {
{{/useBloc}}{{#useCubit}}class {{name.pascalCase()}}Screen extends StatelessWidget {
{{/useCubit}}  const {{name.pascalCase()}}Screen({super.key});

  static const id = '/{{name.snakeCase()}}';

  @override
{{#useRiverpod}}  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch({{name.camelCase()}}ViewModelProvider);
    return _{{name.pascalCase()}}View(state: state);
  }
{{/useRiverpod}}{{^useRiverpod}}  Widget build(BuildContext context) {
{{#useProvider}}    return ChangeNotifierProvider(
      create: (_) => getIt<{{name.pascalCase()}}ViewModel>(),
      child: Consumer<{{name.pascalCase()}}ViewModel>(
        builder: (_, viewModel, __) =>
            _{{name.pascalCase()}}View(state: viewModel.state),
      ),
    );
{{/useProvider}}{{#useBloc}}    return BlocProvider(
      create: (_) => getIt<{{name.pascalCase()}}ViewModel>(),
      child: BlocBuilder<{{name.pascalCase()}}ViewModel, {{name.pascalCase()}}State>(
        builder: (_, state) => _{{name.pascalCase()}}View(state: state),
      ),
    );
{{/useBloc}}{{#useCubit}}    return BlocProvider(
      create: (_) => getIt<{{name.pascalCase()}}ViewModel>(),
      child: BlocBuilder<{{name.pascalCase()}}ViewModel, {{name.pascalCase()}}State>(
        builder: (_, state) => _{{name.pascalCase()}}View(state: state),
      ),
    );
{{/useCubit}}  }
{{/useRiverpod}}}

class _{{name.pascalCase()}}View extends StatelessWidget {
  const _{{name.pascalCase()}}View({required this.state});

  final {{name.pascalCase()}}State state;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('{{name.titleCase()}}')),
        body: switch (state.status) {
          ViewStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          ViewStatus.error => Center(
              child: Text(state.errorMessage ?? 'Something went wrong'),
            ),
          _ => const SizedBox.shrink(),
        },
      );
}
