// lib/main.dart
// OpenHT - Open-source Android controller for VGC/Benshi protocol radios
// github.com/repins267/OpenHT
//
// Protocol based on benlink by Kyle Husmann KC3SLD
// https://github.com/khusmann/benlink
//
// flutter_benlink port by SarahRoseLives
// https://github.com/SarahRoseLives/flutter_benlink
//
// APRS parsing based on aprs-parser by Lee K0QED
// https://github.com/k0qed/aprs-parser
//
// Inspired by HtStation by Ylianst
// https://github.com/Ylianst/HtStation

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'bluetooth/radio_service.dart';
import 'services/gps_service.dart';
import 'aprs/aprs_service.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/near_repeater/near_repeater_screen.dart';
import 'screens/aprs_map/aprs_map_screen.dart';
import 'screens/settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenHtApp());
}

class OpenHtApp extends StatelessWidget {
  const OpenHtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RadioService()),
        ChangeNotifierProvider(create: (_) => GpsService()..startTracking()),
        ChangeNotifierProvider(create: (_) => AprsService()),
      ],
      child: MaterialApp(
        title: 'OpenHT',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.dark(
            primary: Colors.blue[700]!,
            secondary: Colors.green[600]!,
            surface: Colors.grey[850]!,
            background: Colors.grey[900]!,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.grey[900],
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.grey[850],
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          cardTheme: CardTheme(
            color: Colors.grey[850],
            elevation: 2,
          ),
          chipTheme: ChipThemeData(
            backgroundColor: Colors.grey[800],
            labelStyle: const TextStyle(color: Colors.white70),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
          ),
        ),
        home: const OpenHtShell(),
      ),
    );
  }
}

class OpenHtShell extends StatefulWidget {
  const OpenHtShell({super.key});

  @override
  State<OpenHtShell> createState() => _OpenHtShellState();
}

class _OpenHtShellState extends State<OpenHtShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    DashboardScreen(),
    NearRepeaterScreen(),
    AprsMapScreen(),
    SettingsScreen(),
  ];

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.cell_tower_outlined),
      selectedIcon: Icon(Icons.cell_tower),
      label: 'Near Repeater',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: 'APRS Map',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final radio = context.watch<RadioService>();

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.grey[850],
        indicatorColor: Colors.blue[900],
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _destinations,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
    );
  }
}
