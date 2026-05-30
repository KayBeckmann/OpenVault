import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

/// Full-screen folder browser. Returns the selected absolute path via [Navigator.pop],
/// or null if the user cancels.
class FolderPickerDialog extends StatefulWidget {
  const FolderPickerDialog({super.key, required this.initialPath});
  final String initialPath;

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  late String _current;
  List<String> _dirs = [];
  bool _loading = false;
  String? _error;
  final _newFolderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _current = widget.initialPath;
    _load(_current);
  }

  @override
  void dispose() {
    _newFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = Directory(path)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !_name(d.path).startsWith('.'))
          .map((d) => d.path)
          .toList()
        ..sort();
      setState(() { _dirs = entries; _loading = false; });
    } catch (e) {
      setState(() { _dirs = []; _error = 'Zugriff verweigert'; _loading = false; });
    }
  }

  void _navigate(String path) {
    setState(() => _current = path);
    _load(path);
  }

  void _goUp() {
    final parent = Directory(_current).parent;
    if (parent.path != _current) _navigate(parent.path);
  }

  Future<void> _createFolder(String name) async {
    final newPath = '$_current${Platform.pathSeparator}$name';
    try {
      Directory(newPath).createSync(recursive: true);
      _navigate(newPath);
    } catch (e) {
      if (mounted) setState(() => _error = 'Fehler: $e');
    }
  }

  void _showNewFolderDialog() {
    _newFolderCtrl.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Neuer Ordner',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(
          controller: _newFolderCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Ordnername'),
          onSubmitted: (v) {
            Navigator.pop(ctx);
            if (v.trim().isNotEmpty) _createFolder(v.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final v = _newFolderCtrl.text.trim();
              Navigator.pop(ctx);
              if (v.isNotEmpty) _createFolder(v);
            },
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );
  }

  String _name(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.lastWhere((s) => s.isNotEmpty, orElse: () => path);
  }

  // Splits current path into clickable breadcrumb segments.
  List<({String label, String path})> get _breadcrumbs {
    final sep = Platform.isWindows ? '\\' : '/';
    final parts = _current.split(sep).where((s) => s.isNotEmpty).toList();
    final result = <({String label, String path})>[];
    for (int i = 0; i < parts.length; i++) {
      final p = (Platform.isWindows ? '' : '/') + parts.sublist(0, i + 1).join(sep);
      result.add((label: parts[i], path: p));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = _breadcrumbs;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Ordner wählen',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'Neuer Ordner',
            onPressed: _showNewFolderDialog,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, _current),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Auswählen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb navigation
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (Directory(_current).parent.path != _current)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 16, color: AppColors.primary),
                    onPressed: _goUp,
                    tooltip: 'Eine Ebene hoch',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ...crumbs.asMap().entries.map((e) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.key > 0)
                      Text(' / ', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.outline)),
                    InkWell(
                      onTap: () => _navigate(e.value.path),
                      child: Text(
                        e.value.label,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: e.key == crumbs.length - 1
                              ? AppColors.onSurface
                              : AppColors.primary,
                          fontWeight: e.key == crumbs.length - 1
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                )),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.error)),
            ),
          const Divider(height: 1, color: AppColors.outlineVariant),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _dirs.isEmpty
                    ? Center(
                        child: Text(
                          'Keine Unterordner',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.outline),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _dirs.length,
                        itemBuilder: (_, i) {
                          final name = _name(_dirs[i]);
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.folder, size: 20, color: AppColors.primary),
                            title: Text(name,
                                style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface)),
                            trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.outline),
                            onTap: () => _navigate(_dirs[i]),
                          );
                        },
                      ),
          ),
          // Current selection indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppColors.surfaceContainerHigh,
            child: Text(
              _current,
              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
