import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:markdown/markdown.dart' as md;
import '../theme/app_colors.dart';

// Renders Obsidian-compatible Markdown:
//  - YAML frontmatter display
//  - [[Wikilinks]] as styled spans
//  - Callouts  > [!note/warning/info/tip/danger/quote]
//  - #Tags as chips
//  - Syntax highlighting in code blocks
//  - Standard MD: tables, bold, italic, HR, lists, blockquotes
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
  // Converts Obsidian-specific syntax into tokens understood by _MarkdownBody.
  // Code blocks and callout body lines are passed through verbatim.

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

      // Callouts: > [!type] Title
      if (line.startsWith('> [!')) {
        final match = RegExp(r'> \[!(\w+)\]\s*(.*)').firstMatch(line);
        if (match != null) {
          final type = match.group(1)!.toLowerCase();
          final title = match.group(2)!.trim();
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
        (m) => 'WIKILINK:${m.group(1)}:${m.group(2) ?? m.group(1)}',
      );

      // Inline #Tags (skip heading lines)
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _tokenize(source),
    );
  }

  List<Widget> _tokenize(String source) {
    final widgets = <Widget>[];
    final lines = source.split('\n');
    final mdBuffer = <String>[];

    void flushMd() {
      if (mdBuffer.isEmpty) return;
      final chunk = mdBuffer.join('\n');
      mdBuffer.clear();
      // Does this chunk contain any token lines?
      if (chunk.contains('WIKILINK:') || chunk.contains('TAG:')) {
        // Render line-by-line so tokens can be handled individually,
        // but buffer consecutive non-token lines as one Markdown block
        final chunkLines = chunk.split('\n');
        final plain = <String>[];
        void flushPlain() {
          if (plain.isEmpty) return;
          widgets.add(_PureMarkdown(source: plain.join('\n')));
          plain.clear();
        }
        for (final line in chunkLines) {
          if (line.contains('WIKILINK:') || line.contains('TAG:')) {
            flushPlain();
            widgets.add(_InlineRich(line: line));
          } else {
            plain.add(line);
          }
        }
        flushPlain();
      } else {
        // No tokens — pass the whole block to flutter_markdown at once
        // This preserves multi-line structures like code blocks and blockquotes
        widgets.add(_PureMarkdown(source: chunk));
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('CALLOUT:')) {
        flushMd();
        final colonIdx = line.indexOf(':', 8);
        final type = colonIdx > 8 ? line.substring(8, colonIdx) : line.substring(8);
        final title = colonIdx > 8 ? line.substring(colonIdx + 1) : '';
        final body = <String>[];
        i++;
        while (i < lines.length && lines[i].startsWith('CALLOUTBODY:')) {
          body.add(lines[i].substring(12));
          i++;
        }
        widgets.add(_Callout(type: type, title: title, body: body.join('\n')));
        continue;
      }

      mdBuffer.add(line);
    }

    flushMd();
    return widgets;
  }
}

// ── Pure Markdown (via flutter_markdown) ─────────────────────────────────────

class _PureMarkdown extends StatelessWidget {
  const _PureMarkdown({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: source,
      styleSheet: _sheet(),
      builders: {'code': _SyntaxCodeBuilder()},
      softLineBreak: true,
      fitContent: false,
    );
  }

  MarkdownStyleSheet _sheet() {
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
      // Inline code
      code: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        color: AppColors.secondary,
        backgroundColor: AppColors.surfaceContainerHighest,
      ),
      // Code block — the builder handles actual rendering; these are fallback styles
      codeblockDecoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      codeblockPadding: const EdgeInsets.all(0), // padding handled by builder
      // Blockquote
      blockquoteDecoration: BoxDecoration(
        color: AppColors.primary.withAlpha(18),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      blockquote: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurfaceVariant, fontStyle: FontStyle.italic),
      // Tables
      tableHead: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, color: AppColors.onSurface),
      tableBody: GoogleFonts.inter(fontSize: 14, color: AppColors.onSurface),
      tableBorder: TableBorder.all(color: AppColors.outlineVariant, width: 1),
      tableColumnWidth: const FlexColumnWidth(),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // HR
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant, width: 1)),
      ),
    );
  }
}

// ── Syntax Highlighting Code Builder ─────────────────────────────────────────

class _SyntaxCodeBuilder extends MarkdownElementBuilder {
  static const _background = AppColors.surfaceContainerLowest;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final raw = element.textContent;
    // flutter_markdown sets class="language-xxx" for fenced blocks
    final langClass = element.attributes['class'] ?? '';
    final lang = langClass.startsWith('language-')
        ? langClass.substring('language-'.length)
        : null;

    if (lang == null) {
      // Inline code — render normally
      return null;
    }

    return _HighlightBlock(code: raw, language: lang);
  }
}

