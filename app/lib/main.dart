import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/api_client.dart';
import 'auth/auth_redirect.dart';
import 'screens/login_screen.dart';
import 'screens/password_screens.dart';
import 'screens/shell.dart';

Future<void> main() async {
  // Primero de todo: leer (y quitar de la URL) los datos de un enlace de email de Supabase.
  final redirect = takeAuthRedirect();
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');
  await ApiClient.instance.restore();
  runApp(FinanzApp(redirect: redirect));
}

class FinanzApp extends StatelessWidget {
  const FinanzApp({super.key, this.redirect});
  final AuthRedirect? redirect;

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
      home: AuthGate(redirect: redirect),
      // La app no usa rutas con nombre: ignora la ruta inicial de la URL (p. ej. restos de un enlace).
      onGenerateInitialRoutes: (_) => [MaterialPageRoute(builder: (_) => AuthGate(redirect: redirect))],
    );
  }
}

/// Decide la pantalla raíz: nueva contraseña (al volver del email), login o la app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.redirect});
  final AuthRedirect? redirect;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late AuthRedirect? _recovery = widget.redirect?.isRecovery == true ? widget.redirect : null;

  @override
  void initState() {
    super.initState();
    if (_recovery != null) {
      // Un enlace de recuperación sustituye a cualquier sesión guardada en este navegador.
      ApiClient.instance.logout();
      // Cuando la nueva contraseña se guarda, ApiClient inicia sesión y se pasa a la app.
      ApiClient.instance.addListener(_onSession);
    }
  }

  void _onSession() {
    if (ApiClient.instance.isLoggedIn && _recovery != null) {
      setState(() => _recovery = null);
      ApiClient.instance.removeListener(_onSession);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Contraseña cambiada. ¡Bienvenido de nuevo!')));
      });
    }
  }

  @override
  void dispose() {
    ApiClient.instance.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = _recovery;
    if (recovery != null) {
      return ResetPasswordScreen(
        accessToken: recovery.accessToken!,
        refreshToken: recovery.refreshToken!,
        onCancel: () {
          ApiClient.instance.removeListener(_onSession);
          setState(() => _recovery = null);
        },
      );
    }
    return ListenableBuilder(
      listenable: ApiClient.instance,
      builder: (context, _) => ApiClient.instance.isLoggedIn
          ? const Shell()
          : LoginScreen(initialError: widget.redirect?.error),
    );
  }
}
