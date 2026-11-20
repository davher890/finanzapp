import 'package:flutter/material.dart';

/// Contenedor común de las pantallas: cabecera con título y ancho máximo legible.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.maxWidth = 1100,
    this.scroll = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final header = Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide) Text(title, style: theme.textTheme.headlineSmall),
              if (subtitle != null)
                Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, if (scroll) child else Expanded(child: child)],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: scroll
            ? SingleChildScrollView(padding: EdgeInsets.all(wide ? 32 : 16), child: content)
            : Padding(padding: EdgeInsets.all(wide ? 32 : 16), child: content),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.color, this.icon, this.footer});
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
              Flexible(child: Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
            if (footer != null) ...[
              const SizedBox(height: 4),
              Text(footer!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila de tarjetas que se reparte en columnas según el ancho disponible.
class CardGrid extends StatelessWidget {
  const CardGrid({super.key, required this.children, this.minWidth = 200});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minWidth).floor().clamp(1, children.length);
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}
