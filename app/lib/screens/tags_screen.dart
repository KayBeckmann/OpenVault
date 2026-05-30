import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import 'editor_screen.dart';

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key, required this.vaultId, required this.vaultName});
  final String vaultId;
  final String vaultName;

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  List<Map<String, dynamic>> _tags = [];
  bool _loading = true;
  String _filterOp = 'AND';
  final Set<String> _selectedTags = {};
  List<Map<String, dynamic>> _filteredFiles = [];
  bool _filtering = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() { _loading = true; });
    try {
      final result = await ApiClient().get('/api/files/${widget.vaultId}/tags');
      final list = result['tags'] as List? ?? [];
      setState(() { _tags = list.cast<Map<String, dynamic>>(); });
    } on ApiException catch (_) {
      setState(() { _tags = []; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _applyFilter() async {
    if (_selectedTags.isEmpty) {
      setState(() { _filteredFiles = []; _filtering = false; });
      return;
    }
    setState(() { _filtering = true; });
    try {
      final tagParam = _selectedTags.join(',');
      final results = await ApiClient().getList(
        '/api/files/${widget.vaultId}/tags/filter?tags=${Uri.encodeQueryComponent(tagParam)}&op=$_filterOp',
      );
      setState(() { _filteredFiles = results; });
    } on ApiException catch (_) {
      setState(() { _filteredFiles = []; });
    } finally {
      if (mounted) setState(() { _filtering = false; });
    }
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    _applyFilter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Tags — ${widget.vaultName}'),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadTags, tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _tags.isEmpty
              ? _EmptyTags()
              : Column(
                  children: [
                    _FilterBar(op: _filterOp, onOpChanged: (v) { setState(() => _filterOp = v); _applyFilter(); }),
                    _TagCloud(tags: _tags, selected: _selectedTags, onToggle: _toggleTag),
                    if (_selectedTags.isNotEmpty) const Divider(height: 1),
                    if (_selectedTags.isNotEmpty)
                      Expanded(child: _FileResults(
                        files: _filteredFiles,
                        loading: _filtering,
                        vaultId: widget.vaultId,
                        selectedTags: _selectedTags,
                        op: _filterOp,
                      )),
                    if (_selectedTags.isEmpty) Expanded(child: _AllTagsList(tags: _tags, onTap: _toggleTag, vaultId: widget.vaultId)),
                  ],
                ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.op, required this.onOpChanged});
  final String op;
  final void Function(String) onOpChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surfaceContainerHigh,
      child: Row(
        children: [
          Text('Filter:', style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
          const SizedBox(width: 12),
          _OpChip(label: 'AND', active: op == 'AND', onTap: () => onOpChanged('AND')),
          const SizedBox(width: 8),
          _OpChip(label: 'OR', active: op == 'OR', onTap: () => onOpChanged('OR')),
          const Spacer(),
          Text('Tap tags to filter', style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline)),
        ],
      ),
    );
  }
}

class _OpChip extends StatelessWidget {
  const _OpChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(30) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.primary : AppColors.outlineVariant),
        ),
        child: Text(label, style: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? AppColors.primary : AppColors.outline,
        )),
      ),
    );
  }
}

class _TagCloud extends StatelessWidget {
  const _TagCloud({required this.tags, required this.selected, required this.onToggle});
  final List<Map<String, dynamic>> tags;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.surfaceContainerLow,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tags.map((t) {
          final tag = t['tag'] as String;
          final count = t['count'] as int? ?? 0;
          final isSelected = selected.contains(tag);
          return InkWell(
            onTap: () => onToggle(tag),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withAlpha(40) : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('#$tag', style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isSelected ? AppColors.primary : AppColors.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  )),
                  const SizedBox(width: 4),
                  Text('$count', style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AllTagsList extends StatelessWidget {
  const _AllTagsList({required this.tags, required this.onTap, required this.vaultId});
  final List<Map<String, dynamic>> tags;
  final void Function(String) onTap;
  final String vaultId;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: tags.length,
      itemBuilder: (ctx, i) {
        final t = tags[i];
        final tag = t['tag'] as String;
        final count = t['count'] as int? ?? 0;
        final files = (t['files'] as List? ?? []).cast<String>();
        return ExpansionTile(
          leading: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text('$count', style: GoogleFonts.inter(fontSize: 11, color: AppColors.primary))),
          ),
          title: Text('#$tag', style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          children: files.map((f) => ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined, size: 14, color: AppColors.primary),
            title: Text(f, style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface)),
            onTap: () => Navigator.push(ctx, MaterialPageRoute(
              builder: (_) => EditorScreen(vaultId: vaultId, filePath: f),
            )),
          )).toList(),
        );
      },
    );
  }
}

class _FileResults extends StatelessWidget {
  const _FileResults({required this.files, required this.loading, required this.vaultId, required this.selectedTags, required this.op});
  final List<Map<String, dynamic>> files;
  final bool loading;
  final String vaultId;
  final Set<String> selectedTags;
  final String op;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (files.isEmpty) {
      return Center(child: Text(
        'No files match ${op == 'AND' ? 'all' : 'any'} of: ${selectedTags.map((t) => '#$t').join(', ')}',
        style: GoogleFonts.inter(color: AppColors.outline, fontSize: 14),
        textAlign: TextAlign.center,
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (ctx, i) {
        final f = files[i];
        final path = f['path'] as String;
        final fileTags = (f['tags'] as List? ?? []).cast<String>();
        return ListTile(
          leading: const Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
          title: Text(path, style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface)),
          subtitle: Wrap(
            spacing: 4,
            children: fileTags.map((t) => Text('#$t',
              style: GoogleFonts.inter(fontSize: 11, color: AppColors.primary))).toList(),
          ),
          onTap: () => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => EditorScreen(vaultId: vaultId, filePath: path),
          )),
        );
      },
    );
  }
}

class _EmptyTags extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.label_off_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('No tags found', style: GoogleFonts.spaceGrotesk(fontSize: 18, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text('Add #tags to your notes or in YAML frontmatter.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
