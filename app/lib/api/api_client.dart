import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// URL de la API. Se define al compilar: --dart-define=API_URL=https://mi-api.vercel.app
const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class Session {
  Session({required this.accessToken, required this.refreshToken, required this.email});
  final String accessToken;
  final String refreshToken;
  final String email;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        email: (j['user']?['email'] ?? j['email'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {'access_token': accessToken, 'refresh_token': refreshToken, 'email': email};
}

/// Único punto de acceso a la API. El front nunca habla directamente con Supabase.
class ApiClient extends ChangeNotifier {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _prefsKey = 'finanzapp.session';
  Session? _session;
  Session? get session => _session;
  bool get isLoggedIn => _session != null;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        _session = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        await prefs.remove(_prefsKey);
      }
    }
    notifyListeners();
  }

  Future<void> _setSession(Session? s) async {
    _session = s;
    final prefs = await SharedPreferences.getInstance();
    if (s == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    }
    notifyListeners();
  }

  // ---------- Auth ----------

  Future<void> login(String email, String password) async {
    final res = await _request('POST', '/auth/login', body: {'email': email, 'password': password}, auth: false);
    await _setSession(Session.fromJson(res as Map<String, dynamic>));
  }

  /// Devuelve true si el registro requiere confirmar el email antes de entrar.
  Future<bool> signup(String email, String password) async {
    final res = await _request('POST', '/auth/signup', body: {'email': email, 'password': password}, auth: false)
        as Map<String, dynamic>;
    if (res['needs_confirmation'] == true) return true;
    await _setSession(Session.fromJson(res));
    return false;
  }

  Future<void> logout() => _setSession(null);

  /// Envía el email de recuperación. [redirectTo] es la URL de la app web a la que llevará el enlace
  /// (en móvil se omite y la API usa la URL pública del front).
  Future<void> forgotPassword(String email, {String? redirectTo}) async {
    await _request('POST', '/auth/forgot-password',
        body: {'email': email, 'redirect_to': ?redirectTo}, auth: false);
  }

  /// Fija la nueva contraseña con los tokens del enlace de recuperación y deja la sesión iniciada.
  Future<void> resetPassword({required String accessToken, required String refreshToken, required String password}) async {
    final res = await _request('POST', '/auth/reset-password',
        body: {'access_token': accessToken, 'refresh_token': refreshToken, 'password': password}, auth: false);
    await _setSession(Session.fromJson(res as Map<String, dynamic>));
  }

  /// Cambia la contraseña (exige la actual). La API devuelve una sesión nueva, que sustituye a la anterior.
  Future<void> changePassword(String currentPassword, String newPassword) async {
    final res = await _request('POST', '/auth/change-password',
        body: {'current_password': currentPassword, 'new_password': newPassword});
    await _setSession(Session.fromJson(res as Map<String, dynamic>));
  }

  Future<Map<String, dynamic>> me() async => await get('/auth/me') as Map<String, dynamic>;

  Future<bool> _refresh() async {
    final s = _session;
    if (s == null) return false;
    try {
      final res = await _request('POST', '/auth/refresh', body: {'refresh_token': s.refreshToken}, auth: false);
      await _setSession(Session.fromJson(res as Map<String, dynamic>));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- Categorías ----------

  Future<List<dynamic>> categories() async => await get('/categories') as List<dynamic>;
  Future<List<dynamic>> uncategorized() async => await get('/categories/uncategorized') as List<dynamic>;
  Future<dynamic> createCategory(String name, String kind) => post('/categories', {'name': name, 'kind': kind});
  Future<dynamic> updateCategory(int id, Map<String, dynamic> data) => _request('PATCH', '/categories/$id', body: data);
  Future<void> deleteCategory(int id) => _request('DELETE', '/categories/$id');
  Future<dynamic> reorderCategories(List<int> ids) => _request('PUT', '/categories/order', body: {'ids': ids});
  Future<dynamic> addConcept(int categoryId, String pattern) =>
      post('/categories/$categoryId/concepts', {'pattern': pattern});
  Future<void> deleteConcept(int id) => _request('DELETE', '/categories/concepts/$id');
  /// Alta de varios conceptos a la vez: [{category_id, pattern}]. Devuelve {created, skipped}.
  Future<Map<String, dynamic>> addConceptsBulk(List<Map<String, dynamic>> items) async =>
      await post('/categories/concepts/bulk', {'items': items}) as Map<String, dynamic>;
  Future<dynamic> importCategories(Uint8List bytes, String filename) =>
      upload('/categories/import', bytes, filename);

  // ---------- Cargos ----------

  Future<dynamic> createTransaction(Map<String, dynamic> data) => post('/transactions', data);
  Future<void> deleteTransaction(int id) => _request('DELETE', '/transactions/$id');
  Future<dynamic> uploadTransactions(Uint8List bytes, String filename, {bool dryRun = false}) =>
      upload('/transactions/upload${dryRun ? '?dry_run=1' : ''}', bytes, filename);

  // ---------- Informes ----------

  Future<List<dynamic>> months() async => await get('/reports/months') as List<dynamic>;
  Future<Map<String, dynamic>> summary(String month) async =>
      await get('/reports/summary/$month') as Map<String, dynamic>;
  Future<Map<String, dynamic>> search(String query, {bool details = false}) async =>
      await get('/reports/search', query: {'q': query, if (details) 'details': '1'}) as Map<String, dynamic>;

  // ---------- HTTP ----------

  Future<dynamic> get(String path, {Map<String, String>? query}) => _request('GET', path, query: query);
  Future<dynamic> post(String path, Object body) => _request('POST', path, body: body);

  Future<dynamic> upload(String path, Uint8List bytes, String filename) {
    return _send(() {
      final req = http.MultipartRequest('POST', Uri.parse('$apiUrl$path'));
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      return req;
    }, auth: true);
  }

  Future<dynamic> _request(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true}) {
    return _send(() {
      final uri = Uri.parse('$apiUrl$path').replace(queryParameters: query);
      final req = http.Request(method, uri);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      return req;
    }, auth: auth);
  }

  Future<dynamic> _send(http.BaseRequest Function() build, {required bool auth, bool retried = false}) async {
    final req = build();
    if (auth && _session != null) req.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
    http.Response res;
    try {
      res = await http.Response.fromStream(await req.send());
    } catch (e) {
      throw ApiException('No se pudo conectar con la API ($apiUrl)');
    }
    if (res.statusCode == 401 && auth && !retried) {
      if (await _refresh()) return _send(build, auth: auth, retried: true);
      await _setSession(null);
      throw ApiException('Tu sesión ha caducado. Vuelve a entrar.', 401);
    }
    final dynamic data = res.body.isEmpty ? null : _tryDecode(res.body);
    if (res.statusCode >= 400) {
      final msg = data is Map && data['error'] != null ? data['error'].toString() : 'Error ${res.statusCode}';
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'error': body};
    }
  }
}
