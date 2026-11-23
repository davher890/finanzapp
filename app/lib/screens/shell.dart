import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'add_charges_screen.dart';
import 'categories_screen.dart';
import 'home_screen.dart';
import 'months_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class _Section {
  const _Section(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _sections = [
  _Section('Inicio', Icons.home_outlined, Icons.home),
  _Section('Añadir cargos', Icons.add_card_outlined, Icons.add_card),
  _Section('Categorías', Icons.category_outlined, Icons.category),
  _Section('Meses', Icons.calendar_month_outlined, Icons.calendar_month),
  _Section('Búsqueda', Icons.manage_search_outlined, Icons.manage_search),
  _Section('Perfil', Icons.person_outline, Icons.person),
];

/// Estructura principal con el menú: lateral en pantallas anchas y cajón en móvil.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  Widget _page() => switch (_index) {
        0 => HomeScreen(onNavigate: _go),
        1 => const AddChargesScreen(),
        2 => const CategoriesScreen(),
        3 => const MonthsScreen(),
        4 => const SearchScreen(),
        _ => const ProfileScreen(),
      };

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres salir?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok == true) await ApiClient.instance.logout();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final email = ApiClient.instance.session?.email ?? '';
    final page = KeyedSubtree(key: ValueKey(_index), child: _page());

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(children: [
                  Icon(Icons.savings_outlined, color: Theme.of(context).colorScheme.primary, size: 32),
                  const SizedBox(height: 4),
                  Text('FinanzApp', style: Theme.of(context).textTheme.labelLarge),
                ]),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Tooltip(
                      message: 'Cerrar sesión ($email)',
                      child: IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final s in _sections)
                  NavigationRailDestination(
                      icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_sections[_index].label)),
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          Navigator.pop(context);
          _go(i);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
            child: Row(children: [
              Icon(Icons.savings_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('FinanzApp', style: Theme.of(context).textTheme.titleLarge),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 16, 16),
            child: Text(email, style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final s in _sections)
            NavigationDrawerDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label)),
          const Divider(indent: 28, endIndent: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(leading: const Icon(Icons.logout), title: const Text('Cerrar sesión'), onTap: _logout),
          ),
        ],
      ),
      body: page,
    );
  }
}
