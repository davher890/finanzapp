import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../util/format.dart';
import '../widgets/page.dart';
import 'password_screens.dart';

/// Datos de la cuenta y cambio de contraseña.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _me;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final me = await ApiClient.instance.me();
      if (mounted) setState(() => _me = me);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _date(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    return d == null ? '—' : DateFormat("d 'de' MMMM 'de' y, HH:mm", 'es_ES').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final me = _me;
    if (me == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final email = me['email'] as String? ?? '';

    return PageBody(
      title: 'Perfil',
      subtitle: 'Tu cuenta de FinanzApp.',
      maxWidth: 640,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(email.isEmpty ? '?' : email[0].toUpperCase(),
                    style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(email, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('Cuenta creada el ${_date(me['created_at'] as String?)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text('Último acceso: ${_date(me['last_sign_in_at'] as String?)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Text('Cambiar contraseña', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _ChangePasswordCard(),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => ApiClient.instance.logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ]),
    );
  }
}

class _ChangePasswordCard extends StatefulWidget {
  const _ChangePasswordCard();

  @override
  State<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends State<_ChangePasswordCard> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.changePassword(_current.text, _new.text);
      _form.currentState!.reset();
      _current.clear();
      _new.clear();
      _new2.clear();
      if (mounted) showInfo(context, 'Contraseña cambiada');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PasswordField(
                controller: _current,
                label: 'Contraseña actual',
                autofillHints: const [AutofillHints.password],
                validator: (v) => v == null || v.isEmpty ? 'Escribe tu contraseña actual' : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _new,
                label: 'Contraseña nueva',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) {
                  final err = validateNewPassword(v);
                  if (err != null) return err;
                  if (v == _current.text) return 'Debe ser distinta de la actual';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _new2,
                label: 'Repite la contraseña nueva',
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) => v != _new.text ? 'Las contraseñas no coinciden' : null,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.key),
                  label: const Text('Cambiar contraseña'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
