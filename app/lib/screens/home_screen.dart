import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../widgets/sidebar.dart';
import 'ssh_keys_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          if (isMobile) {
            return _MobileLayout();
          }
          return _DesktopLayout();
        },
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 280, child: Sidebar()),
        Container(width: 1, color: AppColors.outlineVariant),
        Expanded(child: _ContentArea()),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'OpenVault',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: AppColors.onSurface),
            onPressed: () {},
          ),
        ],
      ),
      body: _ContentArea(),
    );
  }
}

class _ContentArea extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'OpenVault',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: -1.92,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Self-hosted, Git-synchronized Markdown vault',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              _StatusCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusRow(icon: Icons.check_circle, label: 'Phase 1: Setup', done: true),
          const SizedBox(height: 8),
          _StatusRow(icon: Icons.check_circle, label: 'Phase 2: Authentication', done: true),
          const SizedBox(height: 8),
          _StatusRow(icon: Icons.check_circle, label: 'Phase 3: SSH-Keys', done: true),
          const SizedBox(height: 8),
          _StatusRow(icon: Icons.merge_type, label: 'Phase 4: Git Integration', done: false),
          const SizedBox(height: 8),
          _StatusRow(icon: Icons.folder_outlined, label: 'Phase 5: File Browser', done: false),
          const SizedBox(height: 8),
          _StatusRow(icon: Icons.edit_outlined, label: 'Phase 6: Markdown Editor', done: false),
          const SizedBox(height: 24),
          _NavigationRow(
            icon: Icons.key,
            label: 'Manage SSH Keys',
            onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SshKeysScreen())),
          ),
          const SizedBox(height: 8),
          _NavigationRow(
            icon: Icons.logout,
            label: 'Sign out',
            onTap: (ctx) => ctx.read<AuthService>().logout(),
            color: AppColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.label, required this.done});

  final IconData icon;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: done ? AppColors.primary : AppColors.outline,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: done ? AppColors.onSurface : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext) onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return InkWell(
      onTap: () => onTap(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(fontSize: 14, color: c)),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: c),
          ],
        ),
      ),
    );
  }
}
