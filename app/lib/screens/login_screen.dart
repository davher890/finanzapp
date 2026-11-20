import 'package:flutter/material.dart';

import '../api/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _signup = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final api = ApiClient.instance;
      if (_signup) {
        final needsConfirmation = await api.signup(_email.text.trim(), _password.text);
        if (needsConfirmation && mounted) {
          setState(() {
            _signup = false;
            _info = 'Cuenta creada. Revisa tu email para confirmarla y después inicia sesión.';
          });
        }
      } else {
        await api.login(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.savings_outlined, size: 56, color: theme.colorScheme.primary),
                        const SizedBox(height: 12),
                        Text('FinanzApp', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text(
                          _signup ? 'Crea tu cuenta' : 'Inicia sesión para ver tus finanzas',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Entrar'), icon: Icon(Icons.login)),
                            ButtonSegment(value: true, label: Text('Registrarse'), icon: Icon(Icons.person_add_alt)),
                          ],
                          selected: {_signup},
                          onSelectionChanged: (s) => setState(() {
                            _signup = s.first;
                            _error = null;
                          }),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                          validator: (v) =>
                              v == null || !RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim()) ? 'Email no válido' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
                          onFieldSubmitted: (_) => _signup ? null : _submit(),
                        ),
                        if (_signup) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password2,
                            obscureText: _obscure,
                            decoration: const InputDecoration(
                                labelText: 'Repite la contraseña', prefixIcon: Icon(Icons.lock_outline)),
                            validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        ],
                        if (_info != null) ...[
                          const SizedBox(height: 16),
                          Text(_info!, style: TextStyle(color: theme.colorScheme.primary)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: _loading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_signup ? 'Crear cuenta' : 'Entrar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
