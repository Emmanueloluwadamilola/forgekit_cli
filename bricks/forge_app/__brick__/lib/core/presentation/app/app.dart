import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../di/core_module_container.dart';
import '../manager/theme_provider.dart';
import '../theme/app_theme.dart';

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

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Forge App — add your first feature.')),
    );
  }
}
