import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import '../widgets/obsidian_preview.dart';
import 'editor_screen.dart';
import 'tags_screen.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key, required this.vaultId, required this.vaultName});

  final String vaultId;
  final String vaultName;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  List<dynamic> _tree = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _sidebarOpen = true;
  String? _activeFilePath;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTree() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ApiClient().get('/api/files/${widget.vaultId}/tree');
      setState(() { _tree = result['children'] as List? ?? []; });
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; });
      return;
    }
    try {
      final results = await ApiClient().getList(
        '/api/files/${widget.vaultId}/search?q=${Uri.encodeQueryComponent(query)}',
      );
      setState(() { _searchResults = results; });
    } on ApiException catch (_) {
      setState(() { _searchResults = []; });
    }
  }

  Future<void> _createFile(String parentPath) async {
    final ctrl = TextEditingController(text: 'neue-notiz.md');
    final created = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Neue Datei', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Dateiname'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              final path = parentPath.isEmpty ? name : '$parentPath/$name';
              Navigator.pop(ctx, path);
            },
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );
    if (created == null) return;
    await ApiClient().put('/api/files/${widget.vaultId}/file', {'path': created, 'content': ''});
    await _loadTree();
    _openFile(created);
  }

  Future<void> _deleteFile(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Löschen?', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Text('"$path" endgültig löschen?', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorContainer),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Löschen', style: GoogleFonts.spaceGrotesk(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiClient().delete('/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(path)}');
    if (_activeFilePath == path) setState(() => _activeFilePath = null);
    await _loadTree();
  }

  void _openFile(String path) {
    setState(() => _activeFilePath = path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.vaultName),
        backgroundColor: AppColors.surfaceContainerLow,
        leading: IconButton(
          icon: Icon(_sidebarOpen ? Icons.menu_open : Icons.menu),
          tooltip: _sidebarOpen ? 'Sidebar einklappen' : 'Sidebar ausklappen',
          onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _createFile(''), tooltip: 'Neue Datei'),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Tags',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => TagsScreen(vaultId: widget.vaultId, vaultName: widget.vaultName),
            )),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTree, tooltip: 'Aktualisieren'),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final isDesktop = constraints.maxWidth >= 700;

          if (!isDesktop) {
            // Mobile: sidebar OR editor, not side-by-side
            if (_activeFilePath != null) {
              return _EditorWrapper(
                vaultId: widget.vaultId,
                filePath: _activeFilePath!,
                onBack: () => setState(() => _activeFilePath = null),
              );
            }
            return _SidebarContent(
              loading: _loading,
              error: _error,
              tree: _tree,
              searchQuery: _searchQuery,
              searchResults: _searchResults,
              searchCtrl: _searchCtrl,
              activeFilePath: _activeFilePath,
              onSearch: (q) { setState(() => _searchQuery = q); _search(q); },
              onOpen: _openFile,
              onDelete: _deleteFile,
              onCreate: _createFile,
            );
          }

          // Desktop: collapsible sidebar + editor
          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: _sidebarOpen ? 280 : 0,
                child: _sidebarOpen
                    ? _SidebarContent(
                        loading: _loading,
                        error: _error,
                        tree: _tree,
                        searchQuery: _searchQuery,
                        searchResults: _searchResults,
                        searchCtrl: _searchCtrl,
                        activeFilePath: _activeFilePath,
                        onSearch: (q) { setState(() => _searchQuery = q); _search(q); },
                        onOpen: _openFile,
                        onDelete: _deleteFile,
                        onCreate: _createFile,
                      )
                    : const SizedBox.shrink(),
              ),
              if (_sidebarOpen) Container(width: 1, color: AppColors.outlineVariant),
              Expanded(
                child: _activeFilePath != null
                    ? _EditorWrapper(vaultId: widget.vaultId, filePath: _activeFilePath!)
                    : _EmptyEditor(onCreateFile: () => _createFile('')),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Editor wrapper (inline, no separate route on desktop) ─────────────────────

class _EditorWrapper extends StatefulWidget {
  const _EditorWrapper({required this.vaultId, required this.filePath, this.onBack});
  final String vaultId;
  final String filePath;
  final VoidCallback? onBack;

  @override
  State<_EditorWrapper> createState() => _EditorWrapperState();
}

class _EditorWrapperState extends State<_EditorWrapper> {
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  EditorMode _mode = EditorMode.split;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _loadFile();
  }

  @override
  void didUpdateWidget(_EditorWrapper old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) _loadFile();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    setState(() { _loading = true; _dirty = false; });
    try {
      final content = await ApiClient().getRaw(
        '/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(widget.filePath)}',
      );
      _ctrl.text = content;
    } catch (_) {
      _ctrl.text = '';
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      await ApiClient().put('/api/files/${widget.vaultId}/file', {
        'path': widget.filePath,
        'content': _ctrl.text,
      });
      setState(() { _dirty = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gespeichert'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  void _cycleMode() => setState(() {
    _mode = switch (_mode) {
      EditorMode.split   => EditorMode.edit,
      EditorMode.edit    => EditorMode.preview,
      EditorMode.preview => EditorMode.split,
    };
  });

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;
    return Column(
      children: [
        // Inline toolbar
        Container(
          height: 44,
          color: AppColors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: widget.onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: AppColors.onSurfaceVariant,
                ),
              if (widget.onBack != null) const SizedBox(width: 8),
              const Icon(Icons.description_outlined, size: 14, color: AppColors.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fileName,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_dirty)
                Container(
                  width: 6, height: 6, margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                ),
              TextButton.icon(
                onPressed: _cycleMode,
                icon: Icon(_modeIcon(_mode), size: 14, color: AppColors.primary),
                label: Text(
                  switch (_mode) {
                    EditorMode.split   => 'Split',
                    EditorMode.edit    => 'Bearbeiten',
                    EditorMode.preview => 'Lesen',
                  },
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.primary),
                ),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
              if (_mode != EditorMode.preview)
                IconButton(
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.save_outlined, size: 18),
                  onPressed: _saving ? null : _save,
                  tooltip: 'Speichern',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                  color: AppColors.onSurface,
                ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.outlineVariant),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : LayoutBuilder(builder: (ctx, c) {
                  final isWide = c.maxWidth >= 600;
                  if (!isWide || _mode == EditorMode.edit) {
                    return _EditPane(ctrl: _ctrl, onChanged: () => setState(() => _dirty = true));
                  }
                  if (_mode == EditorMode.preview) {
                    return _ReadPane(content: _ctrl.text);
                  }
                  return Row(children: [
                    Expanded(child: _EditPane(ctrl: _ctrl, onChanged: () => setState(() => _dirty = true))),
                    Container(width: 1, color: AppColors.outlineVariant),
                    Expanded(child: _ReadPane(content: _ctrl.text)),
                  ]);
                }),
        ),
      ],
    );
  }

  IconData _modeIcon(EditorMode m) => switch (m) {
    EditorMode.split   => Icons.view_column_outlined,
    EditorMode.edit    => Icons.edit_outlined,
    EditorMode.preview => Icons.chrome_reader_mode_outlined,
  };
}

