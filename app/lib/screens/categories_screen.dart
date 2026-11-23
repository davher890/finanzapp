import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../util/format.dart';
import '../widgets/page.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _api = ApiClient.instance;
  List<Map<String, dynamic>>? _categories;
  List<Map<String, dynamic>>? _uncategorized;
  Object? _error;
  bool _busy = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([_api.categories(), _api.uncategorized()]);
      if (!mounted) return;
      setState(() {
        _categories = results[0].cast<Map<String, dynamic>>();
        _uncategorized = results[1].cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _guard(Future<void> Function() action, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (ok != null && mounted) showInfo(context, ok);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCategory([Map<String, dynamic>? category]) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _CategoryDialog(category: category),
    );
    if (result == null) return;
    final (name, kind) = result;
    await _guard(() async {
      if (category == null) {
        await _api.createCategory(name, kind);
      } else {
        await _api.updateCategory(category['id'] as int, {'name': name, 'kind': kind});
      }
    }, ok: category == null ? 'Categoría creada' : 'Categoría actualizada');
  }

  Future<void> _deleteCategory(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar ${c['name']}'),
        content: Text(
            'Se borrará la categoría y sus ${(c['concepts'] as List).length} conceptos. Los cargos no se borran: pasarán a OTROS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await _guard(() => _api.deleteCategory(c['id'] as int), ok: 'Categoría eliminada');
  }

  Future<void> _move(int index, int delta) async {
    final list = [..._categories!];
    final target = index + delta;
    if (target < 0 || target >= list.length) return;
    final item = list.removeAt(index);
    list.insert(target, item);
    setState(() => _categories = list);
    await _guard(() => _api.reorderCategories([for (final c in list) c['id'] as int]));
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _guard(() async {
      final res = await _api.importCategories(bytes, file.name) as Map<String, dynamic>;
      if (mounted) {
        showInfo(context,
            'Importadas ${res['categories_created']} categorías nuevas y ${res['concepts_created']} conceptos nuevos');
      }
    });
  }

  List<Map<String, dynamic>> _suggestionsOf(Map<String, dynamic> u) =>
      ((u['suggestions'] as List?) ?? const []).cast<Map<String, dynamic>>();

  String _patternOf(Map<String, dynamic> u) => (u['suggested_pattern'] as String?) ?? (u['movement'] as String);

  /// Elegir categoría a mano: primero las sugeridas, después todas.
  Future<void> _assign(Map<String, dynamic> u) async {
    final suggested = _suggestionsOf(u).map((s) => s['category_id'] as int).toSet();
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Asignar "${u['movement']}" a…'),
        children: [
          for (final s in _suggestionsOf(u))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s['category_id'] as int),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(s['category'] as String)),
                Text(_scoreLabel(s), style: Theme.of(ctx).textTheme.bodySmall),
              ]),
            ),
          if (suggested.isNotEmpty) const Divider(),
          for (final c in _categories!)
            if (!suggested.contains(c['id']))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c['id'] as int),
                child: Text(c['name'] as String),
              ),
        ],
      ),
    );
    if (id == null) return;
    await _addConcept(u, id);
  }

  Future<void> _addConcept(Map<String, dynamic> u, int categoryId) async {
    final name = _categories!.firstWhere((c) => c['id'] == categoryId)['name'];
    final pattern = _patternOf(u);
    await _guard(() => _api.addConcept(categoryId, pattern), ok: '"$pattern" añadido a $name');
  }

  /// Otros usuarios tienen el movimiento en una categoría que tú no tienes: la crea y asigna el concepto.
  Future<void> _createAndAssign(Map<String, dynamic> u) async {
    final nc = u['new_category'] as Map<String, dynamic>;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Crear la categoría ${nc['name']}'),
        content: Text('Se creará la categoría ${nc['name']} (${kindLabels[nc['kind']] ?? nc['kind']}) '
            'y se le añadirá el concepto "${_patternOf(u)}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear y asignar')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      final created = await _api.createCategory(nc['name'] as String, nc['kind'] as String) as Map<String, dynamic>;
      await _api.addConcept(created['id'] as int, _patternOf(u));
    }, ok: 'Categoría ${nc['name']} creada');
  }

  /// Acepta de una vez la primera sugerencia de todos los movimientos con sugerencia segura.
  Future<void> _acceptAllStrong(List<Map<String, dynamic>> strong) async {
    final byPattern = <String, Map<String, dynamic>>{};
    for (final u in strong) {
      byPattern.putIfAbsent(_patternOf(u), () => {'category_id': _suggestionsOf(u).first['category_id'], 'pattern': _patternOf(u)});
    }
    final names = {for (final c in _categories!) c['id']: c['name']};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aceptar ${strong.length} sugerencias'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView(children: [
            for (final item in byPattern.values)
              ListTile(
                dense: true,
                title: Text(item['pattern'] as String),
                trailing: Text('${names[item['category_id']]}'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceptar todas')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      final r = await _api.addConceptsBulk(byPattern.values.toList());
      if (mounted) showInfo(context, '${r['created']} conceptos añadidos');
    });
  }

  String _scoreLabel(Map<String, dynamic> s) => s['source'] == 'others'
      ? '${s['users']} ${s['users'] == 1 ? 'usuario' : 'usuarios'}'
      : '${((s['score'] as num) * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    if (_categories == null) return const Center(child: CircularProgressIndicator());
    final uncategorized = _uncategorized ?? [];

    return DefaultTabController(
      length: 2,
      child: PageBody(
        title: 'Categorías',
        subtitle: 'Las categorías agrupan conceptos del banco. Un cargo entra en la primera categoría (por orden) '
            'que tenga su movimiento. Admite comodines * y ?.',
        scroll: false,
        actions: [
          if (_busy) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Importar desde Excel (Metadata)'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : () => _editCategory(),
            icon: const Icon(Icons.add),
            label: const Text('Nueva categoría'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(tabs: [
              Tab(text: 'Categorías (${_categories!.length})'),
              Tab(text: 'Sin categoría (${uncategorized.length})'),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(children: [
                _categoriesTab(),
                _uncategorizedTab(uncategorized),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoriesTab() {
    final cats = _categories!;
    if (cats.isEmpty) {
      return EmptyState(
        icon: Icons.category_outlined,
        message: 'Aún no tienes categorías.\nCrea una o impórtalas desde la pestaña Metadata de tu Excel.',
        action: FilledButton.icon(onPressed: () => _editCategory(), icon: const Icon(Icons.add), label: const Text('Nueva categoría')),
      );
    }
    final f = _filter.toLowerCase();
    final visible = [
      for (var i = 0; i < cats.length; i++)
        if (f.isEmpty ||
            (cats[i]['name'] as String).toLowerCase().contains(f) ||
            (cats[i]['concepts'] as List).any((c) => (c['pattern'] as String).toLowerCase().contains(f)))
          i
    ];
    return Column(children: [
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.filter_list),
          hintText: 'Filtrar por categoría o concepto',
          isDense: true,
        ),
        onChanged: (v) => setState(() => _filter = v.trim()),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: ListView.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, vi) {
            final i = visible[vi];
            final c = cats[i];
            return _CategoryCard(
              key: ValueKey(c['id']),
              category: c,
              filter: f,
              busy: _busy,
              onEdit: () => _editCategory(c),
              onDelete: () => _deleteCategory(c),
              onUp: i > 0 && f.isEmpty ? () => _move(i, -1) : null,
              onDown: i < cats.length - 1 && f.isEmpty ? () => _move(i, 1) : null,
              onAddConcept: (p) => _guard(() => _api.addConcept(c['id'] as int, p)),
              onDeleteConcept: (id) => _guard(() => _api.deleteConcept(id)),
            );
          },
        ),
      ),
    ]);
  }

  Widget _uncategorizedTab(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const EmptyState(icon: Icons.task_alt, message: 'Todos los cargos tienen categoría.');
    }
    final theme = Theme.of(context);
    final strong = items.where((u) => u['strong'] == true && _suggestionsOf(u).isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Estos movimientos aparecen como OTROS en el resumen. Pulsa una sugerencia para asignarla '
              '(también se clasifican los cargos pasados). Las resaltadas son seguras; las del icono de '
              'personas las tienen así otros usuarios.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (strong.isNotEmpty)
            FilledButton.icon(
              onPressed: _busy ? null : () => _acceptAllStrong(strong),
              icon: const Icon(Icons.done_all),
              label: Text('Aceptar ${strong.length} seguras'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Card(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _uncategorizedRow(items[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _uncategorizedRow(Map<String, dynamic> u) {
    final theme = Theme.of(context);
    final suggestions = _suggestionsOf(u);
    final pattern = _patternOf(u);
    final patternMovements = (u['pattern_movements'] as int?) ?? 1;
    final newCategory = u['new_category'] as Map<String, dynamic>?;
    final strong = u['strong'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u['movement'] as String, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('${_plural(u['count'] as int, 'cargo')} · último ${dateLabel(u['last_date'] as String)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          Text(money(toDouble(u['total'])), style: TextStyle(color: amountColor(context, toDouble(u['total'])))),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy || _categories!.isEmpty ? null : () => _assign(u),
            child: const Text('Elegir…'),
          ),
        ]),
        if (suggestions.isNotEmpty || newCategory != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (i, s) in suggestions.indexed)
              Tooltip(
                message: s['source'] == 'others'
                    ? '${_scoreLabel(s)} ${s['users'] == 1 ? 'tiene' : 'tienen'} este movimiento en ${s['category']}'
                    : 'Parecido a tus conceptos de ${s['category']}',
                child: ActionChip(
                  avatar: Icon(
                    s['source'] == 'others' ? Icons.people_alt_outlined : (i == 0 && strong ? Icons.check : Icons.auto_awesome),
                    size: 16,
                  ),
                  label: Text('${s['category']} · ${_scoreLabel(s)}'),
                  backgroundColor: i == 0 && strong ? theme.colorScheme.secondaryContainer : null,
                  onPressed: _busy ? null : () => _addConcept(u, s['category_id'] as int),
                ),
              ),
            if (newCategory != null)
              Tooltip(
                message: '${newCategory['users']} ${newCategory['users'] == 1 ? 'usuario lo tiene' : 'usuarios lo tienen'} '
                    'en ${newCategory['name']}, que tú no tienes',
                child: ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('Crear ${newCategory['name']} · ${newCategory['users']} '
                      '${newCategory['users'] == 1 ? 'usuario' : 'usuarios'}'),
                  onPressed: _busy ? null : () => _createAndAssign(u),
                ),
              ),
          ]),
          if (patternMovements > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Se añadirá el concepto "$pattern", que cubre $patternMovements movimientos parecidos.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ]),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    super.key,
    required this.category,
    required this.filter,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
    required this.onAddConcept,
    required this.onDeleteConcept,
  });

  final Map<String, dynamic> category;
  final String filter;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final Future<void> Function(String) onAddConcept;
  final Future<void> Function(int) onDeleteConcept;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  final _concept = TextEditingController();

  @override
  void dispose() {
    _concept.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final p = _concept.text.trim();
    if (p.isEmpty) return;
    await widget.onAddConcept(p);
    _concept.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.category;
    final concepts = (c['concepts'] as List).cast<Map<String, dynamic>>();
    final stats = c['transactions'] as Map<String, dynamic>? ?? {'count': 0, 'total': 0};
    final kind = c['kind'] as String;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final kindColor = switch (kind) {
      'ingreso' => Colors.green.shade700,
      'mixto' => Colors.orange.shade800,
      _ => theme.colorScheme.primary,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: widget.filter.isNotEmpty,
        shape: const Border(),
        title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(c['name'] as String, style: theme.textTheme.titleMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: kindColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(kind == 'mixto' ? 'Mixto' : kindLabels[kind]!, style: theme.textTheme.labelSmall?.copyWith(color: kindColor)),
          ),
        ]),
        subtitle: Text('${_plural(concepts.length, 'concepto')} · ${_plural(stats['count'] as int, 'cargo')} · '
            '${money(toDouble(stats['total']))}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!narrow) ...[
            IconButton(tooltip: 'Subir', icon: const Icon(Icons.arrow_upward), onPressed: widget.busy ? null : widget.onUp),
            IconButton(tooltip: 'Bajar', icon: const Icon(Icons.arrow_downward), onPressed: widget.busy ? null : widget.onDown),
          ],
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'edit' => widget.onEdit(),
              'up' => widget.onUp?.call(),
              'down' => widget.onDown?.call(),
              _ => widget.onDelete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'))),
              if (narrow) ...[
                PopupMenuItem(
                    value: 'up',
                    enabled: widget.onUp != null && !widget.busy,
                    child: const ListTile(leading: Icon(Icons.arrow_upward), title: Text('Subir'))),
                PopupMenuItem(
                    value: 'down',
                    enabled: widget.onDown != null && !widget.busy,
                    child: const ListTile(leading: Icon(Icons.arrow_downward), title: Text('Bajar'))),
              ],
              const PopupMenuItem(
                  value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar'))),
            ],
          ),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (concepts.isEmpty)
            Text('Sin conceptos todavía.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in concepts)
                InputChip(
                  label: Text(k['pattern'] as String),
                  selected: widget.filter.isNotEmpty && (k['pattern'] as String).toLowerCase().contains(widget.filter),
                  showCheckmark: false,
                  onDeleted: widget.busy ? null : () => widget.onDeleteConcept(k['id'] as int),
                  deleteButtonTooltipMessage: 'Quitar concepto',
                ),
            ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _concept,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Nuevo concepto (texto del movimiento, admite * y ?)',
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(onPressed: widget.busy ? null : _add, icon: const Icon(Icons.add), label: const Text('Añadir')),
          ]),
        ],
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});
  final Map<String, dynamic>? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?['name'] as String? ?? '');
  late String _kind = widget.category?['kind'] as String? ?? 'gasto';
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, (_name.text.trim(), _kind));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'Nueva categoría' : 'Editar categoría'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'p. ej. LUZ MADRID'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Obligatorio' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('Tipo', style: Theme.of(context).textTheme.labelLarge),
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v!),
              child: const Column(children: [
                RadioListTile(value: 'gasto', title: Text('Gasto'), subtitle: Text('Todo cuenta como gasto (las devoluciones lo reducen)')),
                RadioListTile(value: 'ingreso', title: Text('Ingreso'), subtitle: Text('Todo cuenta como ingreso (p. ej. nómina)')),
                RadioListTile(
                    value: 'mixto',
                    title: Text('Mixto'),
                    subtitle: Text('Lo negativo es gasto y lo positivo ingreso (p. ej. Bizum, transferencias)')),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
