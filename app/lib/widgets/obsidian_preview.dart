import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

// Renders Obsidian-compatible Markdown with:
//  - YAML frontmatter display
//  - [[Wikilinks]] rendered as styled spans
//  - Callouts > [!note/warning/info/tip/danger]
//  - #Tags highlighted inline
//  - Code blocks with JetBrains Mono
//  - Tables, bold, italic, strikethrough
//  - Standard headings, lists, blockquotes, hr
class ObsidianPreview extends StatelessWidget {
  const ObsidianPreview({super.key, required this.content, this.onWikilink});

  final String content;
  final void Function(String target)? onWikilink;

  @override
  Widget build(BuildContext context) {
    final frontmatter = _parseFrontmatter(content);
    final body = frontmatter != null ? _stripFrontmatter(content) : content;
    final preprocessed = _preprocess(body);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (frontmatter != null) _FrontmatterCard(data: frontmatter),
        _MarkdownBody(source: preprocessed, onWikilink: onWikilink),
      ],
    );
  }

  // ── Frontmatter ───────────────────────────────────────────────────────────

  Map<String, String>? _parseFrontmatter(String text) {
    if (!text.startsWith('---')) return null;
    final end = text.indexOf('\n---', 3);
    if (end < 0) return null;
    final yaml = text.substring(4, end).trim();
    final result = <String, String>{};
    for (final line in yaml.split('\n')) {
      final colon = line.indexOf(':');
      if (colon < 0) {
        continue;
      }
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }
    return result.isEmpty ? null : result;
  }

  String _stripFrontmatter(String text) {
    if (!text.startsWith('---')) return text;
    final end = text.indexOf('\n---', 3);
    if (end < 0) return text;
    return text.substring(end + 4).trimLeft();
  }

  // ── Preprocessing ─────────────────────────────────────────────────────────
  // Transforms Obsidian-specific syntax into standard Markdown that
  // flutter_markdown can render, using placeholder tokens for custom widgets.

  String _preprocess(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    var inCodeBlock = false;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];

      if (line.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        out.add(line);
        continue;
      }

      if (inCodeBlock) {
        out.add(line);
        continue;
      }

      // Callouts: > [!note] Title
      if (line.startsWith('> [!')) {
        final match = RegExp(r'> \[!(\w+)\]\s*(.*)').firstMatch(line);
        if (match != null) {
          final type = match.group(1)!.toLowerCase();
          final title = match.group(2)!.trim();
          // Collect continuation lines
          final body = <String>[];
          while (i + 1 < lines.length && lines[i + 1].startsWith('> ')) {
            i++;
            body.add(lines[i].substring(2));
          }
          out.add('CALLOUT:$type:${title.isEmpty ? type.toUpperCase() : title}');
          for (final b in body) {
            out.add('CALLOUTBODY:$b');
          }
          out.add('CALLOUTEND');
          continue;
        }
      }

      // [[Wikilinks]]
      line = line.replaceAllMapped(
        RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
        (m) {
          final target = m.group(1)!;
          final display = m.group(2) ?? target;
          return 'WIKILINK:$target:$display';
        },
      );

      // #Tags (not inside code spans, not headings)
      if (!line.startsWith('#')) {
        line = line.replaceAllMapped(
          RegExp(r'(?<!\w)#([A-Za-z][A-Za-z0-9_/-]*)'),
          (m) => 'TAG:${m.group(1)}',
        );
      }

      out.add(line);
    }

    return out.join('\n');
  }
}

// ── Markdown Body ─────────────────────────────────────────────────────────────

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.source, this.onWikilink});
  final String source;
  final void Function(String)? onWikilink;

  @override
  Widget build(BuildContext context) {
    // Split on custom tokens and render segments
    final segments = _tokenize(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments,
    );
  }

  List<Widget> _tokenize(String source) {
    final widgets = <Widget>[];
    final lines = source.split('\n');
    final mdBuffer = <String>[];

    void flushMd() {
      if (mdBuffer.isEmpty) return;
      widgets.add(_MdSegment(source: mdBuffer.join('\n')));
      mdBuffer.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('CALLOUT:')) {
        flushMd();
        final parts = line.substring(8).split(':');
        final type = parts[0];
        final title = parts.sublist(1).join(':');
        final body = <String>[];
        i++;
        while (i < lines.length && lines[i].startsWith('CALLOUTBODY:')) {
          body.add(lines[i].substring(12));
          i++;
        }
        // skip CALLOUTEND
        widgets.add(_Callout(type: type, title: title, body: body.join('\n')));
        continue;
      }

      mdBuffer.add(line);
    }

    flushMd();
    return widgets;
  }
}

