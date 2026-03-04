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
import 'aprs/aprs_is_service.dart';
import 'services/igate_service.dart';
import 'services/noaa_service.dart';
import 'services/spotter_service.dart';
import 'services/track_service.dart';
import 'services/bbs_service.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/near_repeater/near_repeater_screen.dart';
import 'screens/aprs_map/aprs_map_screen.dart';
import 'screens/weather/weather_screen.dart';
import 'screens/messages/messages_screen.dart';
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
        ChangeNotifierProvider(create: (_) => AprsIsService()),
        ChangeNotifierProvider(create: (_) {
          final svc = IgateService();
          svc.init();
          return svc;
        }),
        ChangeNotifierProvider(create: (_) => NoaaService()),
        ChangeNotifierProvider(create: (_) {
          final svc = SpotterService();
          svc.init();
          return svc;
        }),
        ChangeNotifierProvider(create: (_) => TrackService()),
        ChangeNotifierProvider(create: (_) {
          final svc = BbsService();
          svc.init();
          return svc;
        }),
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
          cardTheme: CardThemeData(
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
  bool _radioWasConnected = false;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(onNavigate: (i) => setState(() => _selectedIndex = i)),
      const NearRepeaterScreen(),
      const AprsMapScreen(),
      const WeatherScreen(),
      const MessagesScreen(),
      const SettingsScreen(),
    ];
    // Wire adaptive GPS: switch to high-frequency when radio connects
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAdaptiveGps());
  }

  void _initAdaptiveGps() {
    final radio = context.read<RadioService>();
    final gps   = context.read<GpsService>();

    radio.addListener(() {
      // Only switch GPS frequency when connection state actually changes,
      // not on every radio packet notification.
      final nowConnected = radio.isConnected;
      if (nowConnected == _radioWasConnected) return;
      _radioWasConnected = nowConnected;
      if (nowConnected) {
        gps.setHighFrequency();
      } else {
        gps.setLowFrequency();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bbs = context.watch<BbsService>();

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
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.cell_tower_outlined),
            selectedIcon: Icon(Icons.cell_tower),
            label: 'Repeaters',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'APRS Map',
          ),
          const NavigationDestination(
            icon: Icon(Icons.thunderstorm_outlined),
            selectedIcon: Icon(Icons.thunderstorm),
            label: 'Weather',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: bbs.unreadCount > 0,
              label: Text('${bbs.unreadCount}'),
              child: const Icon(Icons.mail_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: bbs.unreadCount > 0,
              label: Text('${bbs.unreadCount}'),
              child: const Icon(Icons.mail),
            ),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
