import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import '../services/local_vault_service.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/obsidian_preview.dart';
import 'editor_screen.dart';
import 'tags_screen.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({
    super.key,
    this.vaultId,
    this.localPath,
    required this.vaultName,
    this.remoteUrl,
    this.sshKeyPath,
    this.nativeAutoPushOnClose = false,
  }) : assert(vaultId != null || localPath != null,
            'Entweder vaultId (Web) oder localPath (nativ) muss gesetzt sein.');

  final String? vaultId;
  final String? localPath;
  final String vaultName;
  final String? remoteUrl;
  final String? sshKeyPath;
  final bool nativeAutoPushOnClose;

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
  int _treeGeneration = 0;
  bool _treeDefaultExpanded = true;
  String _defaultNoteFolder = '';
  String _templateFolder = '_templates';
  bool _autoPushOnClose = false;

  @override
  void initState() {
    super.initState();
    if (widget.localPath != null) {
      _autoPushOnClose = widget.nativeAutoPushOnClose;
    }
    _loadSettings();
    _pullAndLoad();
  }

  Future<void> _pullAndLoad() async {
    if (widget.localPath != null) {
      final hasRemote = widget.remoteUrl != null && widget.remoteUrl!.isNotEmpty;
      if (hasRemote) {
        setState(() => _working = true);
        final result = await LocalVaultService.pullRepo(
          widget.localPath!,
          sshKeyPath: widget.sshKeyPath,
        );
        if (mounted) {
          setState(() => _working = false);
          if (!result.success && result.output.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Pull: ${result.output}'),
              duration: const Duration(seconds: 4),
            ));
          }
        }
      }
      await _loadTree();
      return;
    }
    try {
      await ApiClient().post('/api/vaults/${widget.vaultId}/pull', {});
    } catch (_) {}
    await _loadTree();
  }

  Future<void> _manualSync() async {
    if (widget.localPath == null) return;
    final hasRemote = widget.remoteUrl != null && widget.remoteUrl!.isNotEmpty;
    if (!hasRemote) return;
    setState(() => _working = true);
    try {
      final pullResult = await LocalVaultService.pullRepo(
        widget.localPath!,
        sshKeyPath: widget.sshKeyPath,
      );
      if (mounted && !pullResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pull fehlgeschlagen: ${pullResult.output}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ));
        setState(() => _working = false);
        return;
      }
      final now = DateTime.now();
      final ts = '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';
      final pushResult = await LocalVaultService.commitAndPushRepo(
        widget.localPath!,
        'Sync $ts (OpenVault)',
        sshKeyPath: widget.sshKeyPath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(pushResult.success ? 'Sync erfolgreich' : 'Push fehlgeschlagen: ${pushResult.output}'),
          backgroundColor: pushResult.success ? null : AppColors.error,
        ));
        await _loadTree();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sync-Fehler: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _loadSettings() async {
    if (widget.localPath != null) return;
    try {
      final s = await ApiClient().get('/api/settings/${widget.vaultId}');
      if (mounted) setState(() {
        _defaultNoteFolder = s['defaultNoteFolder'] as String? ?? '';
        _templateFolder = s['templateFolder'] as String? ?? '_templates';
        _autoPushOnClose = s['autoPushOnClose'] as bool? ?? false;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTree() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (widget.localPath != null) {
        final tree = LocalVaultService.buildTree(widget.localPath!);
        setState(() { _tree = tree; });
      } else {
        final result = await ApiClient().get('/api/files/${widget.vaultId}/tree');
        setState(() { _tree = result['children'] as List? ?? []; });
      }
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = e.toString(); });
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
      if (widget.localPath != null) {
        final results = LocalVaultService.searchFiles(widget.localPath!, query);
        setState(() { _searchResults = results; });
      } else {
        final results = await ApiClient().getList(
          '/api/files/${widget.vaultId}/search?q=${Uri.encodeQueryComponent(query)}',
        );
        setState(() { _searchResults = results; });
      }
    } catch (_) {
      setState(() { _searchResults = []; });
    }
  }

  Future<void> _createFile(String parentPath) async {
    final effectiveParent = parentPath.isEmpty ? _defaultNoteFolder : parentPath;
    final result = await showDialog<({String path, String content})>(
      context: context,
      builder: (ctx) => _NewFileDialog(
        vaultId: widget.vaultId,
        localPath: widget.localPath,
        effectiveParent: effectiveParent,
        templateFolder: _templateFolder,
      ),
    );
    if (result == null) return;
    if (widget.localPath != null) {
      LocalVaultService.writeFile(widget.localPath!, result.path, result.content);
    } else {
      await ApiClient().put('/api/files/${widget.vaultId}/file', {
        'path': result.path,
        'content': result.content,
      });
    }
    await _loadTree();
    _openFile(result.path);
  }

  Future<void> _closeVault() async {
    if (widget.localPath != null) {
      final hasRemote = widget.remoteUrl != null && widget.remoteUrl!.isNotEmpty;
      if (_autoPushOnClose && hasRemote) {
        setState(() => _working = true);
        try {
          final now = DateTime.now();
          final ts = '${now.year}-'
              '${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')} '
              '${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')}';
          final result = await LocalVaultService.commitAndPushRepo(
            widget.localPath!,
            'Auto-commit $ts (OpenVault)',
            sshKeyPath: widget.sshKeyPath,
          );
          if (mounted && !result.success) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Push fehlgeschlagen: ${result.output}'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ));
          }
        } catch (_) {} finally {
          if (mounted) setState(() => _working = false);
        }
      }
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (_autoPushOnClose) {
      setState(() { _working = true; });
      try {
        final now = DateTime.now();
        final ts = '${now.year}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';
        await ApiClient().post('/api/vaults/${widget.vaultId}/push', {
          'commitMessage': 'Auto-commit $ts (OpenVault)',
        });
      } catch (_) {} finally {
        if (mounted) setState(() { _working = false; });
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  bool _working = false;

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
    if (widget.localPath != null) {
      LocalVaultService.deleteFile(widget.localPath!, path);
    } else {
      await ApiClient().delete('/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(path)}');
    }
    if (_activeFilePath == path) setState(() => _activeFilePath = null);
    await _loadTree();
  }

  Future<void> _renameFile(String path, String newName) async {
    try {
      if (widget.localPath != null) {
        LocalVaultService.renameFile(widget.localPath!, path, newName);
      } else {
        await ApiClient().post('/api/files/${widget.vaultId}/rename', {'path': path, 'newName': newName});
      }
      if (_activeFilePath == path) {
        final parent = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        setState(() => _activeFilePath = parent.isEmpty ? newName : '$parent/$newName');
      }
      await _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _moveFile(String path, String destFolder) async {
    try {
      if (widget.localPath != null) {
        LocalVaultService.moveFile(widget.localPath!, path, destFolder);
      } else {
        await ApiClient().post('/api/files/${widget.vaultId}/move', {'path': path, 'destFolder': destFolder});
      }
      if (_activeFilePath == path) {
        final name = path.split('/').last;
        setState(() => _activeFilePath = destFolder.isEmpty ? name : '$destFolder/$name');
      }
      await _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  void _openFile(String path) {
    setState(() => _activeFilePath = path);
  }

  void _resolveAndOpenWikilink(String target) {
    final path = _resolveWikilink(target, _activeFilePath);
    if (path != null) { _openFile(path); }
  }

  // Resolve a wikilink target to a vault-relative file path.
  //
  // Rules (Obsidian-compatible):
  //  1. If the target contains '/' it is treated as a path — match the
  //     file whose path ends with that suffix (case-insensitive, .md optional).
  //  2. Otherwise collect every file whose stem (filename without .md) matches
  //     the target.  If exactly one match exists, return it.  If several exist,
  //     return the one whose directory is closest to [currentFilePath].
  String? _resolveWikilink(String target, String? currentFilePath) {
    final t = target.toLowerCase().replaceAll('.md', '');

    if (t.contains('/')) {
      // Path-based link — find a file whose path ends with the given suffix.
      final all = _collectAllFiles(_tree);
      for (final p in all) {
        final norm = p.toLowerCase().replaceAll('.md', '');
        if (norm == t || norm.endsWith('/$t')) return p;
      }
      return null;
    }

    // Bare filename — collect all matches, then pick the closest.
    final matches = _collectAllFiles(_tree).where((p) {
      final stem = p.split('/').last.toLowerCase().replaceAll('.md', '');
      return stem == t;
    }).toList();

    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;

    // Multiple matches — prefer the file whose directory is closest to the
    // directory of the currently open file.
    final currentDir = currentFilePath != null && currentFilePath.contains('/')
        ? currentFilePath.substring(0, currentFilePath.lastIndexOf('/'))
        : '';

    matches.sort((a, b) {
      final aDir = a.contains('/') ? a.substring(0, a.lastIndexOf('/')) : '';
      final bDir = b.contains('/') ? b.substring(0, b.lastIndexOf('/')) : '';
      return _proximity(bDir, currentDir).compareTo(_proximity(aDir, currentDir));
    });

    return matches.first;
  }

  // Returns a closeness score: higher = closer to [base].
  static int _proximity(String candidate, String base) {
    if (candidate == base) return 1000;
    if (base.startsWith('$candidate/')) return 500; // candidate is ancestor
    if (candidate.startsWith('$base/')) return 400; // candidate is descendant
    // Count shared leading path segments.
    final bp = base.split('/');
    final cp = candidate.split('/');
    var shared = 0;
    for (var i = 0; i < bp.length && i < cp.length; i++) {
      if (bp[i] == cp[i]) shared++;
      else break;
    }
    return shared;
  }

  List<String> _collectAllFiles(List nodes) {
    final result = <String>[];
    for (final n in nodes) {
      if (n['type'] == 'file') {
        result.add(n['path'] as String);
      } else if (n['type'] == 'folder') {
        result.addAll(_collectAllFiles(n['children'] as List? ?? []));
      }
    }
    return result;
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
          if (widget.vaultId != null)
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: 'Tags',
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => TagsScreen(vaultId: widget.vaultId!, vaultName: widget.vaultName),
              )),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTree, tooltip: 'Aktualisieren'),
          if (widget.localPath != null && widget.remoteUrl != null)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Jetzt synchronisieren',
              onPressed: _working ? null : _manualSync,
            ),
          IconButton(
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : Icon(_autoPushOnClose ? Icons.cloud_done_outlined : Icons.close, color: AppColors.onSurface),
            tooltip: _autoPushOnClose ? 'Vault schließen & pushen' : 'Vault schließen',
            onPressed: _working ? null : _closeVault,
          ),
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
                localPath: widget.localPath,
                filePath: _activeFilePath!,
                onBack: () => setState(() => _activeFilePath = null),
                onWikilink: _resolveAndOpenWikilink,
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
              treeGeneration: _treeGeneration,
              treeDefaultExpanded: _treeDefaultExpanded,
              onSearch: (q) { setState(() => _searchQuery = q); _search(q); },
              onOpen: _openFile,
              onDelete: _deleteFile,
              onCreate: _createFile,
              onRename: widget.localPath != null ? _renameFile : null,
              onMove: widget.localPath != null ? _moveFile : null,
              onCollapseAll: () => setState(() { _treeGeneration++; _treeDefaultExpanded = false; }),
              onExpandAll: () => setState(() { _treeGeneration++; _treeDefaultExpanded = true; }),
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
                        treeGeneration: _treeGeneration,
                        treeDefaultExpanded: _treeDefaultExpanded,
                        onSearch: (q) { setState(() => _searchQuery = q); _search(q); },
                        onOpen: _openFile,
                        onDelete: _deleteFile,
                        onCreate: _createFile,
                        onCollapseAll: () => setState(() { _treeGeneration++; _treeDefaultExpanded = false; }),
                        onExpandAll: () => setState(() { _treeGeneration++; _treeDefaultExpanded = true; }),
                      )
                    : const SizedBox.shrink(),
              ),
              if (_sidebarOpen) Container(width: 1, color: AppColors.outlineVariant),
              Expanded(
                child: _activeFilePath != null
                    ? _EditorWrapper(
                        vaultId: widget.vaultId,
                        localPath: widget.localPath,
                        filePath: _activeFilePath!,
                        onWikilink: _resolveAndOpenWikilink,
                      )
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
  const _EditorWrapper({required this.vaultId, this.localPath, required this.filePath, this.onBack, this.onWikilink});
  final String? vaultId;
  final String? localPath;
  final String filePath;
  final VoidCallback? onBack;
  final void Function(String)? onWikilink;

  @override
  State<_EditorWrapper> createState() => _EditorWrapperState();
}

