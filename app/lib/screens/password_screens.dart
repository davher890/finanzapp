import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Tarjeta centrada común a las pantallas de acceso.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.icon, required this.title, this.subtitle, required this.child});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(icon, size: 52, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 24),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo de contraseña con botón para mostrarla.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Mostrar' : 'Ocultar',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}

String? validateNewPassword(String? v) {
  if (v == null || v.length < 6) return 'Mínimo 6 caracteres';
  if (v.length > 72) return 'Máximo 72 caracteres';
  return null;
}

/// Pide el email y envía el enlace de recuperación.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // En web el enlace vuelve a esta misma app; en móvil la API usa la URL pública del front.
      final redirectTo = kIsWeb ? '${Uri.base.origin}/' : null;
      await ApiClient.instance.forgotPassword(_email.text.trim(), redirectTo: redirectTo);
      if (mounted) setState(() => _sent = true);
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
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: AuthCard(
        icon: _sent ? Icons.mark_email_read_outlined : Icons.lock_reset,
        title: _sent ? 'Revisa tu email' : '¿Has olvidado tu contraseña?',
        subtitle: _sent
            ? 'Si existe una cuenta con ${_email.text.trim()}, te hemos enviado un enlace para elegir una '
                'contraseña nueva. Puede tardar unos minutos; mira también en spam.'
            : 'Escribe el email de tu cuenta y te enviaremos un enlace para elegir una contraseña nueva.',
        child: _sent
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!kIsWeb)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'El enlace se abre en el navegador. Cuando cambies la contraseña, vuelve aquí y entra con la nueva.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Volver a entrar')),
                TextButton(onPressed: () => setState(() => _sent = false), child: const Text('No me ha llegado, reenviar')),
              ])
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    controller: _email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => v == null || !RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim()) ? 'Email no válido' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enviar enlace'),
                  ),
                ]),
              ),
      ),
    );
  }
}

/// Se muestra al abrir el enlace del email: elige la contraseña nueva y entra en la app.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.accessToken, required this.refreshToken, required this.onCancel});
  final String accessToken;
  final String refreshToken;
  final VoidCallback onCancel;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Al terminar, ApiClient guarda la sesión y la app pasa sola a la pantalla principal.
      await ApiClient.instance.resetPassword(
        accessToken: widget.accessToken,
        refreshToken: widget.refreshToken,
        password: _password.text,
      );
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
      body: AuthCard(
        icon: Icons.lock_reset,
        title: 'Elige una contraseña nueva',
        subtitle: 'Después entrarás directamente en FinanzApp.',
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PasswordField(
                controller: _password,
                label: 'Contraseña nueva',
                autofocus: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: validateNewPassword,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password2,
                label: 'Repite la contraseña nueva',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar y entrar'),
              ),
              TextButton(onPressed: _loading ? null : widget.onCancel, child: const Text('Cancelar')),
            ]),
          ),
        ),
      ),
    );
  }
}
