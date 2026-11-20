import 'package:flutter/material.dart';

import '../widgets/page.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      (
        1,
        Icons.add_card,
        'Añadir cargos',
        'Apunta un cargo a mano o sube el Excel del banco. Los cargos repetidos no se duplican.'
      ),
      (
        2,
        Icons.category,
        'Categorías',
        'Crea categorías (Luz, Comida, Hipoteca…) y asígnales los conceptos del banco para clasificar los cargos.'
      ),
      (
        3,
        Icons.calendar_month,
        'Meses',
        'Resumen de cada mes: gasto por categoría, variación con el mes anterior, ingresos y balance.'
      ),
      (
        4,
        Icons.manage_search,
        'Búsqueda',
        'Busca cargos con una expresión regular (p. ej. AMAZON|AMZN) y ve el total por mes.'
      ),
    ];

    return PageBody(
      title: 'Bienvenido a FinanzApp',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined, size: 56, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('¿Qué es FinanzApp?',
                            style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                        const SizedBox(height: 8),
                        Text(
                          'FinanzApp es tu hoja de gastos de casa, pero sin fórmulas. Guarda los movimientos de tu cuenta, '
                          'los clasifica por categorías y te enseña cada mes en qué se va el dinero, cuánto entra y '
                          'cuál es el balance. Todo queda guardado en tu cuenta y solo tú puedes verlo.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('¿Qué puedes hacer?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          CardGrid(
            minWidth: 240,
            children: [
              for (final (index, icon, title, text) in items)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onNavigate(index),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                        height: 170,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(icon, color: theme.colorScheme.primary, size: 30),
                            const SizedBox(height: 12),
                            Text(title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Text(text,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.fade),
                            ),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Icon(Icons.arrow_forward, size: 18, color: theme.colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Primeros pasos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Step(n: 1, text: 'En Categorías, crea tus categorías o impórtalas desde la pestaña Metadata de tu Excel.'),
          const _Step(n: 2, text: 'En Añadir cargos, sube el Excel con los movimientos del banco.'),
          const _Step(n: 3, text: 'Revisa en Categorías → Sin categoría los movimientos que aún no tienen categoría.'),
          const _Step(n: 4, text: 'Consulta el resumen de cada mes en Meses.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 12, child: Text('$n', style: theme.textTheme.labelMedium)),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text))),
      ]),
    );
  }
}