class _EditorWrapperState extends State<_EditorWrapper> {
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  EditorMode _mode = EditorMode.split;
  bool _syncScroll = false;
  bool _syncing = false;

  late TextEditingController _ctrl;
  final _editorScroll  = ScrollController();
  final _previewScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _loadFile();
    _editorScroll.addListener(_onEditorScroll);
    _previewScroll.addListener(_onPreviewScroll);
  }

  @override
  void didUpdateWidget(_EditorWrapper old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) _loadFile();
  }

  @override
  void dispose() {
    _editorScroll.removeListener(_onEditorScroll);
    _previewScroll.removeListener(_onPreviewScroll);
    _editorScroll.dispose();
    _previewScroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onEditorScroll() => _sync(_editorScroll, _previewScroll);
  void _onPreviewScroll() => _sync(_previewScroll, _editorScroll);

  void _sync(ScrollController source, ScrollController target) {
    if (!_syncScroll || _syncing) return;
    if (!source.hasClients || !target.hasClients) return;
    final srcMax = source.position.maxScrollExtent;
    final tgtMax = target.position.maxScrollExtent;
    if (srcMax <= 0 || tgtMax <= 0) return;
    _syncing = true;
    target.jumpTo((source.offset / srcMax) * tgtMax);
    _syncing = false;
  }

  Future<void> _loadFile() async {
    setState(() { _loading = true; _dirty = false; });
    try {
      if (widget.localPath != null) {
        _ctrl.text = LocalVaultService.readFile(widget.localPath!, widget.filePath);
      } else {
        _ctrl.text = await ApiClient().getRaw(
          '/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(widget.filePath)}',
        );
      }
    } catch (_) {
      _ctrl.text = '';
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      if (widget.localPath != null) {
        LocalVaultService.writeFile(widget.localPath!, widget.filePath, _ctrl.text);
      } else {
        await ApiClient().put('/api/files/${widget.vaultId}/file', {
          'path': widget.filePath,
          'content': _ctrl.text,
        });
      }
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

  void _toggleCheckboxInCtrl(int idx, bool checked) {
    final text = _ctrl.text;
    final matches = RegExp(r'\[[ xX]\]', caseSensitive: false).allMatches(text).toList();
    if (idx >= matches.length) return;
    final m = matches[idx];
    final newText = text.replaceRange(m.start, m.end, checked ? '[x]' : '[ ]');
    _ctrl.value = TextEditingValue(text: newText, selection: _ctrl.selection);
    setState(() => _dirty = true);
    // Auto-save after toggling a checkbox
    _save();
  }

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
              _ModeButtons(current: _mode, onSelect: (m) => setState(() => _mode = m)),
              if (_mode == EditorMode.split)
                Tooltip(
                  message: _syncScroll ? 'Scroll-Kopplung aktiv' : 'Scroll-Kopplung inaktiv',
                  child: InkWell(
                    onTap: () => setState(() => _syncScroll = !_syncScroll),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Icon(
                        Icons.swap_vert,
                        size: 16,
                        color: _syncScroll ? AppColors.primary : AppColors.outline,
                      ),
                    ),
                  ),
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
                  final editPane = _EditPaneWithToolbar(
                    ctrl: _ctrl,
                    vaultId: widget.vaultId,
                    localPath: widget.localPath,
                    scrollController: _editorScroll,
                    onChanged: () => setState(() => _dirty = true),
                  );
                  if (_mode == EditorMode.edit) return editPane;
                  if (_mode == EditorMode.preview) return _ReadPane(
                    content: _ctrl.text,
                    onToggleCheckbox: (i, v) => _toggleCheckboxInCtrl(i, v),
                    onWikilink: widget.onWikilink,
                  );
                  // Split: show side-by-side on wide screens, editor-only on narrow
                  if (!isWide) return editPane;
                  return Row(children: [
                    Expanded(child: editPane),
                    Container(width: 1, color: AppColors.outlineVariant),
                    Expanded(child: _ReadPane(
                      content: _ctrl.text,
                      scrollController: _previewScroll,
                      onToggleCheckbox: (i, v) => _toggleCheckboxInCtrl(i, v),
                      onWikilink: widget.onWikilink,
                    )),
                  ]);
                }),
        ),
      ],
    );
  }

}

