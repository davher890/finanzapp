import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../util/format.dart';
import '../widgets/page.dart';

/// Listado de años/meses; al elegir uno se ve su resumen al estilo de la pestaña "Agregado".
class MonthsScreen extends StatefulWidget {
  const MonthsScreen({super.key});

  @override
  State<MonthsScreen> createState() => _MonthsScreenState();
}

class _MonthsScreenState extends State<MonthsScreen> {
  List<Map<String, dynamic>>? _years;
  Object? _error;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final years = (await ApiClient.instance.months()).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _years = years;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        if (wide && _selected == null && years.isNotEmpty) {
          _selected = (years.first['months'] as List).first['month'] as String;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(String month, bool wide) {
    if (wide) {
      setState(() => _selected = month);
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(monthLabel(month))),
          body: MonthSummaryView(month: month),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    if (_years == null) return const Center(child: CircularProgressIndicator());
    if (_years!.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_outlined,
        message: 'Todavía no hay cargos.\nAñádelos desde "Añadir cargos".',
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = _MonthList(years: _years!, selected: wide ? _selected : null, onTap: (m) => _open(m, wide));
    if (!wide) return list;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 260, child: list),
      const VerticalDivider(width: 1),
      Expanded(
        child: _selected == null
            ? const EmptyState(icon: Icons.touch_app_outlined, message: 'Elige un mes')
            : MonthSummaryView(key: ValueKey(_selected), month: _selected!),
      ),
    ]);
  }
}

class _MonthList extends StatelessWidget {
  const _MonthList({required this.years, required this.selected, required this.onTap});
  final List<Map<String, dynamic>> years;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (final (i, y) in years.indexed)
          ExpansionTile(
            initiallyExpanded: i == 0 || (selected?.startsWith('${y['year']}') ?? false),
            shape: const Border(),
            title: Text('${y['year']}', style: theme.textTheme.titleMedium),
            subtitle: Text('${(y['months'] as List).length} meses'),
            children: [
              for (final m in (y['months'] as List).cast<Map<String, dynamic>>())
                ListTile(
                  selected: m['month'] == selected,
                  selectedTileColor: theme.colorScheme.secondaryContainer,
                  contentPadding: const EdgeInsets.only(left: 28, right: 16),
                  title: Text(monthLabel(m['month'] as String, withYear: false)),
                  subtitle: Text('${m['transactions']} cargos'),
                  trailing: Text(money(toDouble(m['net'])),
                      style: TextStyle(color: amountColor(context, toDouble(m['net'])))),
                  onTap: () => onTap(m['month'] as String),
                ),
            ],
          ),
      ],
    );
  }
}

class MonthSummaryView extends StatefulWidget {
  const MonthSummaryView({super.key, required this.month});
  final String month;

  @override
  State<MonthSummaryView> createState() => _MonthSummaryViewState();
}

