import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';

class SshKeysScreen extends StatefulWidget {
  const SshKeysScreen({super.key});

  @override
  State<SshKeysScreen> createState() => _SshKeysScreenState();
}

class _SshKeysScreenState extends State<SshKeysScreen> {
  List<Map<String, dynamic>> _keys = [];
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() { _loading = true; _error = null; });
    try {
      final keys = await ApiClient().getList('/api/ssh-keys/');
      setState(() { _keys = keys; });
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _generateKey(String label) async {
    setState(() { _generating = true; _error = null; });
    try {
      await ApiClient().post('/api/ssh-keys/', {'label': label});
      await _loadKeys();
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _generating = false; });
    }
  }

  Future<void> _deleteKey(String id) async {
    try {
      await ApiClient().delete('/api/ssh-keys/$id');
      await _loadKeys();
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    }
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('New SSH Key', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Label (e.g. GitHub)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                _generateKey(ctrl.text.trim());
              }
            },
            child: const Text('Generate'),
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
        title: const Text('SSH Keys'),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          IconButton(
            icon: _generating
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.add),
            onPressed: _generating ? null : _showAddDialog,
            tooltip: 'Generate new key',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _keys.isEmpty
              ? _EmptyState(onAdd: _showAddDialog)
              : _KeyList(keys: _keys, onDelete: _deleteKey, error: _error),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.key_off_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('No SSH keys yet',
              style: GoogleFonts.spaceGrotesk(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text('Generate a key to connect to GitHub, GitLab, or Gitea.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Generate SSH Key'),
          ),
        ],
      ),
    );
  }
}

class _KeyList extends StatelessWidget {
  const _KeyList({required this.keys, required this.onDelete, this.error});
  final List<Map<String, dynamic>> keys;
  final Future<void> Function(String) onDelete;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(error!,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.onError)),
          ),
        ...keys.map((k) => _KeyCard(key: ValueKey(k['id']), keyData: k, onDelete: onDelete)),
      ],
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({super.key, required this.keyData, required this.onDelete});
  final Map<String, dynamic> keyData;
  final Future<void> Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    final publicKey = keyData['publicKey'] as String? ?? '';
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
              const Icon(Icons.key, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(keyData['label'] as String? ?? '',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: AppColors.onSurfaceVariant),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: publicKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Public key copied to clipboard')),
                  );
                },
                tooltip: 'Copy public key',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                onPressed: () => _confirmDelete(context),
                tooltip: 'Delete key',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              publicKey.length > 80 ? '${publicKey.substring(0, 80)}…' : publicKey,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: AppColors.onSurfaceVariant, height: 1.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Created ${keyData['createdAt'] ?? ''}',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Delete key?',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Text('This will permanently remove "${keyData['label']}". The key cannot be recovered.',
            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorContainer),
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(keyData['id'] as String);
            },
            child: Text('Delete', style: GoogleFonts.spaceGrotesk(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