// ── Mode buttons (all three always visible) ───────────────────────────────────

class _ModeButtons extends StatelessWidget {
  const _ModeButtons({required this.current, required this.onSelect});
  final EditorMode current;
  final void Function(EditorMode) onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeBtn(
          icon: Icons.view_column_outlined,
          label: 'Split',
          active: current == EditorMode.split,
          onTap: () => onSelect(EditorMode.split),
        ),
        _ModeBtn(
          icon: Icons.edit_outlined,
          label: 'Bearbeiten',
          active: current == EditorMode.edit,
          onTap: () => onSelect(EditorMode.edit),
        ),
        _ModeBtn(
          icon: Icons.chrome_reader_mode_outlined,
          label: 'Lesen',
          active: current == EditorMode.preview,
          onTap: () => onSelect(EditorMode.preview),
        ),
      ],
    );
  }
}

class _ModeBtn extends StatelessWidget {
  const _ModeBtn({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: active
              ? BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primary.withAlpha(80)),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: active ? AppColors.primary : AppColors.outline),
              const SizedBox(width: 3),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: active ? AppColors.primary : AppColors.outline,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPaneWithToolbar extends StatelessWidget {
  const _EditPaneWithToolbar({required this.ctrl, this.vaultId, this.localPath, required this.onChanged, this.scrollController});
  final TextEditingController ctrl;
  final String? vaultId;
  final String? localPath;
  final VoidCallback onChanged;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditorToolbar(ctrl: ctrl, vaultId: vaultId, localPath: localPath, onChanged: onChanged),
        Container(height: 1, color: AppColors.outlineVariant),
        Expanded(child: _EditPane(ctrl: ctrl, onChanged: onChanged, scrollController: scrollController)),
      ],
    );
  }
}

