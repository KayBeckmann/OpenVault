import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
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
      setState(() { _searchResults = [];  });
      return;
    }
    
    try {
      final results = await ApiClient().getList('/api/files/${widget.vaultId}/search?q=${Uri.encodeQueryComponent(query)}');
      setState(() { _searchResults = results; });
    } on ApiException catch (_) {
      setState(() { _searchResults = []; });
    } finally {
      if (mounted) setState(() {  });
    }
  }

  Future<void> _createFile(String parentPath) async {
    final ctrl = TextEditingController(text: 'new-note.md');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('New File', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Filename')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              final path = parentPath.isEmpty ? name : '$parentPath/$name';
              Navigator.pop(ctx);
              await ApiClient().put('/api/files/${widget.vaultId}/file', {'path': path, 'content': ''});
              await _loadTree();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFile(String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        title: Text('Delete file?', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
        content: Text('Delete "$path"? This cannot be undone.',
            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorContainer),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.spaceGrotesk(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiClient().delete('/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(path)}');
    await _loadTree();
  }

  void _openFile(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(vaultId: widget.vaultId, filePath: path),
      ),
    ).then((_) => _loadTree());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.vaultName),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _createFile(''), tooltip: 'New file'),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Tags',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => TagsScreen(vaultId: widget.vaultId, vaultName: widget.vaultName),
            )),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTree, tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchCtrl,
            onSearch: (q) { setState(() { _searchQuery = q; }); _search(q); },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _ErrorView(error: _error!)
                    : _searchQuery.isNotEmpty
                        ? _SearchResults(results: _searchResults, onOpen: _openFile)
                        : _tree.isEmpty
                            ? _EmptyVault(onCreate: () => _createFile(''))
                            : _FileTree(nodes: _tree, onOpen: _openFile, onDelete: _deleteFile, onCreate: _createFile),
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
      color: AppColors.surfaceContainerLow,
      child: TextField(
        controller: controller,
        onChanged: onSearch,
        decoration: InputDecoration(
          hintText: 'Search notes…',
          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.outline),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () { controller.clear(); onSearch(''); },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      return Center(child: Text('No results', style: GoogleFonts.inter(color: AppColors.outline)));
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: results.map((r) => ListTile(
        dense: true,
        leading: const Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
        title: Text(r['path'] as String? ?? '', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface)),
        subtitle: Text(r['preview'] as String? ?? '', style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline), maxLines: 2),
        onTap: () => onOpen(r['path'] as String),
      )).toList(),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.note_add_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('Empty vault', style: GoogleFonts.spaceGrotesk(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text('Create your first note to get started.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('New Note')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(error, style: GoogleFonts.inter(color: AppColors.error)),
  );
}

class _FileTree extends StatelessWidget {
  const _FileTree({required this.nodes, required this.onOpen, required this.onDelete, required this.onCreate});
  final List<dynamic> nodes;
  final void Function(String) onOpen;
  final Future<void> Function(String) onDelete;
  final Future<void> Function(String) onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: nodes.map((n) => _Node(node: n as Map<String, dynamic>, depth: 0, onOpen: onOpen, onDelete: onDelete, onCreate: onCreate)).toList(),
    );
  }
}

class _Node extends StatefulWidget {
  const _Node({required this.node, required this.depth, required this.onOpen, required this.onDelete, required this.onCreate});
  final Map<String, dynamic> node;
  final int depth;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: isFolder ? () => setState(() => _expanded = !_expanded) : () => widget.onOpen(path),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 + indent, 4, 8, 4),
            child: Row(
              children: [
                if (isFolder)
                  Icon(_expanded ? Icons.expand_more : Icons.chevron_right, size: 16, color: AppColors.outline)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 4),
                Icon(
                  isFolder ? Icons.folder_outlined : Icons.description_outlined,
                  size: 15,
                  color: isFolder ? AppColors.tertiary : AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(name,
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface),
                    overflow: TextOverflow.ellipsis)),
                if (!isFolder)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 13, color: AppColors.outline),
                    onPressed: () => widget.onDelete(path),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (isFolder)
                  IconButton(
                    icon: const Icon(Icons.add, size: 13, color: AppColors.outline),
                    onPressed: () => widget.onCreate(path),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'New file here',
                  ),
              ],
            ),
          ),
        ),
        if (isFolder && _expanded)
          ...((node['children'] as List? ?? []).map((child) => _Node(
            node: child as Map<String, dynamic>,
            depth: widget.depth + 1,
            onOpen: widget.onOpen,
            onDelete: widget.onDelete,
            onCreate: widget.onCreate,
          ))),
      ],
    );
  }
}
