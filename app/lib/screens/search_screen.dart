import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../util/format.dart';
import '../widgets/page.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  bool _inDetails = false;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  static const _examples = ['AMAZON|AMZN', '^TAXI', 'MERCADONA', 'IBERDROLA|ENERGIA', 'BIZUM'];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    try {
      RegExp(q, caseSensitive: false);
    } on FormatException catch (e) {
      setState(() => _error = 'Expresión regular no válida: ${e.message}');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ApiClient.instance.search(q, details: _inDetails);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    return PageBody(
      title: 'Búsqueda de cargos',
      subtitle: 'Busca por expresión regular en el movimiento (no distingue mayúsculas).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: _query,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Expresión regular',
                  hintText: 'p. ej. AMAZON|AMZN',
                  prefixIcon: const Icon(Icons.search),
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _loading ? null : _search,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Buscar'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilterChip(
              label: const Text('Buscar también en "Más datos"'),
              selected: _inDetails,
              onSelected: (v) => setState(() => _inDetails = v),
            ),
            Text('Ejemplos:', style: theme.textTheme.bodySmall),
            for (final e in _examples)
              ActionChip(
                label: Text(e, style: const TextStyle(fontFamily: 'monospace')),
                onPressed: () {
                  _query.text = e;
                  _search();
                },
              ),
          ]),
          const SizedBox(height: 24),
          if (r != null) ...[
            if ((r['count'] as int) == 0)
              const EmptyState(icon: Icons.search_off, message: 'No hay cargos que coincidan.')
            else ...[
              CardGrid(minWidth: 180, children: [
                StatCard(label: 'Cargos encontrados', value: '${r['count']}', icon: Icons.receipt_long),
                StatCard(
                  label: 'Total',
                  value: money(toDouble(r['total'])),
                  icon: Icons.functions,
                  color: amountColor(context, toDouble(r['total'])),
                ),
                StatCard(
                  label: 'Media por mes',
                  value: money(toDouble(r['average_per_month'])),
                  icon: Icons.calendar_view_month,
                  footer: 'en ${(r['by_month'] as List).length} meses con cargos',
                ),
              ]),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, c) {
                final byMonth = _ByMonth(rows: (r['by_month'] as List).cast<Map<String, dynamic>>());
                final byYear = _ByYear(rows: ((r['by_year'] as List?) ?? const []).cast<Map<String, dynamic>>());
                final totals = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  byYear,
                  const SizedBox(height: 20),
                  byMonth,
                ]);
                final list = _TxList(rows: (r['transactions'] as List).cast<Map<String, dynamic>>());
                if (c.maxWidth < 800) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [totals, const SizedBox(height: 20), list]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 340, child: totals),
                  const SizedBox(width: 20),
                  Expanded(child: list),
                ]);
              }),
            ],
          ],
        ],
      ),
    );
  }
}

class _ByYear extends StatelessWidget {
  const _ByYear({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(16),
          child: Text('Total por año', style: theme.textTheme.titleMedium),
        ),
        for (final y in rows)
          ListTile(
            dense: true,
            title: Text('${y['year']}'),
            subtitle: Text('${y['count']} cargos · ${y['months']} ${y['months'] == 1 ? 'mes' : 'meses'}\n'
                'Media ${money(toDouble(y['average_per_month']))} al mes'),
            isThreeLine: true,
            trailing: Text(money(toDouble(y['total'])),
                style: TextStyle(color: amountColor(context, toDouble(y['total'])), fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

class _ByMonth extends StatelessWidget {
  const _ByMonth({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(16),
          child: Text('Total por mes', style: theme.textTheme.titleMedium),
        ),
        for (final m in rows)
          ListTile(
            dense: true,
            title: Text(monthLabel(m['month'] as String)),
            subtitle: Text('${m['count']} cargos'),
            trailing: Text(money(toDouble(m['total'])),
                style: TextStyle(color: amountColor(context, toDouble(m['total'])), fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

class _TxList extends StatelessWidget {
  const _TxList({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(16),
          child: Text('Cargos', style: theme.textTheme.titleMedium),
        ),
        for (final t in rows)
          ListTile(
            dense: true,
            title: Text(t['movement'] as String),
            subtitle: Text([
              dateLabel(t['date'] as String),
              t['category'] ?? 'OTROS',
              if (t['details'] != null) t['details'],
            ].join(' · ')),
            trailing: Text(money(toDouble(t['amount'])),
                style: TextStyle(color: amountColor(context, toDouble(t['amount'])), fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}
