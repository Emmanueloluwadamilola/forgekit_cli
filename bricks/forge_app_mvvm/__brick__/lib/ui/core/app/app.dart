import 'package:flutter/material.dart';
{{^useRouter}}import 'package:go_router/go_router.dart';
{{/useRouter}}{{#useProvider}}import 'package:provider/provider.dart';
import '../../../config/di/dependencies.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../config/di/dependencies.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../config/di/dependencies.dart';
{{/useCubit}}
import '../themes/app_theme.dart';
import '../view_models/theme_view_model.dart';
// forgekit:route-imports

{{#useProvider}}class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => getIt<ThemeViewModel>(),
        child: Consumer<ThemeViewModel>(
          builder: (_, vm, _) => _AppView(themeMode: vm.mode),
        ),
      );
}
{{/useProvider}}{{#useRiverpod}}class App extends ConsumerWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _AppView(themeMode: ref.watch(themeViewModelProvider));
}
{{/useRiverpod}}{{#useBloc}}class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<ThemeViewModel>(),
        child: BlocBuilder<ThemeViewModel, ThemeMode>(
          builder: (_, mode) => _AppView(themeMode: mode),
        ),
      );
}
{{/useBloc}}{{#useCubit}}class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<ThemeViewModel>(),
        child: BlocBuilder<ThemeViewModel, ThemeMode>(
          builder: (_, mode) => _AppView(themeMode: mode),
        ),
      );
}
{{/useCubit}}

class _AppView extends StatelessWidget {
  const _AppView({required this.themeMode});
  final ThemeMode themeMode;
{{^useRouter}}  static final _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _HomeView()),
      // forgekit:go-routes
    ],
  );
{{/useRouter}}
  @override
  Widget build(BuildContext context) {
{{#useRouter}}    return MaterialApp(
      title: 'Flutter ForgeKit CLI MVVM',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routes: {
        '/': (_) => const _HomeView(),
        // forgekit:named-routes
      },
    );
{{/useRouter}}{{^useRouter}}    return MaterialApp.router(
      title: 'Flutter ForgeKit CLI MVVM',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
    );
{{/useRouter}}  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Add your first MVVM feature.')),
      );
}
