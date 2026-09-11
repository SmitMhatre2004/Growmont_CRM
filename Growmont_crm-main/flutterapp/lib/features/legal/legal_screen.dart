import 'dart:convert' show LineSplitter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme/app_theme.dart';

/// The bundled legal documents, in the order they appear as tabs.
const List<LegalDocument> kLegalDocuments = [
  LegalDocument('Privacy', 'assets/legal/privacy-policy.md'),
  LegalDocument('Terms', 'assets/legal/terms-of-service.md'),
  LegalDocument('Licence', 'assets/legal/eula.md'),
];

class LegalDocument {
  const LegalDocument(this.label, this.asset);

  final String label;
  final String asset;
}

/// Opens the legal documents over whatever is on screen. Deliberately uses the
/// root [Navigator] rather than a go_router route: these have to be reachable
/// from the login screen, and the router sends every unauthenticated location
/// back to '/'.
Future<void> showLegalDocuments(BuildContext context, {int initialTab = 0}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => LegalScreen(initialTab: initialTab),
      fullscreenDialog: true,
    ),
  );
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kLegalDocuments.length,
      initialIndex: initialTab.clamp(0, kLegalDocuments.length - 1),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('Legal'),
          bottom: TabBar(
            tabs: [
              for (final doc in kLegalDocuments) Tab(text: doc.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final doc in kLegalDocuments) _DocumentView(asset: doc.asset),
          ],
        ),
      ),
    );
  }
}

class _DocumentView extends StatefulWidget {
  const _DocumentView({required this.asset});

  final String asset;

  @override
  State<_DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<_DocumentView>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<_Block>> _blocks = rootBundle
      .loadString(widget.asset)
      .then(_parseMarkdown);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return FutureBuilder<List<_Block>>(
      future: _blocks,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load this document.'));
        }
        final blocks = snapshot.data;
        if (blocks == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView.builder(
              padding: AppLayout.pagePadding(context),
              itemCount: blocks.length,
              itemBuilder: (context, i) => blocks[i].build(context),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// A deliberately small Markdown subset - headings, rules, bullets, paragraphs
// and inline bold - covering exactly what the bundled documents use. Enough to
// keep the .md files the single source of truth without pulling in a renderer.
// ---------------------------------------------------------------------------

enum _BlockKind { h1, h2, rule, bullet, paragraph }

class _Block {
  const _Block(this.kind, [this.text = '']);

  final _BlockKind kind;
  final String text;

  Widget build(BuildContext context) {
    switch (kind) {
      case _BlockKind.h1:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Text(text, style: AppTypography.pageTitle),
        );
      case _BlockKind.h2:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xl,
            bottom: AppSpacing.sm,
          ),
          child: Text(text, style: AppTypography.sectionTitle),
        );
      case _BlockKind.rule:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Divider(height: 1),
        );
      case _BlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: AppSpacing.md),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: _richText()),
            ],
          ),
        );
      case _BlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _richText(),
        );
    }
  }

  Widget _richText() {
    const base = AppTypography.bodySecondary;
    final bold = base.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    );
    return Text.rich(
      TextSpan(style: base.copyWith(height: 1.6), children: _inline(base, bold)),
    );
  }

  List<TextSpan> _inline(TextStyle base, TextStyle bold) {
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in RegExp(r'\*\*(.+?)\*\*').allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(text: match.group(1), style: bold));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }
}

List<_Block> _parseMarkdown(String source) {
  final blocks = <_Block>[];
  final buffer = <String>[];
  _BlockKind? pending;

  void flush() {
    if (pending != null && buffer.isNotEmpty) {
      blocks.add(_Block(pending!, buffer.join(' ')));
    }
    buffer.clear();
    pending = null;
  }

  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.trimRight();
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flush();
    } else if (trimmed.startsWith('# ')) {
      flush();
      blocks.add(_Block(_BlockKind.h1, trimmed.substring(2).trim()));
    } else if (trimmed.startsWith('## ')) {
      flush();
      blocks.add(_Block(_BlockKind.h2, trimmed.substring(3).trim()));
    } else if (trimmed == '---') {
      flush();
      blocks.add(const _Block(_BlockKind.rule));
    } else if (trimmed.startsWith('- ')) {
      flush();
      pending = _BlockKind.bullet;
      buffer.add(trimmed.substring(2).trim());
    } else if (pending == _BlockKind.bullet && line.startsWith('  ')) {
      // Indented wrap of the bullet above.
      buffer.add(trimmed);
    } else {
      if (pending != _BlockKind.paragraph) flush();
      pending = _BlockKind.paragraph;
      buffer.add(trimmed);
    }
  }
  flush();

  return blocks;
}
