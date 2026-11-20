import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 2);
final _pct = NumberFormat.decimalPercentPattern(locale: 'es_ES', decimalDigits: 1);

String money(num? v) => v == null ? '—' : _money.format(v);
String pct(num? v) => v == null ? '—' : _pct.format(v);
String signedPct(num? v) => v == null ? '—' : '${v > 0 ? '+' : ''}${_pct.format(v)}';

double toDouble(dynamic v) => v == null ? 0 : (v as num).toDouble();

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "2025-03" → "Marzo 2025"
String monthLabel(String month, {bool withYear = true}) {
  final parts = month.split('-');
  final name = _monthNames[int.parse(parts[1]) - 1];
  final cap = '${name[0].toUpperCase()}${name.substring(1)}';
  return withYear ? '$cap ${parts[0]}' : cap;
}

/// "2025-03-07" → "07/03/2025"
String dateLabel(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

Color amountColor(BuildContext context, num v) {
  final scheme = Theme.of(context).colorScheme;
  if (v > 0) return Colors.green.shade700;
  if (v < 0) return scheme.error;
  return scheme.onSurfaceVariant;
}

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
  );
}

void showInfo(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

const kindLabels = {'gasto': 'Gasto', 'ingreso': 'Ingreso', 'mixto': 'Mixto (− gasto / + ingreso)'};
