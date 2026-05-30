import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.ctrl,
    required this.vaultId,
    required this.onChanged,
  });

  final TextEditingController ctrl;
  final String vaultId;
  final VoidCallback onChanged;

  // ── Text manipulation helpers ─────────────────────────────────────────────

  void _wrap(String before, String after, {String placeholder = 'Text'}) {
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final text = ctrl.text;
    final selected = sel.textInside(text);
    final insert = selected.isEmpty ? '$before$placeholder$after' : '$before$selected$after';
    final newText = text.replaceRange(sel.start, sel.end, insert);
    final cursor = selected.isEmpty
        ? TextSelection(
            baseOffset: sel.start + before.length,
            extentOffset: sel.start + before.length + placeholder.length,
          )
        : TextSelection.collapsed(offset: sel.start + insert.length);
    ctrl.value = TextEditingValue(text: newText, selection: cursor);
    onChanged();
  }

  void _prefixLine(String prefix, {String placeholder = ''}) {
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final lineStart = _lineStart(text, sel.start);
    final currentLine = text.substring(lineStart);
    if (currentLine.startsWith(prefix)) {
      final newText = text.replaceRange(lineStart, lineStart + prefix.length, '');
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: (sel.start - prefix.length).clamp(lineStart, newText.length),
        ),
      );
    } else {
      final insert = placeholder.isNotEmpty && text.substring(lineStart).trim().isEmpty
          ? '$prefix$placeholder'
          : prefix;
      final newText = text.replaceRange(lineStart, lineStart, insert);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + insert.length),
      );
    }
    onChanged();
  }

  void _insertAtCursor(String snippet, {int? cursorOffset}) {
    final sel = ctrl.selection;
    final pos = sel.isValid ? sel.start : ctrl.text.length;
    final newText = ctrl.text.replaceRange(pos, sel.isValid ? sel.end : pos, snippet);
    final cursor = cursorOffset != null ? pos + cursorOffset : pos + snippet.length;
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, newText.length)),
    );
    onChanged();
  }

  void _indent() {
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final lineStart = _lineStart(text, sel.start);
    final newText = text.replaceRange(lineStart, lineStart, '  ');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + 2),
    );
    onChanged();
  }

  void _unindent() {
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final lineStart = _lineStart(text, sel.start);
    final line = text.substring(lineStart);
    final remove = line.startsWith('  ') ? 2 : line.startsWith(' ') ? 1 : 0;
    if (remove == 0) return;
    final newText = text.replaceRange(lineStart, lineStart + remove, '');
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: (sel.start - remove).clamp(lineStart, newText.length)),
    );
    onChanged();
  }

  int _lineStart(String text, int pos) {
    if (pos <= 0) return 0;
    final idx = text.lastIndexOf('\n', pos - 1);
    return idx < 0 ? 0 : idx + 1;
  }

  // ── Link dialog ───────────────────────────────────────────────────────────

  Future<void> _showLinkDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _LinkDialog(vaultId: vaultId),
    );
    if (result != null) _insertAtCursor(result);
  }

  Future<void> _showWikilinkDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _WikilinkDialog(vaultId: vaultId),
    );
    if (result != null) _insertAtCursor(result);
  }

  Future<void> _showCalloutDialog(BuildContext context) async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => _CalloutDialog(),
    );
    if (type != null) {
      _insertAtCursor(
        '> [!$type] Titel\n> Inhalt hier\n',
        cursorOffset: '> [!$type] '.length,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppColors.surfaceContainerHigh,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            // Überschriften
            _HeadingMenu(onSelect: (level) => _prefixLine('${'#' * level} ', placeholder: 'Überschrift')),
            _sep(),

            // Inline-Formatierung
            _Btn(icon: Icons.format_bold, tooltip: 'Fett', onTap: () => _wrap('**', '**', placeholder: 'fett')),
            _Btn(icon: Icons.format_italic, tooltip: 'Kursiv', onTap: () => _wrap('*', '*', placeholder: 'kursiv')),
            _Btn(icon: Icons.format_strikethrough, tooltip: 'Durchgestrichen', onTap: () => _wrap('~~', '~~', placeholder: 'Text')),
            _Btn(icon: Icons.code, tooltip: 'Inline-Code', onTap: () => _wrap('`', '`', placeholder: 'code')),
            _sep(),

            // Listen
            _Btn(icon: Icons.format_list_bulleted, tooltip: 'Aufzählung', onTap: () => _prefixLine('- ', placeholder: 'Listenpunkt')),
            _Btn(icon: Icons.format_list_numbered, tooltip: 'Nummeriert', onTap: () => _prefixLine('1. ', placeholder: 'Listenpunkt')),
            _Btn(icon: Icons.check_box_outlined, tooltip: 'Checkbox', onTap: () => _prefixLine('- [ ] ', placeholder: 'Aufgabe')),
            _sep(),

            // Blöcke
            _Btn(icon: Icons.format_quote, tooltip: 'Blockquote', onTap: () => _prefixLine('> ', placeholder: 'Zitat')),
            _Btn(
              icon: Icons.data_object,
              tooltip: 'Codeblock',
              onTap: () => _insertAtCursor('```\nCode hier\n```\n', cursorOffset: 4),
            ),
            _Btn(
              icon: Icons.horizontal_rule,
              tooltip: 'Horizontale Linie',
              onTap: () {
                final pos = ctrl.selection.isValid ? ctrl.selection.start : ctrl.text.length;
                final needsNewline = pos > 0 && ctrl.text[pos - 1] != '\n';
                _insertAtCursor('${needsNewline ? '\n' : ''}---\n');
              },
            ),
            _sep(),

            // Einrückung
            _Btn(icon: Icons.format_indent_decrease, tooltip: 'Ausrücken', onTap: _unindent),
            _Btn(icon: Icons.format_indent_increase, tooltip: 'Einrücken', onTap: _indent),
            _sep(),

            // Tabelle
            _Btn(
              icon: Icons.table_chart_outlined,
              tooltip: 'Tabelle einfügen',
              onTap: () => _insertAtCursor(
                '| Spalte 1 | Spalte 2 | Spalte 3 |\n'
                '| --- | --- | --- |\n'
                '| Zelle | Zelle | Zelle |\n',
                cursorOffset: 2,
              ),
            ),
            _sep(),

            // Links
            _Btn(
              icon: Icons.link,
              tooltip: 'Markdown-Link',
              onTap: () => _showLinkDialog(context),
            ),
            _Btn(
              label: '[[]]',
              tooltip: 'Wikilink (Vault-Datei)',
              onTap: () => _showWikilinkDialog(context),
            ),
            _sep(),

            // Callout
            _Btn(
              icon: Icons.tips_and_updates_outlined,
              tooltip: 'Callout (Obsidian)',
              onTap: () => _showCalloutDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sep() => Container(
        width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.outlineVariant,
      );
}

// ── Toolbar Buttons ───────────────────────────────────────────────────────────

class _Btn extends StatelessWidget {
  const _Btn({this.icon, this.label, required this.tooltip, required this.onTap});
  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 32, height: 40,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 17, color: AppColors.onSurfaceVariant)
                : Text(label!, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }
}

class _HeadingMenu extends StatelessWidget {
  const _HeadingMenu({required this.onSelect});
  final void Function(int level) onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Überschrift',
      color: AppColors.surfaceContainerHigh,
      offset: const Offset(0, 40),
      onSelected: onSelect,
      itemBuilder: (_) => [
        for (final level in [1, 2, 3, 4])
          PopupMenuItem<int>(
            value: level,
            child: Text(
              '${'#' * level}  H$level',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20 - (level * 2.0),
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('H', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}

// ── Link Dialog ───────────────────────────────────────────────────────────────

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.vaultId});
  final String vaultId;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _textCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text('Link einfügen', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _textCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Anzeigetext'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(labelText: 'URL (https://...)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: () {
            final text = _textCtrl.text.trim();
            final url = _urlCtrl.text.trim();
            if (url.isEmpty) return;
            Navigator.pop(context, '[${text.isEmpty ? url : text}]($url)');
          },
          child: const Text('Einfügen'),
        ),
      ],
    );
  }
}

// ── Wikilink Dialog ───────────────────────────────────────────────────────────

class _WikilinkDialog extends StatefulWidget {
  const _WikilinkDialog({required this.vaultId});
  final String vaultId;

  @override
  State<_WikilinkDialog> createState() => _WikilinkDialogState();
}

class _WikilinkDialogState extends State<_WikilinkDialog> {
  final _searchCtrl = TextEditingController();
  List<String> _allFiles = [];
  List<String> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_filter);
    _loadFiles();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_filter);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    try {
      final result = await ApiClient().get('/api/files/${widget.vaultId}/tree');
      final files = <String>[];
      _collectFiles(result['children'] as List? ?? [], files);
      setState(() {
        _allFiles = files..sort();
        _filtered = List.of(files);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _collectFiles(List nodes, List<String> out) {
    for (final n in nodes) {
      if (n['type'] == 'file') {
        out.add(n['path'] as String);
      } else if (n['type'] == 'folder') {
        _collectFiles(n['children'] as List? ?? [], out);
      }
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.of(_allFiles)
          : _allFiles.where((f) => f.toLowerCase().contains(q)).toList();
    });
  }

  String _toWikilink(String path) {
    // Strip .md extension and path separators for clean Wikilink
    final name = path.split('/').last;
    final display = name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
    return '[[$display]]';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Wikilink einfügen', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Datei suchen…',
                  prefixIcon: Icon(Icons.search, size: 16, color: AppColors.outline),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _filtered.isEmpty
                      ? Center(child: Text('Keine Dateien gefunden', style: GoogleFonts.inter(color: AppColors.outline)))
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final path = _filtered[i];
                            final name = path.split('/').last.replaceAll('.md', '');
                            final dir = path.contains('/') ? path.split('/').reversed.skip(1).toList().reversed.join('/') : '';
                            return InkWell(
                              onTap: () => Navigator.pop(context, _toWikilink(path)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    const Icon(Icons.description_outlined, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurface)),
                                          if (dir.isNotEmpty)
                                            Text(dir, style: GoogleFonts.inter(fontSize: 11, color: AppColors.outline)),
                                        ],
                                      ),
                                    ),
                                    Text('[[]]', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.outline)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Callout Dialog ────────────────────────────────────────────────────────────

class _CalloutDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final types = <(String, IconData, String)>[
      ('note',    Icons.info_outline,           'Note'),
      ('tip',     Icons.lightbulb_outline,       'Tip'),
      ('warning', Icons.warning_amber_outlined,  'Warning'),
      ('danger',  Icons.dangerous_outlined,      'Danger'),
      ('info',    Icons.help_outline,            'Info'),
      ('quote',   Icons.format_quote,            'Quote'),
      ('success', Icons.check_circle_outline,    'Success'),
      ('example', Icons.list_alt_outlined,       'Example'),
    ];

    final items = <Widget>[];
    for (final t in types) {
      final type = t.$1;
      final icon = t.$2;
      final label = t.$3;
      items.add(SimpleDialogOption(
        onPressed: () => Navigator.pop(context, type),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface)),
            const SizedBox(width: 8),
            Text('[!$type]', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppColors.outline)),
          ],
        ),
      ));
    }

    return SimpleDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text('Callout-Typ', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface)),
      children: items,
    );
  }
}