class _EditPane extends StatefulWidget {
  const _EditPane({required this.ctrl, required this.onChanged, this.scrollController});
  final TextEditingController ctrl;
  final VoidCallback onChanged;
  final ScrollController? scrollController;

  @override
  State<_EditPane> createState() => _EditPaneState();
}

class _EditPaneState extends State<_EditPane> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: widget.ctrl,
        scrollController: widget.scrollController,
        onChanged: _handleChange,
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

  void _handleChange(String newText) {
    widget.onChanged();
    _continueListIfNeeded(newText);
  }

  void _continueListIfNeeded(String newText) {
    final sel = widget.ctrl.selection;
    if (!sel.isCollapsed || sel.start < 1) return;
    final pos = sel.start;
    // Detect freshly inserted newline
    if (pos < 1 || newText[pos - 1] != '\n') return;

    final lineStart = newText.lastIndexOf('\n', pos - 2) + 1;
    final prevLine = newText.substring(lineStart, pos - 1);
    final prefix = _listPrefix(prevLine);
    if (prefix == null) return;

    // Empty list item → exit list (remove prefix from prev line)
    if (prevLine.trim() == prefix.trim()) {
      final fixed = newText.replaceRange(lineStart, pos - 1, '');
      widget.ctrl.value = TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(offset: lineStart),
      );
      return;
    }

    // Insert prefix on new line
    final fixed = newText.substring(0, pos) + prefix + newText.substring(pos);
    widget.ctrl.value = TextEditingValue(
      text: fixed,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
  }

  /// Returns the list prefix to continue, or null if line is not a list item.
  String? _listPrefix(String line) {
    // Checkbox: - [ ] or - [x]  (must check before plain bullet)
    final cbMatch = RegExp(r'^(\s*)-\s+\[[ xX]\]\s+').firstMatch(line);
    if (cbMatch != null) {
      return '${RegExp(r'^\s*').firstMatch(line)!.group(0)!}- [ ] ';
    }
    // Numbered list: 1. 2. etc.
    final numMatch = RegExp(r'^(\s*)(\d+)\.\s+').firstMatch(line);
    if (numMatch != null) {
      final n = int.parse(numMatch.group(2)!);
      return '${numMatch.group(1)!}${n + 1}. ';
    }
    // Bullet list: - * +
    final bulletMatch = RegExp(r'^(\s*)([-*+])\s+').firstMatch(line);
    if (bulletMatch != null) {
      return '${bulletMatch.group(1)!}${bulletMatch.group(2)!} ';
    }
    // Blockquote
    if (line.startsWith('> ')) return '> ';
    return null;
  }
}

