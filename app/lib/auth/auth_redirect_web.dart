import 'package:web/web.dart' as web;

/// Devuelve los parámetros del fragmento (`#a=1&b=2`) si son de Supabase Auth y los borra de la URL
/// (para que los tokens no queden en el historial ni se reutilicen al recargar).
Map<String, String>? takeFragmentParams() {
  final location = web.window.location;
  final hash = location.hash;
  if (hash.length < 2) return null;
  final Map<String, String> params;
  try {
    params = Uri.splitQueryString(hash.substring(1));
  } catch (_) {
    return null;
  }
  final isAuth = params.containsKey('access_token') || params.containsKey('error') || params.containsKey('error_code');
  if (!isAuth) return null;
  web.window.history.replaceState(null, '', '${location.pathname}${location.search}');
  return params;
}