class _HighlightBlock extends StatelessWidget {
  const _HighlightBlock({required this.code, required this.language});
  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans(code.trimRight());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: _SyntaxCodeBuilder._background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
              ),
              child: Text(
                language,
                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.outline),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.6, color: AppColors.onSurface),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildSpans(String code) {
    try {
      final result = highlight.parse(code, language: language, autoDetection: language.isEmpty);
      return _nodesToSpans(result.nodes ?? []);
    } catch (_) {
      return [TextSpan(text: code)];
    }
  }

  List<TextSpan> _nodesToSpans(List<Node> nodes) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      if (node.value != null) {
        spans.add(TextSpan(text: node.value, style: _styleFor(node.className)));
      } else if (node.children != null) {
        spans.add(TextSpan(
          style: _styleFor(node.className),
          children: _nodesToSpans(node.children!),
        ));
      }
    }
    return spans;
  }

  TextStyle? _styleFor(String? className) {
    if (className == null) return null;
    // One Dark Pro palette (dark background compatible)
    return switch (className) {
      'keyword'             => const TextStyle(color: Color(0xFFC678DD)),
      'built_in'            => const TextStyle(color: Color(0xFF56B6C2)),
      'type'                => const TextStyle(color: Color(0xFF56B6C2)),
      'literal'             => const TextStyle(color: Color(0xFFD19A66)),
      'number'              => const TextStyle(color: Color(0xFFD19A66)),
      'string'              => const TextStyle(color: Color(0xFF98C379)),
      'subst'               => const TextStyle(color: Color(0xFFE06C75)),
      'regexp'              => const TextStyle(color: Color(0xFF98C379)),
      'comment'             => TextStyle(color: const Color(0xFF5C6370), fontStyle: FontStyle.italic),
      'doctag'              => TextStyle(color: const Color(0xFF5C6370), fontStyle: FontStyle.italic),
      'meta'                => const TextStyle(color: Color(0xFF61AFEF)),
      'meta-keyword'        => const TextStyle(color: Color(0xFFC678DD)),
      'meta-string'         => const TextStyle(color: Color(0xFF98C379)),
      'section'             => const TextStyle(color: Color(0xFF61AFEF), fontWeight: FontWeight.bold),
      'title'               => const TextStyle(color: Color(0xFF61AFEF)),
      'name'                => const TextStyle(color: Color(0xFFE06C75)),
      'property'            => const TextStyle(color: Color(0xFF61AFEF)),
      'attr'                => const TextStyle(color: Color(0xFFD19A66)),
      'attribute'           => const TextStyle(color: Color(0xFFD19A66)),
      'variable'            => const TextStyle(color: Color(0xFFE06C75)),
      'bullet'              => const TextStyle(color: Color(0xFF56B6C2)),
      'code'                => const TextStyle(color: Color(0xFF98C379)),
      'emphasis'            => TextStyle(fontStyle: FontStyle.italic),
      'strong'              => const TextStyle(fontWeight: FontWeight.bold),
      'formula'             => const TextStyle(color: Color(0xFF56B6C2)),
      'link'                => const TextStyle(color: Color(0xFF98C379), decoration: TextDecoration.underline),
      'quote'               => TextStyle(color: const Color(0xFF5C6370), fontStyle: FontStyle.italic),
      'selector-tag'        => const TextStyle(color: Color(0xFFE06C75)),
      'selector-id'         => const TextStyle(color: Color(0xFF98C379)),
      'selector-class'      => const TextStyle(color: Color(0xFFD19A66)),
      'selector-attr'       => const TextStyle(color: Color(0xFFD19A66)),
      'selector-pseudo'     => const TextStyle(color: Color(0xFF56B6C2)),
      'template-tag'        => const TextStyle(color: Color(0xFFE06C75)),
      'template-variable'   => const TextStyle(color: Color(0xFFE06C75)),
      'tag'                 => const TextStyle(color: Color(0xFFE06C75)),
      'deletion'            => const TextStyle(color: Color(0xFFE06C75)),
      'addition'            => const TextStyle(color: Color(0xFF98C379)),
      _                     => null,
    };
  }
}

// ── Inline rich text (Wikilinks + Tags) ──────────────────────────────────────

class _InlineRich extends StatelessWidget {
  const _InlineRich({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final tokenPattern = RegExp(
      r'(WIKILINK:([^:\n]+):([^\n]+?)(?=WIKILINK:|TAG:|$))|(TAG:([A-Za-z][A-Za-z0-9_/-]*))',
    );

    var last = 0;
    for (final match in tokenPattern.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: line.substring(last, match.start),
          style: GoogleFonts.inter(fontSize: 15, height: 1.7, color: AppColors.onSurface),
        ));
      }
      if (match.group(1) != null) {
        final display = match.group(3) ?? match.group(2) ?? '';
        spans.add(TextSpan(
          text: '[[$display]]',
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.primary, decoration: TextDecoration.underline),
        ));
      } else if (match.group(4) != null) {
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
    if (last < line.length) {
      spans.add(TextSpan(
        text: line.substring(last),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
        'note'             => (AppColors.primary,              Icons.info_outline),
        'info'             => (AppColors.secondary,            Icons.info_outline),
        'tip'              => (const Color(0xFF4CAF50),         Icons.lightbulb_outline),
        'warning'          => (AppColors.tertiary,             Icons.warning_amber_outlined),
        'danger' || 'caution' => (AppColors.error,            Icons.dangerous_outlined),
        'quote'            => (AppColors.outline,              Icons.format_quote),
        'success'          => (const Color(0xFF4CAF50),         Icons.check_circle_outline),
        _                  => (AppColors.primary,              Icons.sticky_note_2_outlined),
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
    final tags = raw
        .replaceAll('[', '').replaceAll(']', '')
        .split(',')
        .map((t) => t.trim().replaceAll('"', '').replaceAll("'", ''))
        .where((t) => t.isNotEmpty)
        .toList();
    return Wrap(
      spacing: 4, runSpacing: 4,
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