class _ReadPane extends StatelessWidget {
  const _ReadPane({required this.content, this.onToggleCheckbox, this.onWikilink, this.scrollController});
  final String content;
  final void Function(int, bool)? onToggleCheckbox;
  final void Function(String)? onWikilink;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ObsidianPreview(
              content: content,
              onToggleCheckbox: onToggleCheckbox,
              onWikilink: onWikilink,
            ),
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
    required this.activeFilePath, required this.treeGeneration, required this.treeDefaultExpanded,
    required this.onSearch, required this.onOpen, required this.onDelete, required this.onCreate,
    required this.onCollapseAll, required this.onExpandAll,
    this.onRename, this.onMove,
  });

  final bool loading;
  final String? error;
  final List<dynamic> tree;
  final String searchQuery;
  final List<Map<String, dynamic>> searchResults;
  final TextEditingController searchCtrl;
  final String? activeFilePath;
  final int treeGeneration;
  final bool treeDefaultExpanded;
  final void Function(String) onSearch;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;
  final VoidCallback onCollapseAll;
  final VoidCallback onExpandAll;
  final Future<void> Function(String, String)? onRename;
  final Future<void> Function(String, String)? onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLow,
      child: Column(
        children: [
          _SearchBar(controller: searchCtrl, onSearch: onSearch),
          // Collapse / expand toolbar (only when tree is visible)
          if (!loading && error == null && searchQuery.isEmpty && tree.isNotEmpty)
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
              ),
              child: Row(
                children: [
                  Text('Ordner', style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline)),
                  const Spacer(),
                  _TreeToolButton(
                    icon: Icons.unfold_less,
                    tooltip: 'Alle einklappen',
                    onTap: onCollapseAll,
                  ),
                  const SizedBox(width: 4),
                  _TreeToolButton(
                    icon: Icons.unfold_more,
                    tooltip: 'Alle ausklappen',
                    onTap: onExpandAll,
                  ),
                ],
              ),
            ),
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
                                key: ValueKey(treeGeneration),
                                nodes: tree,
                                defaultExpanded: treeDefaultExpanded,
                                activeFilePath: activeFilePath,
                                onOpen: onOpen, onDelete: onDelete, onCreate: onCreate,
                                onRename: onRename, onMove: onMove,
                              ),
          ),
        ],
      ),
    );
  }
}

