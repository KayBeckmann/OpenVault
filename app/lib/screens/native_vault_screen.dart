import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/local_vault_service.dart';
import '../services/ssh_key_service.dart';
import '../widgets/folder_picker_dialog.dart';
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
  SshKeyInfo? _sshKey;
  bool _sshKeyLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSshKey();
  }

  Future<void> _load() async {
    final vaults = await LocalVaultService.loadVaults();
    if (mounted) setState(() { _vaults = vaults; _loading = false; });
  }

  Future<void> _loadSshKey() async {
    final key = await SshKeyService.findKey();
    if (mounted) setState(() { _sshKey = key; _sshKeyLoading = false; });
  }

  Future<void> _generateKey() async {
    setState(() => _sshKeyLoading = true);
    try {
      final key = await SshKeyService.generateKey();
      if (mounted) setState(() { _sshKey = key; _sshKeyLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _sshKeyLoading = false);
        _showStatus('Key-Generierung fehlgeschlagen: $e', isError: true);
      }
    }
  }

  void _showStatus(String msg, {bool isError = false}) =>
      setState(() { _statusMessage = msg; _statusIsError = isError; });

  Future<void> _showAddDialog() async {
    final result = await showDialog<_VaultAction>(
      context: context,
      builder: (_) => _AddVaultDialog(sshKey: _sshKey),
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
      final result = await LocalVaultService.cloneRepo(
        action.remoteUrl!,
        action.localPath!,
        sshKeyPath: action.sshKeyPath,
      );
      if (!result.success) {
        if (mounted) setState(() { _statusMessage = result.output.isNotEmpty ? result.output : 'Clone fehlgeschlagen'; _statusIsError = true; });
        return;
      }
      final vault = await LocalVaultService.addVault(
        name: action.name,
        localPath: action.localPath!,
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
          _SshKeyCard(
            keyInfo: _sshKey,
            loading: _sshKeyLoading,
            onGenerate: _generateKey,
          ),
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

// ── SSH Key Card ──────────────────────────────────────────────────────────────

class _SshKeyCard extends StatelessWidget {
  const _SshKeyCard({required this.keyInfo, required this.loading, required this.onGenerate});
  final SshKeyInfo? keyInfo;
  final bool loading;
  final VoidCallback onGenerate;

  String _platformNote() {
    if (Platform.isAndroid) return 'App-verwalteter Key (in App-Verzeichnis)';
    if (Platform.isWindows) return 'System-Key (%USERPROFILE%\\.ssh\\)';
    return 'System-Key (~/.ssh/)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surfaceContainerHigh,
      child: loading
          ? Row(children: [
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
              const SizedBox(width: 10),
              Text('SSH-Key wird gesucht …',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ])
          : keyInfo == null
              ? Row(children: [
                  const Icon(Icons.key_off_outlined, size: 16, color: AppColors.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kein SSH-Key gefunden',
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                        Text(_platformNote(),
                            style: GoogleFonts.inter(fontSize: 10, color: AppColors.outline)),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onGenerate,
                    icon: const Icon(Icons.generating_tokens, size: 14),
                    label: const Text('Generieren'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ])
              : Row(children: [
                  const Icon(Icons.key, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          keyInfo!.isSystemKey ? 'System-Key' : 'App-Key',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,
                              color: AppColors.onSurface),
                        ),
                        Text(
                          keyInfo!.privateKeyPath,
                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    tooltip: 'Public Key kopieren',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: keyInfo!.publicKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Public Key kopiert'), duration: Duration(seconds: 2)),
                      );
                    },
                    color: AppColors.onSurfaceVariant,
                  ),
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    tooltip: 'Public Key anzeigen',
                    onPressed: () => _showPublicKey(context),
                    color: AppColors.onSurfaceVariant,
                  ),
                ]),
    );
  }

  void _showPublicKey(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Public Key', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Füge diesen Key bei GitHub / GitLab / Gitea unter\nSettings → SSH Keys hinzu.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                keyInfo!.publicKey,
                style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.onSurface),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: keyInfo!.publicKey));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Kopieren & Schließen'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
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
            Row(children: [
              const Icon(Icons.link, size: 12, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(vault['remoteUrl'] as String,
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
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
    this.sshKeyPath,
  });
  final String name;
  final bool clone;
  final String? localPath;
  final String? remoteUrl;
  final String? sshKeyPath;
}

// ── Add / Clone Dialog ────────────────────────────────────────────────────────

class _AddVaultDialog extends StatefulWidget {
  const _AddVaultDialog({this.sshKey});
  final SshKeyInfo? sshKey;

  @override
  State<_AddVaultDialog> createState() => _AddVaultDialogState();
}

class _AddVaultDialogState extends State<_AddVaultDialog> {
  bool _cloneMode = false;
  final _nameCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  bool _initializingPath = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_autoFillName);
    _initDefaultPath();
  }

  Future<void> _initDefaultPath() async {
    setState(() => _initializingPath = true);
    final path = await SshKeyService.defaultVaultPath();
    if (mounted) {
      setState(() {
        if (_pathCtrl.text.isEmpty) _pathCtrl.text = path;
        _initializingPath = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _autoFillName() {
    if (!_cloneMode || _nameCtrl.text.isNotEmpty) return;
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final segment = url.split('/').last.replaceAll('.git', '');
    if (segment.isNotEmpty) _nameCtrl.text = segment;
  }

  Future<void> _browseFolder() async {
    final startPath = _pathCtrl.text.trim().isNotEmpty
        ? _pathCtrl.text.trim()
        : await SshKeyService.browseRoot();
    if (!mounted) return;
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FolderPickerDialog(initialPath: startPath),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        if (_cloneMode && _nameCtrl.text.isNotEmpty) {
          _pathCtrl.text = '$selected${Platform.pathSeparator}${_nameCtrl.text.trim()}';
        } else {
          _pathCtrl.text = selected;
        }
      });
    }
  }

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
      sshKeyPath: widget.sshKey?.privateKeyPath,
    ));
  }

  String _sshNote() {
    if (widget.sshKey == null) return 'Kein SSH-Key — nur HTTPS-Clone möglich';
    return 'SSH-Key: ${widget.sshKey!.privateKeyPath}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text(_cloneMode ? 'Vault clonen' : 'Vault hinzufügen',
          style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _ModeChip(
                  label: 'Vorhandener Ordner',
                  icon: Icons.folder_open,
                  active: !_cloneMode,
                  onTap: () => setState(() { _cloneMode = false; }),
                ),
                const SizedBox(width: 8),
                _ModeChip(
                  label: 'Clone via Git',
                  icon: Icons.cloud_download_outlined,
                  active: _cloneMode,
                  onTap: () => setState(() { _cloneMode = true; }),
                ),
              ]),
              const SizedBox(height: 16),

              if (_cloneMode) ...[
                TextField(
                  controller: _urlCtrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Git Remote URL',
                    hintText: 'git@github.com:user/vault.git',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                // SSH key note
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Icon(
                      widget.sshKey != null ? Icons.key : Icons.key_off_outlined,
                      size: 13,
                      color: widget.sshKey != null ? AppColors.primary : AppColors.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_sshNote(),
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Hinweis: git-Binary auf Android nicht verfügbar — Clone schlägt fehl.\n'
                    'libgit2dart-Integration ist in Phase 4 geplant.',
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.outline),
                  ),
                ],
              ] else ...[
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ],

              const SizedBox(height: 12),
              // Path field with browse button
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _pathCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _cloneMode ? 'Zielverzeichnis' : 'Lokaler Pfad',
                      hintText: _cloneMode ? '/home/user/vaults/mein-vault' : '/home/user/mein-vault',
                      suffixIcon: _initializingPath
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2,
                                      color: AppColors.primary)),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _browseFolder,
                  icon: const Icon(Icons.folder_open, color: AppColors.primary),
                  tooltip: 'Ordner durchsuchen',
                ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
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