class _EditPane extends StatelessWidget {
  const _EditPane({required this.ctrl, required this.onChanged});
  final TextEditingController ctrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: ctrl,
        onChanged: (_) => onChanged(),
        maxLines: null, expands: true,
        style: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.6, color: AppColors.onSurface),
        decoration: InputDecoration(
          border: InputBorder.none, focusedBorder: InputBorder.none, enabledBorder: InputBorder.none,
          filled: false,
          hintText: 'Hier schreiben…',
          hintStyle: GoogleFonts.jetBrainsMono(color: AppColors.outline),
        ),
        cursorColor: AppColors.primary,
        keyboardType: TextInputType.multiline,
      ),
    );
  }
}

class _ReadPane extends StatelessWidget {
  const _ReadPane({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ObsidianPreview(content: content),
          ),
        ),
      ),
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor({required this.onCreateFile});
  final VoidCallback onCreateFile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.edit_note, size: 48, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('Keine Datei geöffnet', style: GoogleFonts.spaceGrotesk(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text('Datei aus dem Baum wählen oder neue erstellen.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: onCreateFile, icon: const Icon(Icons.add), label: const Text('Neue Notiz')),
        ],
      ),
    );
  }
}

// ── Sidebar content (shared between mobile/desktop) ───────────────────────────

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.loading, required this.error, required this.tree,
    required this.searchQuery, required this.searchResults, required this.searchCtrl,
    required this.activeFilePath, required this.onSearch, required this.onOpen,
    required this.onDelete, required this.onCreate,
  });

  final bool loading;
  final String? error;
  final List<dynamic> tree;
  final String searchQuery;
  final List<Map<String, dynamic>> searchResults;
  final TextEditingController searchCtrl;
  final String? activeFilePath;
  final void Function(String) onSearch;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLow,
      child: Column(
        children: [
          _SearchBar(controller: searchCtrl, onSearch: onSearch),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(error!, style: GoogleFonts.inter(color: AppColors.error, fontSize: 13)),
                      )
                    : searchQuery.isNotEmpty
                        ? _SearchResults(results: searchResults, onOpen: onOpen)
                        : tree.isEmpty
                            ? _EmptyVaultHint(onCreate: () => onCreate(''))
                            : _FileTree(
                                nodes: tree,
                                activeFilePath: activeFilePath,
                                onOpen: onOpen, onDelete: onDelete, onCreate: onCreate,
                              ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSearch});
  final TextEditingController controller;
  final void Function(String) onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: controller,
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: 'Suchen…',
          prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.outline),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear, size: 14), onPressed: () { controller.clear(); onSearch(''); })
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.onOpen});
  final List<Map<String, dynamic>> results;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(child: Text('Keine Ergebnisse', style: GoogleFonts.inter(color: AppColors.outline, fontSize: 13)));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: results.map((r) => ListTile(
        dense: true,
        leading: const Icon(Icons.description_outlined, size: 14, color: AppColors.primary),
        title: Text(r['path'] as String? ?? '', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurface)),
        subtitle: r['preview'] != null
            ? Text(r['preview'] as String, style: GoogleFonts.inter(fontSize: 10, color: AppColors.outline), maxLines: 2)
            : null,
        onTap: () => onOpen(r['path'] as String),
      )).toList(),
    );
  }
}