class _TreeToolButton extends StatelessWidget {
  const _TreeToolButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: AppColors.outline),
        ),
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
  const _FileTree({super.key, required this.nodes, required this.defaultExpanded, required this.activeFilePath, required this.onOpen, required this.onDelete, required this.onCreate, this.onRename, this.onMove});
  final List<dynamic> nodes;
  final bool defaultExpanded;
  final String? activeFilePath;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;
  final Future<void> Function(String, String)? onRename;
  final Future<void> Function(String, String)? onMove;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: nodes.map((n) => _Node(
        node: n as Map<String, dynamic>, depth: 0,
        defaultExpanded: defaultExpanded,
        activeFilePath: activeFilePath,
        onOpen: onOpen, onDelete: onDelete, onCreate: onCreate,
        onRename: onRename, onMove: onMove,
      )).toList(),
    );
  }
}

class _Node extends StatefulWidget {
  const _Node({required this.node, required this.depth, required this.defaultExpanded, required this.activeFilePath, required this.onOpen, required this.onDelete, required this.onCreate, this.onRename, this.onMove});
  final Map<String, dynamic> node;
  final int depth;
  final bool defaultExpanded;
  final String? activeFilePath;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;
  final Future<void> Function(String, String)? onRename;
  final Future<void> Function(String, String)? onMove;

