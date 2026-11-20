import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/api_client.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');
  await ApiClient.instance.restore();
  runApp(const FinanzApp());
}

class FinanzApp extends StatelessWidget {
  const FinanzApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: b),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinanzApp',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: ApiClient.instance,
        builder: (context, _) => ApiClient.instance.isLoggedIn ? const Shell() : const LoginScreen(),
      ),
    );
  }
}
