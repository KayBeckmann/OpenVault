import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/local_vault_service.dart';
import 'file_browser_screen.dart';

class NativeVaultScreen extends StatefulWidget {
  const NativeVaultScreen({super.key});

  @override
  State<NativeVaultScreen> createState() => _NativeVaultScreenState();
}

class _NativeVaultScreenState extends State<NativeVaultScreen> {
  List<Map<String, dynamic>> _vaults = [];
  bool _loading = true;
  bool _cloning = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vaults = await LocalVaultService.loadVaults();
    if (mounted) setState(() { _vaults = vaults; _loading = false; });
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<_VaultAction>(
      context: context,
      builder: (_) => const _AddVaultDialog(),
    );
    if (result == null) return;

    if (result.clone) {
      await _cloneAndAdd(result);
    } else {
      final vault = await LocalVaultService.addVault(
        name: result.name,
        localPath: result.localPath!,
        remoteUrl: result.remoteUrl,
      );
      if (mounted) setState(() => _vaults.add(vault));
    }
  }

  Future<void> _cloneAndAdd(_VaultAction action) async {
    setState(() { _cloning = true; _statusMessage = 'Cloning ${action.remoteUrl} …'; _statusIsError = false; });
    try {
      final dest = action.localPath!;
      final result = await LocalVaultService.cloneRepo(action.remoteUrl!, dest);
      if (!result.success) {
        if (mounted) setState(() { _statusMessage = result.output.isNotEmpty ? result.output : 'Clone fehlgeschlagen'; _statusIsError = true; });
        return;
      }
      final vault = await LocalVaultService.addVault(
        name: action.name,
        localPath: dest,
        remoteUrl: action.remoteUrl,
      );
      if (mounted) setState(() { _vaults.add(vault); _statusMessage = 'Clone erfolgreich!'; _statusIsError = false; });
    } catch (e) {
      if (mounted) setState(() { _statusMessage = 'Fehler: $e'; _statusIsError = true; });
    } finally {
      if (mounted) setState(() => _cloning = false);
    }
  }

  Future<void> _removeVault(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Vault entfernen?',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Text(
          'Den Vault aus der Liste entfernen?\nDie Dateien auf der Festplatte bleiben erhalten.',
          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorContainer),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Entfernen', style: GoogleFonts.spaceGrotesk(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalVaultService.removeVault(id);
    if (mounted) setState(() => _vaults.removeWhere((v) => v['id'] == id));
  }

  void _openVault(Map<String, dynamic> vault) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FileBrowserScreen(
        localPath: vault['localPath'] as String,
        vaultName: vault['name'] as String? ?? 'Vault',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('OpenVault',
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700, color: AppColors.primary)),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          if (_cloning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            )
          else
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddDialog,
              tooltip: 'Vault hinzufügen / clonen',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            _StatusBanner(
              message: _statusMessage!,
              isError: _statusIsError,
              onDismiss: () => setState(() => _statusMessage = null),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _vaults.isEmpty
                    ? _EmptyState(onAdd: _showAddDialog)
                    : _VaultList(vaults: _vaults, onOpen: _openVault, onRemove: _removeVault),
          ),
        ],
      ),
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError, required this.onDismiss});
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isError ? AppColors.errorContainer : AppColors.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isError ? AppColors.onError : AppColors.primary)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            color: isError ? AppColors.onError : AppColors.onSurfaceVariant,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('Noch keine Vaults',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text(
            'Füge einen lokalen Vault-Ordner hinzu\noder clone ein Git-Repository.',
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Vault hinzufügen'),
          ),
        ],
      ),
    );
  }
}

// ── Vault list ────────────────────────────────────────────────────────────────

class _VaultList extends StatelessWidget {
  const _VaultList({required this.vaults, required this.onOpen, required this.onRemove});
  final List<Map<String, dynamic>> vaults;
  final void Function(Map<String, dynamic>) onOpen;
  final Future<void> Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: vaults
          .map((v) => _VaultCard(
                key: ValueKey(v['id']),
                vault: v,
                onOpen: () => onOpen(v),
                onRemove: () => onRemove(v['id'] as String),
              ))
          .toList(),
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({super.key, required this.vault, required this.onOpen, required this.onRemove});
  final Map<String, dynamic> vault;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

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
              Expanded(
                child: Text(vault['name'] as String? ?? '',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface)),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                onPressed: onRemove,
                tooltip: 'Entfernen',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(vault['localPath'] as String? ?? '',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.outline)),
          if (vault['remoteUrl'] != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.link, size: 12, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(vault['remoteUrl'] as String,
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open, size: 14),
            label: const Text('Öffnen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action model ──────────────────────────────────────────────────────────────

class _VaultAction {
  const _VaultAction({
    required this.name,
    required this.clone,
    this.localPath,
    this.remoteUrl,
  });
  final String name;
  final bool clone;
  final String? localPath;
  final String? remoteUrl;
}

// ── Add / Clone Dialog ────────────────────────────────────────────────────────

class _AddVaultDialog extends StatefulWidget {
  const _AddVaultDialog();

  @override
  State<_AddVaultDialog> createState() => _AddVaultDialogState();
}

class _AddVaultDialogState extends State<_AddVaultDialog> {
  bool _cloneMode = false;
  final _nameCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_autoFillName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // Auto-fill name from last path segment of the remote URL
  void _autoFillName() {
    if (!_cloneMode || _nameCtrl.text.isNotEmpty) return;
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final segment = url.split('/').last.replaceAll('.git', '');
    if (segment.isNotEmpty) _nameCtrl.text = segment;
  }

  // Auto-fill destination path from name
  void _autoFillPath() {
    if (!_cloneMode) return;
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty && _pathCtrl.text.isEmpty) {
      _pathCtrl.text = '${_homeDir()}/$name';
    }
  }

  String _homeDir() =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/home/user';

  bool get _valid {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_cloneMode) return _urlCtrl.text.trim().isNotEmpty && _pathCtrl.text.trim().isNotEmpty;
    return _pathCtrl.text.trim().isNotEmpty;
  }

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, _VaultAction(
      name: _nameCtrl.text.trim(),
      clone: _cloneMode,
      localPath: _pathCtrl.text.trim(),
      remoteUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text(_cloneMode ? 'Vault clonen' : 'Vault hinzufügen',
          style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode toggle
            Row(
              children: [
                _ModeChip(
                  label: 'Vorhandener Ordner',
                  icon: Icons.folder_open,
                  active: !_cloneMode,
                  onTap: () => setState(() { _cloneMode = false; _pathCtrl.clear(); }),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Clone via Git',
                  icon: Icons.cloud_download_outlined,
                  active: _cloneMode,
                  onTap: () => setState(() { _cloneMode = true; _pathCtrl.clear(); }),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_cloneMode) ...[
              TextField(
                controller: _urlCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Git Remote URL',
                  hintText: 'git@github.com:user/vault.git',
                  helperText: 'SSH-Key aus ~/.ssh/ wird automatisch verwendet',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                onEditingComplete: _autoFillPath,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Zielverzeichnis',
                  hintText: '/home/user/vaults/mein-vault',
                  helperText: 'Ordner wird angelegt wenn nicht vorhanden',
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Lokaler Pfad',
                  hintText: '/home/user/git/mein-vault',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: _valid ? _submit : null,
          icon: Icon(_cloneMode ? Icons.cloud_download : Icons.add, size: 16),
          label: Text(_cloneMode ? 'Clonen' : 'Hinzufügen'),
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(30) : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.outlineVariant,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? AppColors.primary : AppColors.outline),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: active ? AppColors.primary : AppColors.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