  @override
  State<_Node> createState() => _NodeState();
}

class _NodeState extends State<_Node> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultExpanded;
  }

  void _showContextMenu(BuildContext context, String path, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, color: AppColors.primary),
              title: Text('Umbenennen', style: GoogleFonts.inter(color: AppColors.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _renameDialog(context, path, name);
              },
            ),
            if (widget.onMove != null)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline, color: AppColors.primary),
                title: Text('Verschieben', style: GoogleFonts.inter(color: AppColors.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _moveDialog(context, path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text('Löschen', style: GoogleFonts.inter(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                widget.onDelete(path);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDialog(BuildContext context, String path, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Umbenennen', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(color: AppColors.onSurface),
          decoration: const InputDecoration(labelText: 'Neuer Name', labelStyle: TextStyle(color: AppColors.outline)),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Umbenennen')),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      widget.onRename?.call(path, newName);
    }
  }

  Future<void> _moveDialog(BuildContext context, String path) async {
    final ctrl = TextEditingController();
    final destFolder = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Verschieben nach', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(color: AppColors.onSurface),
          decoration: const InputDecoration(
            labelText: 'Zielordner (leer = Root)',
            labelStyle: TextStyle(color: AppColors.outline),
            hintText: 'z.B. Ordner/Unterordner',
            hintStyle: TextStyle(color: AppColors.outline),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Verschieben')),
        ],
      ),
    );
    ctrl.dispose();
    if (destFolder != null) {
      widget.onMove?.call(path, destFolder);
    }
  }

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
            onLongPress: isFolder ? null : () => _showContextMenu(context, path, name),
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
            defaultExpanded: widget.defaultExpanded,
            activeFilePath: widget.activeFilePath,
            onOpen: widget.onOpen,
            onDelete: widget.onDelete,
            onCreate: widget.onCreate,
            onRename: widget.onRename,
            onMove: widget.onMove,
          ))),
      ],
    );
  }
}

// ── New File Dialog with template selection ───────────────────────────────────

class _NewFileDialog extends StatefulWidget {
  const _NewFileDialog({
    this.vaultId,
    this.localPath,
    required this.effectiveParent,
    required this.templateFolder,
  });

