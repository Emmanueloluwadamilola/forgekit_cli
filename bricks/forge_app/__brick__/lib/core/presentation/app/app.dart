import 'package:flutter/material.dart';
{{^useRouter}}import 'package:go_router/go_router.dart';
{{/useRouter}}{{#useProvider}}import 'package:provider/provider.dart';

import '../../di/core_module_container.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';

import '../../di/core_module_container.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';

import '../../di/core_module_container.dart';
{{/useCubit}}
import '../manager/theme_provider.dart';
import '../theme/app_theme.dart';

{{#useProvider}}class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => getIt<ThemeProvider>(),
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => _AppView(themeMode: theme.themeMode),
      ),
    );
  }
}
{{/useProvider}}{{#useRiverpod}}class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AppView(themeMode: ref.watch(themeProvider));
  }
}
{{/useRiverpod}}{{#useBloc}}class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ThemeBloc>(
      create: (_) => getIt<ThemeBloc>(),
      child: BlocBuilder<ThemeBloc, ThemeMode>(
        builder: (context, mode) => _AppView(themeMode: mode),
      ),
    );
  }
}
{{/useBloc}}{{#useCubit}}class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ThemeCubit>(
      create: (_) => getIt<ThemeCubit>(),
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, mode) => _AppView(themeMode: mode),
      ),
    );
  }
}
{{/useCubit}}

class _AppView extends StatelessWidget {
  const _AppView({required this.themeMode});

  final ThemeMode themeMode;

{{^useRouter}}  static final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _Placeholder(),
      ),
      // Register feature routes here, e.g.:
      //   ...ordersRoutes,
    ],
  );
{{/useRouter}}
  @override
  Widget build(BuildContext context) {
{{#useRouter}}    return MaterialApp(
      title: 'Forge App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      initialRoute: '/',
      routes: {
        // Register feature screens here.
        '/': (_) => const _Placeholder(),
      },
    );
{{/useRouter}}{{^useRouter}}    return MaterialApp.router(
      title: 'Forge App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      routerConfig: _router,
    );
{{/useRouter}}  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Forge App - add your first feature.')),
    );
  }
}
