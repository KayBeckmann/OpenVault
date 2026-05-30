import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/obsidian_preview.dart';

enum EditorMode { split, edit, preview }

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.vaultId, required this.filePath});

  final String vaultId;
  final String filePath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    setState(() { _loading = true; });
    try {
      final resp = await ApiClient().getRaw(
        '/api/files/${widget.vaultId}/file?path=${Uri.encodeQueryComponent(widget.filePath)}',
      );
      _ctrl.text = resp;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Text(fileName),
            if (_dirty) ...[
              const SizedBox(width: 8),
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        backgroundColor: AppColors.surfaceContainerLow,
        actions: [
          _EditorModeButtons(current: _mode, onSelect: (m) => setState(() => _mode = m)),
          const SizedBox(width: 4),
          if (_mode != EditorMode.preview)
            IconButton(
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                  : const Icon(Icons.save_outlined),
              onPressed: _saving ? null : _save,
              tooltip: 'Speichern (Ctrl+S)',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth >= 700;
                if (!isWide) {
                  return _MobileEditorView(
                    ctrl: _ctrl,
                    vaultId: widget.vaultId,
                    onChanged: () => setState(() => _dirty = true),
                  );
                }
                return switch (_mode) {
                  EditorMode.split => Row(children: [
                      Expanded(child: _EditorPane(ctrl: _ctrl, vaultId: widget.filePath.isEmpty ? '' : widget.vaultId, onChanged: () => setState(() => _dirty = true))),
                      Container(width: 1, color: AppColors.outlineVariant),
                      Expanded(child: _PreviewPane(content: _ctrl.text)),
                    ]),
                  EditorMode.edit => _EditorPane(ctrl: _ctrl, vaultId: widget.filePath.isEmpty ? '' : widget.vaultId, onChanged: () => setState(() => _dirty = true)),
                  EditorMode.preview => _PreviewPane(content: _ctrl.text),
                };
              },
            ),
    );
  }

}

// ── Editor pane ───────────────────────────────────────────────────────────────

class _EditorPane extends StatefulWidget {
  const _EditorPane({required this.ctrl, required this.onChanged, required this.vaultId});
  final TextEditingController ctrl;
  final VoidCallback onChanged;
  final String vaultId;

  @override
  State<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<_EditorPane> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditorToolbar(ctrl: widget.ctrl, vaultId: widget.vaultId, onChanged: widget.onChanged),
        Container(height: 1, color: AppColors.outlineVariant),
        Expanded(
          child: Container(
            color: AppColors.background,
            padding: const EdgeInsets.all(24),
            child: TextField(
              controller: widget.ctrl,
              onChanged: _handleChange,
              maxLines: null,
              expands: true,
              style: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.6, color: AppColors.onSurface),
              decoration: InputDecoration(
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                filled: false,
                hintText: 'Hier schreiben…',
                hintStyle: GoogleFonts.jetBrainsMono(color: AppColors.outline),
              ),
              cursorColor: AppColors.primary,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ),
      ],
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
    if (pos < 1 || newText[pos - 1] != '\n') return;

    final lineStart = newText.lastIndexOf('\n', pos - 2) + 1;
    final prevLine = newText.substring(lineStart, pos - 1);
    final prefix = _listPrefix(prevLine);
    if (prefix == null) return;

    if (prevLine.trim() == prefix.trim()) {
      final fixed = newText.replaceRange(lineStart, pos - 1, '');
      widget.ctrl.value = TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(offset: lineStart),
      );
      return;
    }

    final fixed = newText.substring(0, pos) + prefix + newText.substring(pos);
    widget.ctrl.value = TextEditingValue(
      text: fixed,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
  }

  String? _listPrefix(String line) {
    final cbMatch = RegExp(r'^(\s*)-\s+\[[ xX]\]\s+').firstMatch(line);
    if (cbMatch != null) return '${RegExp(r'^\s*').firstMatch(line)!.group(0)!}- [ ] ';
    final numMatch = RegExp(r'^(\s*)(\d+)\.\s+').firstMatch(line);
    if (numMatch != null) return '${numMatch.group(1)!}${int.parse(numMatch.group(2)!) + 1}. ';
    final bulletMatch = RegExp(r'^(\s*)([-*+])\s+').firstMatch(line);
    if (bulletMatch != null) return '${bulletMatch.group(1)!}${bulletMatch.group(2)!} ';
    if (line.startsWith('> ')) return '> ';
    return null;
  }
}

// ── Preview pane ──────────────────────────────────────────────────────────────

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.content});
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

// ── Mobile: Tab-Toggle ────────────────────────────────────────────────────────

class _MobileEditorView extends StatefulWidget {
  const _MobileEditorView({required this.ctrl, required this.onChanged, required this.vaultId});
  final TextEditingController ctrl;
  final VoidCallback onChanged;
  final String vaultId;

  @override
  State<_MobileEditorView> createState() => _MobileEditorViewState();
}

class _MobileEditorViewState extends State<_MobileEditorView> {
  bool _showPreview = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surfaceContainerHigh,
          child: Row(
            children: [
              Expanded(child: _Tab(label: 'Bearbeiten', active: !_showPreview, onTap: () => setState(() => _showPreview = false))),
              Expanded(child: _Tab(label: 'Vorschau', active: _showPreview, onTap: () => setState(() => _showPreview = true))),
            ],
          ),
        ),
        Expanded(
          child: _showPreview
              ? _PreviewPane(content: widget.ctrl.text)
              : _EditorPane(ctrl: widget.ctrl, vaultId: widget.vaultId, onChanged: widget.onChanged),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: active
            ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.primary, width: 2)))
            : null,
        child: Center(
          child: Text(label, style: GoogleFonts.spaceGrotesk(
            fontSize: 13, fontWeight: FontWeight.w500,
            color: active ? AppColors.primary : AppColors.outline,
          )),
        ),
      ),
    );
  }
}

// ── Mode buttons for standalone EditorScreen ─────────────────────────────────

class _EditorModeButtons extends StatelessWidget {
  const _EditorModeButtons({required this.current, required this.onSelect});
  final EditorMode current;
  final void Function(EditorMode) onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: EditorMode.values.map((m) {
        final active = m == current;
        final (icon, label) = switch (m) {
          EditorMode.split   => (Icons.view_column_outlined, 'Split'),
          EditorMode.edit    => (Icons.edit_outlined, 'Bearbeiten'),
          EditorMode.preview => (Icons.chrome_reader_mode_outlined, 'Lesen'),
        };
        return Tooltip(
          message: label,
          child: InkWell(
            onTap: () => onSelect(m),
            borderRadius: BorderRadius.circular(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              margin: const EdgeInsets.only(left: 2),
              decoration: active
                  ? BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.primary.withAlpha(80)),
                    )
                  : null,
              child: Icon(icon, size: 16, color: active ? AppColors.primary : AppColors.outline),
            ),
          ),
        );
      }).toList(),
    );
  }
}
