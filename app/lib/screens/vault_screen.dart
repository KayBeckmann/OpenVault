import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'file_browser_screen.dart';
import 'ssh_keys_screen.dart';
import 'vault_settings_screen.dart';

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

  Future<void> _cloneVault(String name, String remoteUrl, {String? sshKeyId}) async {
    setState(() { _working = true; _error = null; _statusMessage = 'Cloning repository…'; });
    try {
      await ApiClient().post('/api/vaults/clone', {
        'name': name,
        'remoteUrl': remoteUrl,
        if (sshKeyId != null) 'sshKeyId': sshKeyId,
      });
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
    showDialog<void>(
      context: context,
      builder: (ctx) => _CloneDialog(onClone: _cloneVault),
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
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'SSH-Keys',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SshKeysScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
            onPressed: () => context.read<AuthService>().logout(),
          ),
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FileBrowserScreen(
                    vaultId: vault['id'] as String,
                    vaultName: vault['name'] as String? ?? 'Vault',
                  )),
                ),
                icon: const Icon(Icons.folder_open, size: 14),
                label: const Text('Öffnen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryContainer,
                  foregroundColor: AppColors.onSecondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 18, color: AppColors.onSurfaceVariant),
                tooltip: 'Einstellungen',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VaultSettingsScreen(
                    vaultId: vault['id'] as String,
                    vaultName: vault['name'] as String? ?? 'Vault',
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloneDialog extends StatefulWidget {
  const _CloneDialog({required this.onClone});
  final void Function(String name, String url, {String? sshKeyId}) onClone;

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  List<Map<String, dynamic>> _keys = [];
  String? _selectedKeyId;
  bool _loadingKeys = true;
  bool _isSsh = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(_onUrlChanged);
    _loadKeys();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final isSsh = _urlCtrl.text.startsWith('git@') || _urlCtrl.text.startsWith('ssh://');
    if (isSsh != _isSsh) setState(() => _isSsh = isSsh);
  }

  Future<void> _loadKeys() async {
    try {
      final keys = await ApiClient().getList('/api/ssh-keys/');
      if (mounted) setState(() { _keys = keys; _loadingKeys = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingKeys = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text('Clone Vault', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Vault name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                labelText: 'Git remote URL',
                hintText: _isSsh ? 'git@github.com:user/repo.git' : 'https://github.com/user/repo.git',
                helperText: _isSsh ? 'SSH — select a key below' : 'HTTPS — no key needed for public repos',
                helperStyle: GoogleFonts.inter(
                  fontSize: 11,
                  color: _isSsh ? AppColors.primary : AppColors.outline,
                ),
              ),
            ),
            if (_isSsh) ...[
              const SizedBox(height: 16),
              Text(
                'SSH Key',
                style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (_loadingKeys)
                const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              else if (_keys.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer.withAlpha(60),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.error.withAlpha(80)),
                  ),
                  child: Text(
                    'No SSH keys found. Generate one under "Manage SSH Keys" first.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.error),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedKeyId,
                  hint: Text('Select SSH key', style: GoogleFonts.inter(fontSize: 13, color: AppColors.outline)),
                  dropdownColor: AppColors.surfaceContainerHigh,
                  decoration: const InputDecoration(isDense: true),
                  items: _keys.map((k) => DropdownMenuItem<String>(
                    value: k['id'] as String,
                    child: Text(
                      k['label'] as String? ?? k['id'] as String,
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface),
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedKeyId = v),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _canSubmit() ? _submit : null,
          child: const Text('Clone'),
        ),
      ],
    );
  }

  bool _canSubmit() {
    if (_nameCtrl.text.trim().isEmpty || _urlCtrl.text.trim().isEmpty) return false;
    if (_isSsh && _keys.isNotEmpty && _selectedKeyId == null) return false;
    return true;
  }

  void _submit() {
    Navigator.pop(context);
    widget.onClone(
      _nameCtrl.text.trim(),
      _urlCtrl.text.trim(),
      sshKeyId: _isSsh ? _selectedKeyId : null,
    );
  }
}
