import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/native_vault_screen.dart';

void main() {
  runApp(const OpenVaultApp());
}

class OpenVaultApp extends StatelessWidget {
  const OpenVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return MaterialApp(
        title: 'OpenVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const NativeVaultScreen(),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: MaterialApp(
        title: 'OpenVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const _WebRootRouter(),
      ),
    );
  }
}

class _WebRootRouter extends StatelessWidget {
  const _WebRootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return auth.isAuthenticated ? const HomeScreen() : const AuthScreen();
  }
}
