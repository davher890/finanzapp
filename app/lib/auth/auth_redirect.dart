import 'auth_redirect_stub.dart' if (dart.library.js_interop) 'auth_redirect_web.dart' as impl;

/// Datos con los que Supabase vuelve a la app desde un enlace de email
/// (p. ej. `#access_token=…&refresh_token=…&type=recovery` o `#error=…&error_description=…`).
class AuthRedirect {
  AuthRedirect({this.accessToken, this.refreshToken, this.type, this.error});

  final String? accessToken;
  final String? refreshToken;
  final String? type;
  final String? error;

  bool get isRecovery => type == 'recovery' && accessToken != null && refreshToken != null;

  static AuthRedirect? fromParams(Map<String, String> p) {
    if (p['error'] != null || p['error_code'] != null) {
      final code = p['error_code'];
      final message = code == 'otp_expired'
          ? 'El enlace ha caducado o ya se ha usado. Pide uno nuevo.'
          : (p['error_description'] ?? 'No se pudo completar la operación del enlace.');
      return AuthRedirect(error: message);
    }
    if (p['access_token'] == null) return null;
    return AuthRedirect(accessToken: p['access_token'], refreshToken: p['refresh_token'], type: p['type']);
  }
}

/// Lee (una sola vez) los datos del enlace de email de la URL y los quita de la barra de direcciones.
/// En móvil y escritorio siempre devuelve null.
AuthRedirect? takeAuthRedirect() {
  final params = impl.takeFragmentParams();
  return params == null ? null : AuthRedirect.fromParams(params);
}