class _MonthSummaryViewState extends State<MonthSummaryView> {
  Map<String, dynamic>? _data;
  Object? _error;
  bool _hideZeros = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await ApiClient.instance.summary(widget.month);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorRetry(error: _error!, onRetry: _load);
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());

    final txs = (d['transactions'] as List).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> rows(String key) {
      final r = (d[key] as List).cast<Map<String, dynamic>>();
      return _hideZeros ? r.where((x) => toDouble(x['amount']) != 0 || toDouble(x['previous']) != 0).toList() : r;
    }

    // Categorías mixtas: aparecen en gastos y en ingresos y el signo decide dónde va cada cargo.
    final incomeIds = {for (final r in d['income'] as List) r['category_id']};
    final expenseIds = {for (final r in d['expenses'] as List) r['category_id']};
    List<Map<String, dynamic>> txFor(Map<String, dynamic> row, {required bool income}) {
      final id = row['category_id'];
      final mixed = incomeIds.contains(id) && expenseIds.contains(id);
      return txs.where((t) {
        if (t['category_id'] != id) return false;
        if (!mixed) return true;
        final amount = toDouble(t['amount']);
        return income ? amount > 0 : amount <= 0;
      }).toList();
    }

    final expTotal = d['expenses_total'] as Map<String, dynamic>;
    final incTotal = d['income_total'] as Map<String, dynamic>;
    final balance = d['balance'] as Map<String, dynamic>;
    final prevLabel = monthLabel(d['previous_month'] as String);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(wide ? 32 : 16),
        children: [
          if (wide) ...[
            Text(monthLabel(widget.month), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
          ],
          Text('${txs.length} cargos · comparado con $prevLabel · media sobre ${d['months_with_data']} meses',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          CardGrid(minWidth: 180, children: [
            StatCard(
              label: 'Gastos',
              value: money(toDouble(expTotal['amount'])),
              icon: Icons.trending_down,
              color: amountColor(context, toDouble(expTotal['amount'])),
              footer: 'vs. mes anterior ${signedPct(expTotal['variation'] as num?)}',
            ),
            StatCard(
              label: 'Ingresos',
              value: money(toDouble(incTotal['amount'])),
              icon: Icons.trending_up,
              color: amountColor(context, toDouble(incTotal['amount'])),
              footer: 'vs. mes anterior ${signedPct(incTotal['variation'] as num?)}',
            ),
            StatCard(
              label: 'Balance',
              value: money(toDouble(balance['amount'])),
              icon: Icons.account_balance_wallet_outlined,
              color: amountColor(context, toDouble(balance['amount'])),
              footer: 'Media mensual ${money(toDouble(balance['average']))}',
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilterChip(
              label: const Text('Ocultar categorías a 0'),
              selected: _hideZeros,
              onSelected: (v) => setState(() => _hideZeros = v),
            ),
          ),
          const SizedBox(height: 8),
          _SummaryTable(
            title: 'Gastos',
            expense: true,
            rows: rows('expenses'),
            total: expTotal,
            transactionsFor: (r) => txFor(r, income: false),
          ),
          const SizedBox(height: 20),
          _SummaryTable(
            title: 'Ingresos',
            expense: false,
            rows: rows('income'),
            total: incTotal,
            transactionsFor: (r) => txFor(r, income: true),
          ),
          const SizedBox(height: 20),
          Card(
            child: _RowLayout(
              name: Text('BALANCE', style: Theme.of(context).textTheme.titleMedium),
              amount: toDouble(balance['amount']),
              share: null,
              variation: balance['variation'] as num?,
              average: toDouble(balance['average']),
              expense: false,
              bold: true,
            ),
          ),
          const SizedBox(height: 20),
          _MonthTransactions(transactions: txs),
        ],
      ),
    );
  }
}

/// Todos los cargos del mes, del más reciente al más antiguo, de 20 en 20.
class _MonthTransactions extends StatefulWidget {
  const _MonthTransactions({required this.transactions});
  final List<Map<String, dynamic>> transactions;

  @override
  State<_MonthTransactions> createState() => _MonthTransactionsState();
}