  final String? vaultId;
  final String? localPath;
  final String effectiveParent;
  final String templateFolder;

  @override
  State<_NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends State<_NewFileDialog> {
  final _nameCtrl = TextEditingController(text: 'neue-notiz.md');
  List<_Template> _templates = [];
  _Template? _selected; // null = leere Notiz
  bool _loadingTemplates = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      List children;
      if (widget.localPath != null) {
        children = LocalVaultService.buildTree(widget.localPath!);
      } else {
        final result = await ApiClient().get('/api/files/${widget.vaultId}/tree');
        children = result['children'] as List? ?? [];
      }
      final templates = <_Template>[];
      _collectTemplates(children, widget.templateFolder, templates);
      setState(() { _templates = templates; _loadingTemplates = false; });
    } catch (_) {
      setState(() => _loadingTemplates = false);
    }
  }

  void _collectTemplates(List nodes, String folderPath, List<_Template> out) {
    for (final n in nodes) {
      final path = n['path'] as String? ?? '';
      final type = n['type'] as String? ?? '';
      if (type == 'folder') {
        if (path == folderPath || path.startsWith('$folderPath/')) {
          _collectTemplates(n['children'] as List? ?? [], folderPath, out);
        } else {
          _collectTemplates(n['children'] as List? ?? [], folderPath, out);
        }
      } else if (type == 'file' &&
          (path.startsWith('$folderPath/') || path.startsWith('${folderPath}\\')) &&
          path.endsWith('.md')) {
        final name = path.split('/').last.replaceAll('.md', '');
        out.add(_Template(name: name, path: path));
      }
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final filePath = widget.effectiveParent.isEmpty
        ? name
        : '${widget.effectiveParent}/$name';

    String content = '';
    if (_selected != null) {
      try {
        if (widget.localPath != null) {
          content = LocalVaultService.readFile(widget.localPath!, _selected!.path);
        } else {
          content = await ApiClient().getRaw(
            '/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(_selected!.path)}',
          );
        }
      } catch (_) {
        content = '';
      }
    }

    if (mounted) {
      Navigator.pop(context, (path: filePath, content: content));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Neue Notiz',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filename
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Dateiname',
                      helperText: widget.effectiveParent.isEmpty
                          ? 'Wird im Vault-Wurzelverzeichnis gespeichert'
                          : 'Ordner: ${widget.effectiveParent}/',
                      helperStyle: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.outline),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Template label
                  Text(
                    'Vorlage',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Template list
                  if (_loadingTemplates)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                    )
                  else
                    _TemplateGrid(
                      templates: _templates,
                      selected: _selected,
                      onSelect: (t) => setState(() => _selected = t),
                    ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.outlineVariant),

            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(_selected == null ? 'Leere Notiz' : 'Mit Vorlage erstellen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Template {
  const _Template({required this.name, required this.path});
  final String name;
  final String path;
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.templates, required this.selected, required this.onSelect});
  final List<_Template> templates;
  final _Template? selected;
  final void Function(_Template?) onSelect;

  @override
  Widget build(BuildContext context) {
    // Always show "Leere Notiz" as first option
    final items = <Widget>[
      _TemplateChip(
        label: 'Leere Notiz',
        icon: Icons.note_add_outlined,
        isSelected: selected == null,
        onTap: () => onSelect(null),
      ),
      ...templates.map((t) => _TemplateChip(
        label: t.name,
        icon: Icons.description_outlined,
        isSelected: selected?.path == t.path,
        onTap: () => onSelect(t),
      )),
    ];

    if (templates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: AppColors.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Keine Vorlagen im Ordner "_templates" gefunden. '
                'Erstelle dort .md-Dateien, um sie hier zu sehen.',
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.outline, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({required this.label, required this.icon, required this.isSelected, required this.onTap});
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withAlpha(30) : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primary : AppColors.outline),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isSelected ? AppColors.primary : AppColors.onSurface,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
