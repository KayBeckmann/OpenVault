import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<Map<String, dynamic>> _vaults = [];
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadVaults();
  }

  Future<void> _loadVaults() async {
    setState(() { _loading = true; _error = null; });
    try {
      final vaults = await ApiClient().getList('/api/vaults/');
      setState(() { _vaults = vaults; });
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _cloneVault(String name, String remoteUrl) async {
    setState(() { _working = true; _error = null; _statusMessage = 'Cloning repository…'; });
    try {
      await ApiClient().post('/api/vaults/clone', {'name': name, 'remoteUrl': remoteUrl});
      setState(() { _statusMessage = 'Clone successful!'; });
      await _loadVaults();
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _working = false; });
    }
  }

  Future<void> _pullVault(String id) async {
    setState(() { _working = true; _statusMessage = 'Pulling changes…'; _error = null; });
    try {
      final result = await ApiClient().post('/api/vaults/$id/pull', {});
      setState(() { _statusMessage = result['output'] as String? ?? 'Up to date'; });
      await _loadVaults();
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _working = false; });
    }
  }

  Future<void> _pushVault(String id, String message) async {
    setState(() { _working = true; _statusMessage = 'Pushing changes…'; _error = null; });
    try {
      final result = await ApiClient().post('/api/vaults/$id/push', {'commitMessage': message});
      final committed = result['committed'] as bool? ?? false;
      setState(() { _statusMessage = committed ? 'Changes pushed!' : 'Nothing to commit'; });
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _working = false; });
    }
  }

  Future<void> _deleteVault(String id) async {
    setState(() { _working = true; });
    try {
      await ApiClient().delete('/api/vaults/$id');
      await _loadVaults();
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _working = false; });
    }
  }

  void _showCloneDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Clone Vault', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Vault name'), autofocus: true),
            const SizedBox(height: 16),
            TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Git remote URL (HTTPS or SSH)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && urlCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                _cloneVault(nameCtrl.text.trim(), urlCtrl.text.trim());
              }
            },
            child: const Text('Clone'),
          ),
        ],
      ),
    );
  }

  void _showPushDialog(String vaultId) {
    final ctrl = TextEditingController(text: 'Update from OpenVault');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Commit & Push', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Commit message')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _pushVault(vaultId, ctrl.text); },
            child: const Text('Push'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Vaults'),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          if (_working) const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _working ? null : _showCloneDialog, tooltip: 'Clone vault'),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null || _error != null)
            _StatusBanner(message: _error ?? _statusMessage!, isError: _error != null),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _vaults.isEmpty
                    ? _EmptyState(onClone: _showCloneDialog)
                    : _VaultList(vaults: _vaults, onPull: _pullVault, onPush: _showPushDialog, onDelete: _deleteVault),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isError ? AppColors.errorContainer : AppColors.surfaceContainerHigh,
      child: Text(message, style: GoogleFonts.inter(
        fontSize: 13,
        color: isError ? AppColors.onError : AppColors.primary,
      )),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onClone});
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_download_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('No vaults yet', style: GoogleFonts.spaceGrotesk(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text('Clone a Git repository to start editing your vault.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: onClone, icon: const Icon(Icons.cloud_download), label: const Text('Clone Vault')),
        ],
      ),
    );
  }
}

class _VaultList extends StatelessWidget {
  const _VaultList({required this.vaults, required this.onPull, required this.onPush, required this.onDelete});
  final List<Map<String, dynamic>> vaults;
  final Future<void> Function(String) onPull;
  final void Function(String) onPush;
  final Future<void> Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: vaults.map((v) => _VaultCard(
        key: ValueKey(v['id']),
        vault: v,
        onPull: () => onPull(v['id'] as String),
        onPush: () => onPush(v['id'] as String),
        onDelete: () => onDelete(v['id'] as String),
      )).toList(),
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({super.key, required this.vault, required this.onPull, required this.onPush, required this.onDelete});
  final Map<String, dynamic> vault;
  final VoidCallback onPull;
  final VoidCallback onPush;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(vault['name'] as String? ?? '',
                  style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface))),
              IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error), onPressed: onDelete, tooltip: 'Delete'),
            ],
          ),
          const SizedBox(height: 4),
          Text(vault['remoteUrl'] as String? ?? '',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.outline)),
          const SizedBox(height: 4),
          Text('Last synced: ${vault['lastSyncedAt'] ?? 'Never'}',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline)),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onPull,
                icon: const Icon(Icons.download, size: 14),
                label: const Text('Pull'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.outlineVariant),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onPush,
                icon: const Icon(Icons.upload, size: 14),
                label: const Text('Commit & Push'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
