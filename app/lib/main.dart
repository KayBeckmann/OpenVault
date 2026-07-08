import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'services/auth_service.dart';
import 'addons/addon_registry.dart';
import 'screens/auth_screen.dart';
import 'screens/vault_screen.dart';
import 'screens/native_vault_screen.dart';

void main() {
  runApp(const OpenVaultApp());
}

class OpenVaultApp extends StatelessWidget {
  const OpenVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return ChangeNotifierProvider(
        create: (_) => AddonRegistry()..load(),
        child: MaterialApp(
          title: 'OpenVault',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: const NativeVaultScreen(),
        ),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AddonRegistry()..load()),
      ],
      child: MaterialApp(
        title: 'OpenVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const _WebRootRouter(),
      ),
    );
  }
}

class _WebRootRouter extends StatefulWidget {
  const _WebRootRouter();

  @override
  State<_WebRootRouter> createState() => _WebRootRouterState();
}

class _WebRootRouterState extends State<_WebRootRouter> {
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    await context.read<AuthService>().tryRestoreSession();
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    final auth = context.watch<AuthService>();
    return auth.isAuthenticated ? const VaultScreen() : const AuthScreen();
  }
}
