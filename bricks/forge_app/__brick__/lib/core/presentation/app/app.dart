import 'package:flutter/material.dart';
{{^useRouter}}import 'package:go_router/go_router.dart';
{{/useRouter}}import 'package:provider/provider.dart';

import '../../di/core_module_container.dart';
import '../manager/theme_provider.dart';
import '../theme/app_theme.dart';

{{#useRouter}}
/// Root application widget.
///
/// Owns the [MaterialApp], the global named-route table and theme wiring.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => getIt<ThemeProvider>(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Forge App',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            routes: {
              // Register feature screens here, e.g.:
              //   OrdersScreen.id: (_) => const OrdersScreen(),
              // The `forge_feature` brick will point you at this map.
              '/': (_) => const _Placeholder(),
            },
          );
        },
      ),
    );
  }
}
{{/useRouter}}
{{^useRouter}}
/// Root application widget.
///
/// Owns the [MaterialApp.router], the global GoRouter instance and theme wiring.
class App extends StatelessWidget {
  const App({super.key});

  static final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _Placeholder(),
      ),
      // Register feature routes here, e.g.:
      //   ...ordersRoutes,
      // The `forge_feature` brick will point you at this list.
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => getIt<ThemeProvider>(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Forge App',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: themeProvider.themeMode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
{{/useRouter}}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Forge App — add your first feature.')),
    );
  }
}
