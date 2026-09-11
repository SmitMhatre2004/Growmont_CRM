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
  late final Future<List<LegalBlock>> _blocks = rootBundle
      .loadString(widget.asset)
      .then(parseLegalMarkdown);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return FutureBuilder<List<LegalBlock>>(
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
              itemBuilder: (context, i) => blocks[i].toWidget(),
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

enum LegalBlockKind { h1, h2, rule, bullet, paragraph }

class LegalBlock {
  const LegalBlock(this.kind, [this.text = '']);

  final LegalBlockKind kind;
  final String text;

  Widget toWidget() {
    switch (kind) {
      case LegalBlockKind.h1:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Text(text, style: AppTypography.pageTitle),
        );
      case LegalBlockKind.h2:
        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xl,
            bottom: AppSpacing.sm,
          ),
          child: Text(text, style: AppTypography.sectionTitle),
        );
      case LegalBlockKind.rule:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Divider(height: 1),
        );
      case LegalBlockKind.bullet:
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
      case LegalBlockKind.paragraph:
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

List<LegalBlock> parseLegalMarkdown(String source) {
  final blocks = <LegalBlock>[];
  final buffer = <String>[];
  LegalBlockKind? pending;

  void flush() {
    if (pending != null && buffer.isNotEmpty) {
      blocks.add(LegalBlock(pending!, buffer.join(' ')));
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
      blocks.add(LegalBlock(LegalBlockKind.h1, trimmed.substring(2).trim()));
    } else if (trimmed.startsWith('## ')) {
      flush();
      blocks.add(LegalBlock(LegalBlockKind.h2, trimmed.substring(3).trim()));
    } else if (trimmed == '---') {
      flush();
      blocks.add(const LegalBlock(LegalBlockKind.rule));
    } else if (trimmed.startsWith('- ')) {
      flush();
      pending = LegalBlockKind.bullet;
      buffer.add(trimmed.substring(2).trim());
    } else if (pending == LegalBlockKind.bullet && line.startsWith('  ')) {
      // Indented wrap of the bullet above.
      buffer.add(trimmed);
    } else {
      if (pending != LegalBlockKind.paragraph) flush();
      pending = LegalBlockKind.paragraph;
      buffer.add(trimmed);
    }
  }
  flush();

  return blocks;
}