class _EmptyVaultHint extends StatelessWidget {
  const _EmptyVaultHint({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.note_add_outlined, size: 32, color: AppColors.outline),
          const SizedBox(height: 8),
          Text('Noch keine Dateien', style: GoogleFonts.inter(fontSize: 13, color: AppColors.outline), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: onCreate, icon: const Icon(Icons.add, size: 14), label: const Text('Neue Notiz')),
        ],
      ),
    );
  }
}

// ── File Tree ─────────────────────────────────────────────────────────────────

class _FileTree extends StatelessWidget {
  const _FileTree({required this.nodes, required this.activeFilePath, required this.onOpen, required this.onDelete, required this.onCreate});
  final List<dynamic> nodes;
  final String? activeFilePath;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: nodes.map((n) => _Node(
        node: n as Map<String, dynamic>, depth: 0,
        activeFilePath: activeFilePath,
        onOpen: onOpen, onDelete: onDelete, onCreate: onCreate,
      )).toList(),
    );
  }
}

class _Node extends StatefulWidget {
  const _Node({required this.node, required this.depth, required this.activeFilePath, required this.onOpen, required this.onDelete, required this.onCreate});
  final Map<String, dynamic> node;
  final int depth;
  final String? activeFilePath;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;

  @override
  State<_Node> createState() => _NodeState();
}

class _NodeState extends State<_Node> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isFolder = node['type'] == 'folder';
    final name = node['name'] as String? ?? '';
    final path = node['path'] as String? ?? '';
    final indent = widget.depth * 12.0;
    final isActive = !isFolder && path == widget.activeFilePath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: isActive ? AppColors.primary.withAlpha(30) : Colors.transparent,
          child: InkWell(
            onTap: isFolder
                ? () => setState(() => _expanded = !_expanded)
                : () => widget.onOpen(path),
            child: Container(
              decoration: isActive
                  ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.primary, width: 2)))
                  : null,
              padding: EdgeInsets.fromLTRB(12 + indent, 5, 8, 5),
              child: Row(
                children: [
                  if (isFolder)
                    Icon(_expanded ? Icons.expand_more : Icons.chevron_right, size: 14, color: AppColors.outline)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 4),
                  Icon(
                    isFolder ? Icons.folder_outlined : Icons.description_outlined,
                    size: 14,
                    color: isFolder ? AppColors.tertiary : (isActive ? AppColors.primary : AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isActive ? AppColors.primary : AppColors.onSurface,
                        fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isFolder)
                    InkWell(
                      onTap: () => widget.onDelete(path),
                      child: const Icon(Icons.close, size: 12, color: AppColors.outline),
                    ),
                  if (isFolder)
                    InkWell(
                      onTap: () => widget.onCreate(path),
                      child: const Icon(Icons.add, size: 12, color: AppColors.outline),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (isFolder && _expanded)
          ...((node['children'] as List? ?? []).map((child) => _Node(
            node: child as Map<String, dynamic>,
            depth: widget.depth + 1,
            activeFilePath: widget.activeFilePath,
            onOpen: widget.onOpen,
            onDelete: widget.onDelete,
            onCreate: widget.onCreate,
          ))),
      ],
    );
  }
}
