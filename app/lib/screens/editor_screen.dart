import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import '../widgets/obsidian_preview.dart';

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
          const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
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
          IconButton(
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _save,
            tooltip: 'Save',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth >= 800;
                if (isWide) {
                  return Row(children: [
                    Expanded(child: _Editor(ctrl: _ctrl, onChanged: () => setState(() => _dirty = true))),
                    Container(width: 1, color: AppColors.outlineVariant),
                    Expanded(child: _Preview(content: _ctrl.text)),
                  ]);
                }
                return _MobileEditorView(ctrl: _ctrl, onChanged: () => setState(() => _dirty = true));
              },
            ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.ctrl, required this.onChanged});
  final TextEditingController ctrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: TextField(
        controller: ctrl,
        onChanged: (_) => onChanged(),
        maxLines: null,
        expands: true,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          height: 1.6,
          color: AppColors.onSurface,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          filled: false,
          hintText: 'Start writing…',
        ),
        cursorColor: AppColors.primary,
        keyboardType: TextInputType.multiline,
      ),
    );
  }
}

class _MobileEditorView extends StatefulWidget {
  const _MobileEditorView({required this.ctrl, required this.onChanged});
  final TextEditingController ctrl;
  final VoidCallback onChanged;

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
              Expanded(child: _Tab(label: 'Edit', active: !_showPreview, onTap: () => setState(() => _showPreview = false))),
              Expanded(child: _Tab(label: 'Preview', active: _showPreview, onTap: () => setState(() => _showPreview = true))),
            ],
          ),
        ),
        Expanded(
          child: _showPreview
              ? _Preview(content: widget.ctrl.text)
              : _Editor(ctrl: widget.ctrl, onChanged: widget.onChanged),
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

class _Preview extends StatelessWidget {
  const _Preview({required this.content});
  final String content;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ObsidianPreview(content: content),
      ),
    );
  }
}
