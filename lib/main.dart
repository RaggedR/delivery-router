import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/route_provider.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeliveryRouterApp());
}

class DeliveryRouterApp extends StatelessWidget {
  const DeliveryRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RouteProvider(),
      child: MaterialApp(
        title: 'Delivery Router',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4F46E5), // indigo from study-tool
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF8F9FA),
            foregroundColor: Color(0xFF1A202C),
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF818CF8), // lighter indigo for dark
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E293B),
            foregroundColor: Color(0xFFE2E8F0),
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          cardTheme: const CardThemeData(
            color: Color(0xFF1E293B),
          ),
          dividerTheme: const DividerThemeData(
            color: Color(0xFF334155),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
