import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../util/format.dart';
import '../widgets/page.dart';

class AddChargesScreen extends StatelessWidget {
  const AddChargesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: PageBody(
        title: 'Añadir cargos',
        subtitle: 'Apunta un cargo a mano o sube un Excel con varios.',
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabBar(tabs: [
              Tab(icon: Icon(Icons.edit_note), text: 'Manual'),
              Tab(icon: Icon(Icons.upload_file), text: 'Subir Excel'),
            ]),
            const SizedBox(height: 20),
            Builder(builder: (context) {
              final controller = DefaultTabController.of(context);
              return ListenableBuilder(
                listenable: controller,
                builder: (context, _) =>
                    IndexedStack(index: controller.index, children: const [_ManualForm(), _ExcelUpload()]),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ManualForm extends StatefulWidget {
  const _ManualForm();

  @override
  State<_ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends State<_ManualForm> {
  final _form = GlobalKey<FormState>();
  final _movement = TextEditingController();
  final _details = TextEditingController();
  final _amount = TextEditingController();
  final _balance = TextEditingController();
  DateTime _date = DateTime.now();
  bool _isExpense = true;
  bool _saving = false;
  final List<Map<String, dynamic>> _added = [];

  @override
  void dispose() {
    _movement.dispose();
    _details.dispose();
    _amount.dispose();
    _balance.dispose();
    super.dispose();
  }

  double? _parse(String s) {
    final t = s.trim().replaceAll('€', '').replaceAll(' ', '');
    if (t.isEmpty) return null;
    final normalized = t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t;
    return double.tryParse(normalized);
  }

  String get _isoDate =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final amount = _parse(_amount.text)!.abs() * (_isExpense ? -1 : 1);
      final created = await ApiClient.instance.createTransaction({
        'date': _isoDate,
        'movement': _movement.text.trim(),
        'details': _details.text.trim().isEmpty ? null : _details.text.trim(),
        'amount': amount,
        'balance': _parse(_balance.text),
      }) as Map<String, dynamic>;
      setState(() {
        _added.insert(0, created);
        _movement.clear();
        _details.clear();
        _amount.clear();
        _balance.clear();
      });
      if (mounted) {
        showInfo(context, 'Cargo guardado${created['category'] != null ? ' en ${created['category']}' : ' (sin categoría → OTROS)'}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _undo(Map<String, dynamic> t) async {
    try {
      await ApiClient.instance.deleteTransaction(t['id'] as int);
      setState(() => _added.remove(t));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Gasto'), icon: Icon(Icons.remove_circle_outline)),
                      ButtonSegment(value: false, label: Text('Ingreso'), icon: Icon(Icons.add_circle_outline)),
                    ],
                    selected: {_isExpense},
                    onSelectionChanged: (s) => setState(() => _isExpense = s.first),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Fecha', prefixIcon: Icon(Icons.event)),
                      child: Text(dateLabel(_isoDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _movement,
                    decoration: const InputDecoration(
                      labelText: 'Movimiento',
                      hintText: 'p. ej. MERCADONA MONTEBU',
                      helperText: 'Es el texto que se usa para asignar la categoría.',
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Obligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _details,
                    decoration: const InputDecoration(labelText: 'Más datos (opcional)', prefixIcon: Icon(Icons.notes)),
                  ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: const InputDecoration(labelText: 'Importe', suffixText: '€', prefixIcon: Icon(Icons.euro)),
                        validator: (v) {
                          final n = _parse(v ?? '');
                          if (n == null) return 'Importe no válido';
                          if (n == 0) return 'No puede ser 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _balance,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(labelText: 'Saldo (opcional)', suffixText: '€'),
                        validator: (v) => (v ?? '').trim().isNotEmpty && _parse(v!) == null ? 'Saldo no válido' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Guardar cargo'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_added.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Añadidos ahora', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final t in _added)
                ListTile(
                  title: Text(t['movement'] as String),
                  subtitle: Text('${dateLabel(t['date'] as String)} · ${t['category'] ?? 'OTROS'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(money(toDouble(t['amount'])),
                        style: TextStyle(color: amountColor(context, toDouble(t['amount'])), fontWeight: FontWeight.w600)),
                    IconButton(tooltip: 'Deshacer', icon: const Icon(Icons.undo), onPressed: () => _undo(t)),
                  ]),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _ExcelUpload extends StatefulWidget {
  const _ExcelUpload();

  @override
  State<_ExcelUpload> createState() => _ExcelUploadState();
}

class _ExcelUploadState extends State<_ExcelUpload> {
  Uint8List? _bytes;
  String? _name;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _result;
  bool _busy = false;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _bytes = bytes;
      _name = file.name;
      _preview = null;
      _result = null;
    });
    await _run(dryRun: true);
  }

  Future<void> _run({required bool dryRun}) async {
    if (_bytes == null) return;
    setState(() => _busy = true);
    try {
      final res = await ApiClient.instance.uploadTransactions(_bytes!, _name!, dryRun: dryRun) as Map<String, dynamic>;
      setState(() {
        if (dryRun) {
          _preview = res;
        } else {
          _result = res;
          _preview = null;
          _bytes = null;
        }
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _result ?? _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Formato del Excel', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Un .xlsx o .xls con las columnas Fecha · Movimiento · Más datos · Importe · Saldo, '
                  'como la pestaña "Total gastos" o el extracto que descargas del banco (puede tener filas '
                  'de título encima y columnas de más, como "Fecha valor"). Los gastos en negativo y los '
                  'ingresos en positivo. Las fechas pueden ser dd/mm/aaaa o fechas de Excel.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Un cargo es único por fecha, movimiento, más datos, importe y saldo: los que ya existen '
                  'o se repiten dentro del fichero se omiten, así que subir el mismo fichero dos veces no duplica nada.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_name == null ? 'Elegir fichero .xlsx o .xls' : 'Elegir otro fichero'),
                  ),
                  if (_name != null) Chip(avatar: const Icon(Icons.description, size: 18), label: Text(_name!)),
                  if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ],
            ),
          ),
        ),
        if (info != null) ...[
          const SizedBox(height: 20),
          Text(_result != null ? 'Importación completada' : 'Vista previa (todavía no se ha guardado nada)',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          CardGrid(minWidth: 150, children: [
            StatCard(label: 'Filas leídas', value: '${info['read']}', icon: Icons.table_rows),
            StatCard(
              label: _result != null ? 'Cargos nuevos' : 'Se importarán',
              value: '${_result != null ? info['inserted'] : info['to_insert']}',
              icon: Icons.add_task,
              color: Colors.green.shade700,
            ),
            StatCard(
              label: 'Ya existían',
              value: '${info['existing'] ?? info['duplicates']}',
              icon: Icons.content_copy,
            ),
            if (((info['repeated_in_file'] as int?) ?? 0) > 0)
              StatCard(
                label: 'Repetidas en el fichero',
                value: '${info['repeated_in_file']}',
                icon: Icons.copy_all,
                footer: 'Solo se importa una vez',
              ),
            StatCard(
              label: 'Filas con error',
              value: '${info['error_count']}',
              icon: Icons.error_outline,
              color: (info['error_count'] as int) > 0 ? theme.colorScheme.error : null,
            ),
          ]),
          if ((info['errors'] as List).isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                title: const Text('Filas que no se pueden importar'),
                children: [
                  for (final e in info['errors'] as List)
                    ListTile(dense: true, leading: Text('Fila ${e['row']}'), title: Text(e['message'] as String)),
                ],
              ),
            ),
          ],
          if (_preview != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || (_preview!['to_insert'] as int) == 0 ? null : () => _run(dryRun: false),
              icon: const Icon(Icons.cloud_upload),
              label: Text((_preview!['to_insert'] as int) == 0
                  ? 'No hay cargos nuevos que importar'
                  : 'Importar ${_preview!['to_insert']} cargos'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ],
      ],
    );
  }
}