class _MdSegment extends StatelessWidget {
  const _MdSegment({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    // Replace WIKILINK and TAG tokens with visual spans via RichText
    final lines = source.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      if (line.contains('WIKILINK:') || line.contains('TAG:')) {
        widgets.add(_InlineRich(line: line));
      } else {
        // Pure markdown — hand to flutter_markdown
        if (line.trim().isNotEmpty) {
          widgets.add(_PureMarkdown(source: line));
        } else {
          widgets.add(const SizedBox(height: 8));
        }
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}

class _PureMarkdown extends StatelessWidget {
  const _PureMarkdown({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: source,
      styleSheet: _buildStyleSheet(),
      softLineBreak: true,
    );
  }

  MarkdownStyleSheet _buildStyleSheet() {
    return MarkdownStyleSheet(
      h1: GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.3),
      h2: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.3),
      h3: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.3),
      h4: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onSurface),
      p: GoogleFonts.inter(fontSize: 15, height: 1.7, color: AppColors.onSurface),
      strong: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
      em: GoogleFonts.inter(fontSize: 15, fontStyle: FontStyle.italic, color: AppColors.onSurface),
      del: GoogleFonts.inter(fontSize: 15, color: AppColors.outline, decoration: TextDecoration.lineThrough),
      listBullet: GoogleFonts.inter(fontSize: 15, color: AppColors.primary),
      code: GoogleFonts.jetBrainsMono(fontSize: 13, color: AppColors.secondary, backgroundColor: AppColors.surfaceContainerHighest),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      blockquotePadding: const EdgeInsets.only(left: 12),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
        color: Colors.transparent,
      ),
      blockquote: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurfaceVariant, fontStyle: FontStyle.italic),
      tableHead: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, color: AppColors.onSurface),
      tableBody: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface),
      tableBorder: TableBorder.all(color: AppColors.outlineVariant, width: 1),
      tableHeadAlign: TextAlign.left,
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant, width: 1)),
      ),
    );
  }
}

// Renders a line containing WIKILINK: and TAG: tokens as RichText
class _InlineRich extends StatelessWidget {
  const _InlineRich({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var remaining = line;

    final tokenPattern = RegExp(r'(WIKILINK:([^:]+):([^W\n]+?)(?=WIKILINK:|TAG:|$))|(TAG:([A-Za-z][A-Za-z0-9_/-]*)(?=\s|WIKILINK:|TAG:|$))');

    var last = 0;
    for (final match in tokenPattern.allMatches(remaining)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: remaining.substring(last, match.start),
          style: GoogleFonts.inter(fontSize: 15, height: 1.7, color: AppColors.onSurface),
        ));
      }

      if (match.group(1) != null) {
        // Wikilink
        final display = match.group(3) ?? match.group(2) ?? '';
        spans.add(TextSpan(
          text: '[[$display]]',
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.primary, decoration: TextDecoration.underline),
        ));
      } else if (match.group(4) != null) {
        // Tag
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withAlpha(80),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withAlpha(100)),
            ),
            child: Text(
              '#${match.group(5)}',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.primary),
            ),
          ),
        ));
      }

      last = match.end;
    }

    if (last < remaining.length) {
      spans.add(TextSpan(
        text: remaining.substring(last),
        style: GoogleFonts.inter(fontSize: 15, height: 1.7, color: AppColors.onSurface),
      ));
    }

    if (spans.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(text: TextSpan(children: spans)),
    );
  }
}

// ── Callout ───────────────────────────────────────────────────────────────────

class _Callout extends StatelessWidget {
  const _Callout({required this.type, required this.title, required this.body});
  final String type;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _style(type);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
          if (body.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: MarkdownBody(
                data: body,
                styleSheet: MarkdownStyleSheet(
                  p: GoogleFonts.inter(fontSize: 14, height: 1.6, color: AppColors.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }

  (Color, IconData) _style(String type) => switch (type) {
        'note'    => (AppColors.primary,   Icons.info_outline),
        'info'    => (AppColors.secondary, Icons.info_outline),
        'tip'     => (const Color(0xFF4CAF50), Icons.lightbulb_outline),
        'warning' => (AppColors.tertiary,  Icons.warning_amber_outlined),
        'danger'  || 'caution' => (AppColors.error, Icons.dangerous_outlined),
        'quote'   => (AppColors.outline,   Icons.format_quote),
        _         => (AppColors.primary,   Icons.sticky_note_2_outlined),
      };
}

// ── Frontmatter Card ──────────────────────────────────────────────────────────

class _FrontmatterCard extends StatefulWidget {
  const _FrontmatterCard({required this.data});
  final Map<String, String> data;

  @override
  State<_FrontmatterCard> createState() => _FrontmatterCardState();
}

class _FrontmatterCardState extends State<_FrontmatterCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.data_object, size: 14, color: AppColors.outline),
                  const SizedBox(width: 6),
                  Text('Frontmatter', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.outline)),
                  const Spacer(),
                  // Show tags inline always
                  if (widget.data.containsKey('tags') && !_expanded)
                    _TagChips(widget.data['tags']!),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: AppColors.outline),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.data.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(e.key, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppColors.outline)),
                      ),
                      Expanded(
                        child: e.key == 'tags'
                            ? _TagChips(e.value)
                            : Text(e.value, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurface)),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagChips extends StatelessWidget {
  const _TagChips(this.raw);
  final String raw;

  @override
  Widget build(BuildContext context) {
    final tags = raw.replaceAll('[', '').replaceAll(']', '').split(',').map((t) => t.trim().replaceAll('"', "").replaceAll("'", '')).where((t) => t.isNotEmpty).toList();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tags.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withAlpha(100)),
        ),
        child: Text('#$t', style: GoogleFonts.inter(fontSize: 11, color: AppColors.primary)),
      )).toList(),
    );
  }
}