class _MonthTransactionsState extends State<_MonthTransactions> {
  static const _pageSize = 20;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...widget.transactions]..sort((a, b) {
        final byDate = (b['date'] as String).compareTo(a['date'] as String);
        return byDate != 0 ? byDate : (b['id'] as int).compareTo(a['id'] as int);
      });
    final total = sorted.length;
    final pages = (total / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, pages - 1);
    final from = page * _pageSize;
    final to = (from + _pageSize).clamp(0, total);
    final visible = sorted.sublist(from, to);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(child: Text('Cargos del mes', style: theme.textTheme.titleMedium)),
            Text('$total ${total == 1 ? 'cargo' : 'cargos'}',
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        if (total == 0)
          const Padding(padding: EdgeInsets.all(16), child: Text('No hay cargos este mes.'))
        else
          for (final (i, t) in visible.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: SizedBox(
                width: 44,
                child: Text(dateLabel(t['date'] as String).substring(0, 5),
                    style: theme.textTheme.labelLarge, textAlign: TextAlign.center),
              ),
              title: Text(t['movement'] as String),
              subtitle: Text([
                (t['category'] as String?) ?? 'OTROS',
                if (t['details'] != null) t['details'] as String,
              ].join(' · ')),
              trailing: Text(
                money(toDouble(t['amount'])),
                style: TextStyle(color: amountColor(context, toDouble(t['amount'])), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        if (pages > 1) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                tooltip: 'Primera página',
                icon: const Icon(Icons.first_page),
                onPressed: page > 0 ? () => setState(() => _page = 0) : null,
              ),
              IconButton(
                tooltip: 'Anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
              ),
              Expanded(
                child: Text(
                  '${from + 1}–$to de $total · página ${page + 1} de $pages',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Siguiente',
                icon: const Icon(Icons.chevron_right),
                onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null,
              ),
              IconButton(
                tooltip: 'Última página',
                icon: const Icon(Icons.last_page),
                onPressed: page < pages - 1 ? () => setState(() => _page = pages - 1) : null,
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _SummaryTable extends StatelessWidget {
  const _SummaryTable(
      {required this.title, required this.expense, required this.rows, required this.total, required this.transactionsFor});
  final String title;
  final bool expense;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> total;
  final List<Map<String, dynamic>> Function(Map<String, dynamic>) transactionsFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxShare = rows.fold<double>(0, (m, r) => (r['share'] as num? ?? 0) > m ? (r['share'] as num).toDouble() : m);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: _RowLayout(
            name: Text(title, style: theme.textTheme.titleMedium),
            header: true,
          ),
        ),
        for (final r in rows)
          Builder(builder: (context) {
            final txs = transactionsFor(r);
            final share = (r['share'] as num?)?.toDouble();
            return ExpansionTile(
              shape: const Border(),
              tilePadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              minTileHeight: 0,
              showTrailingIcon: false,
              enabled: txs.isNotEmpty,
              title: _RowLayout(
                name: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['category'] as String, overflow: TextOverflow.ellipsis),
                  if (share != null && maxShare > 0) ...[
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: share / maxShare, minHeight: 4),
                    ),
                  ],
                ]),
                amount: toDouble(r['amount']),
                share: share,
                variation: r['variation'] as num?,
                average: toDouble(r['average']),
                expense: expense,
              ),
              children: [
                for (final t in txs)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 32, right: 16),
                    title: Text(t['movement'] as String),
                    subtitle: Text([dateLabel(t['date'] as String), if (t['details'] != null) t['details']].join(' · ')),
                    trailing: Text(money(toDouble(t['amount'])),
                        style: TextStyle(color: amountColor(context, toDouble(t['amount'])))),
                  ),
              ],
            );
          }),
        const Divider(height: 1),
        _RowLayout(
          name: Text(total['category'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          amount: toDouble(total['amount']),
          share: (total['amount'] as num) == 0 ? null : 1,
          variation: total['variation'] as num?,
          average: toDouble(total['average']),
          expense: expense,
          bold: true,
        ),
      ]),
    );
  }
}

/// Fila con columnas: nombre | importe | % | vs mes anterior | media. En móvil se ocultan % y media.
class _RowLayout extends StatelessWidget {
  const _RowLayout({
    required this.name,
    this.amount,
    this.share,
    this.variation,
    this.average,
    this.expense = true,
    this.header = false,
    this.bold = false,
  });

  final Widget name;
  final double? amount;
  final num? share;
  final num? variation;
  final double? average;
  final bool expense;
  final bool header;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final full = c.maxWidth >= 620;
      final style = (header ? theme.textTheme.labelMedium : theme.textTheme.bodyMedium)?.copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        color: header ? theme.colorScheme.onSurfaceVariant : null,
      );
      Widget cell(String text, double width, {Color? color}) => SizedBox(
            width: width,
            child: Text(text, textAlign: TextAlign.right, style: style?.copyWith(color: color)),
          );
      Color? varColor(num? v) {
        if (v == null || header) return null;
        // En gastos (importes negativos) una variación positiva significa gastar más.
        final worse = expense ? v > 0 : v < 0;
        return v == 0 ? null : (worse ? theme.colorScheme.error : Colors.green.shade700);
      }

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: header ? 12 : 8),
        child: Row(children: [
          Expanded(child: name),
          const SizedBox(width: 8),
          if (header) cell('Importe', 110) else cell(money(amount), 110, color: amountColor(context, amount ?? 0)),
          if (full) header ? cell('%', 70) : cell(pct(share), 70),
          header ? cell('vs. ant.', 80) : cell(signedPct(variation), 80, color: varColor(variation)),
          if (full) header ? cell('Media', 110) : cell(money(average), 110),
        ]),
      );
    });
  }
}
