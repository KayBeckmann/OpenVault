import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import 'addons_screen.dart';

class VaultSettingsScreen extends StatefulWidget {
  const VaultSettingsScreen({super.key, required this.vaultId, required this.vaultName});
  final String vaultId;
  final String vaultName;

  @override
  State<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends State<VaultSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _autoPushOnClose = false;
  late TextEditingController _templateFolderCtrl;
  late TextEditingController _defaultNoteFolderCtrl;
  // Per-template target folder overrides (template name → controller).
  final Map<String, TextEditingController> _tplFolderCtrls = {};
  List<String> _templateNames = [];

  @override
  void initState() {
    super.initState();
    _templateFolderCtrl = TextEditingController();
    _defaultNoteFolderCtrl = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _templateFolderCtrl.dispose();
    _defaultNoteFolderCtrl.dispose();
    for (final c in _tplFolderCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ApiClient().get('/api/settings/${widget.vaultId}');
      final tplFolder = result['templateFolder'] as String? ?? '_templates';
      _templateFolderCtrl.text = tplFolder;
      _defaultNoteFolderCtrl.text = result['defaultNoteFolder'] as String? ?? '';
      await _loadTemplates(tplFolder, _parseMap(result['templateFolders']));
      setState(() { _autoPushOnClose = result['autoPushOnClose'] as bool? ?? false; });
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Map<String, String> _parseMap(dynamic raw) {
    if (raw is Map) {
      final out = <String, String>{};
      raw.forEach((k, v) { if (v != null) out[k.toString()] = v.toString(); });
      return out;
    }
    return {};
  }

  Future<void> _loadTemplates(String folder, Map<String, String> overrides) async {
    try {
      final tree = await ApiClient().get('/api/files/${widget.vaultId}/tree');
      final names = <String>[];
      void collect(List nodes) {
        for (final n in nodes) {
          final path = n['path'] as String? ?? '';
          final type = n['type'] as String? ?? '';
          if (type == 'folder') {
            collect(n['children'] as List? ?? []);
          } else if (type == 'file' && path.startsWith('$folder/') && path.endsWith('.md')) {
            names.add(path.split('/').last.replaceAll('.md', ''));
          }
        }
      }
      collect(tree['children'] as List? ?? []);
      names.sort();
      for (final c in _tplFolderCtrls.values) {
        c.dispose();
      }
      _tplFolderCtrls.clear();
      for (final name in names) {
        _tplFolderCtrls[name] = TextEditingController(text: overrides[name] ?? '');
      }
      _templateNames = names;
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final tplFolders = <String, String>{};
      _tplFolderCtrls.forEach((name, ctrl) {
        final v = ctrl.text.trim();
        if (v.isNotEmpty) tplFolders[name] = v;
      });
      await ApiClient().put('/api/settings/${widget.vaultId}', {
        'templateFolder': _templateFolderCtrl.text.trim(),
        'defaultNoteFolder': _defaultNoteFolderCtrl.text.trim(),
        'autoPushOnClose': _autoPushOnClose,
        'templateFolders': tplFolders,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert'), duration: Duration(seconds: 2)),
        );
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Einstellungen — ${widget.vaultName}'),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : Text('Speichern', style: GoogleFonts.spaceGrotesk(color: AppColors.primary)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],
                    _SectionHeader('Notiz-Vorlagen'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _templateFolderCtrl,
                      decoration: InputDecoration(
                        labelText: 'Vorlagen-Ordner',
                        hintText: '_templates',
                        helperText: 'Ordner im Vault, in dem Vorlagen liegen (z.B. _templates)',
                        helperStyle: GoogleFonts.inter(fontSize: 11, color: AppColors.outline),
                        prefixIcon: const Icon(Icons.folder_special_outlined, size: 18, color: AppColors.outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader('Neue Notizen'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _defaultNoteFolderCtrl,
                      decoration: InputDecoration(
                        labelText: 'Standard-Ordner für neue Notizen',
                        hintText: '00_Inbox',
                        helperText: 'Leer = Vault-Wurzel. Ordner wird angelegt falls nicht vorhanden.',
                        helperStyle: GoogleFonts.inter(fontSize: 11, color: AppColors.outline),
                        prefixIcon: const Icon(Icons.create_new_folder_outlined, size: 18, color: AppColors.outline),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader('Ordner je Vorlage'),
                    const SizedBox(height: 4),
                    Text(
                      'Leer = Standard-Ordner. Sonst landet eine mit dieser Vorlage erstellte Notiz hier — außer du drückst „+" direkt in einem Ordner.',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    if (_templateNames.isEmpty)
                      Text('Keine Vorlagen im Vorlagen-Ordner gefunden.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline))
                    else
                      ..._templateNames.map((name) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextFormField(
                              controller: _tplFolderCtrls[name],
                              decoration: InputDecoration(
                                labelText: name,
                                hintText: _defaultNoteFolderCtrl.text.trim().isEmpty
                                    ? 'Standard (Vault-Wurzel)'
                                    : 'Standard (${_defaultNoteFolderCtrl.text.trim()})',
                                prefixIcon: const Icon(Icons.folder_outlined, size: 18, color: AppColors.outline),
                              ),
                            ),
                          )),
                    const SizedBox(height: 24),
                    _SectionHeader('Beim Schließen'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Automatisch committen & pushen', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface)),
                        subtitle: Text(
                          'Alle Änderungen werden beim Schließen des Vaults automatisch committiert und gepusht.',
                          style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline, height: 1.4),
                        ),
                        value: _autoPushOnClose,
                        onChanged: (v) => setState(() => _autoPushOnClose = v),
                        activeThumbColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _SectionHeader('Erweiterungen'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.extension_outlined, color: AppColors.primary),
                        title: Text('Add-Ons',
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface)),
                        subtitle: Text('Module aktivieren (z.B. Tasks)',
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline)),
                        trailing: const Icon(Icons.chevron_right, color: AppColors.outline),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AddonsScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    _InfoCard(),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(message, style: GoogleFonts.inter(fontSize: 13, color: AppColors.onError)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Hinweis', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Vorlagen-Ordner: Obsidian-kompatibel — lege Markdown-Dateien darin ab und sie stehen beim Erstellen neuer Notizen als Vorlage zur Verfügung.\n\n'
            'Standard-Ordner: Neue Notizen werden automatisch in diesem Unterordner des Vaults gespeichert.',
            style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
