import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/db/tables.dart';

/// ----
/// 全局名词弹卡
///
/// 能力：
/// 1. 启动时把 concepts 全量 term 载入内存（368 条，量级极小），建最长匹配索引。
/// 2. 把一段文本按术语库切分，命中片段渲染为可点击 TextSpan（虚线下划线）。
/// 3. 点击后 showModalBottomSheet 弹出释义。
///
/// 兼容要求：
/// - 不改变原文本语义与换行，只切分不重排；
/// - 无命中时原样返回单个 span，页面视觉零变化；
/// - 英文术语大小写敏感（PE 不会被 pe 命中），中文按最长词优先。
/// ----

/// 全量概念缓存（一次装载，全局复用）。
final FutureProvider<List<Concept>> _allConceptsProvider =
    FutureProvider<List<Concept>>((ref) async {
  final repo = ref.watch(conceptRepoProvider);
  return repo.allConcepts();
});

/// 内存索引：按 term 长度降序，供最长匹配。
class TermIndex {
  TermIndex._(this._byLength, this._byTerm);

  final List<String> _byLength;
  final Map<String, Concept> _byTerm;

  static final TermIndex empty =
      TermIndex._(const <String>[], const <String, Concept>{});

  factory TermIndex.build(List<Concept> concepts) {
    final Map<String, Concept> byTerm = <String, Concept>{};
    for (final Concept c in concepts) {
      final String t = c.term.trim();
      if (t.isEmpty) continue;
      final Concept? old = byTerm[t];
      if (old == null || c.level < old.level) byTerm[t] = c;
    }
    final List<String> keys = byTerm.keys.toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));
    return TermIndex._(keys, byTerm);
  }

  bool get isEmpty => _byTerm.isEmpty;

  Concept? matchAt(String text, int start) {
    for (final String t in _byLength) {
      if (start + t.length > text.length) continue;
      if (text.startsWith(t, start)) return _byTerm[t];
    }
    return null;
  }
}

/// 全局索引 Provider。
final Provider<TermIndex> termIndexProvider = Provider<TermIndex>((ref) {
  final AsyncValue<List<Concept>> async = ref.watch(_allConceptsProvider);
  final List<Concept>? list = async.valueOrNull;
  if (list == null || list.isEmpty) return TermIndex.empty;
  return TermIndex.build(list);
});

/// 可点击术语文本。
class ConceptTappable extends ConsumerWidget {
  const ConceptTappable({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.enable = true,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool enable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color chipColor = isDark ? AppColors.darkPrimary : AppColors.goldText;

    if (!enable) {
      return Text(text,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign);
    }

    final TermIndex index = ref.watch(termIndexProvider);
    if (index.isEmpty) {
      return Text(text,
          style: style,
          maxLines: maxLines,
          overflow: overflow,
          textAlign: textAlign);
    }

    final List<InlineSpan> spans = <InlineSpan>[];
    final List<TapGestureRecognizer> recognizers = <TapGestureRecognizer>[];
    int i = 0;
    int plainStart = 0;

    while (i < text.length) {
      final Concept? hit = index.matchAt(text, i);
      if (hit == null) {
        i++;
        continue;
      }
      if (i > plainStart) {
        spans.add(TextSpan(text: text.substring(plainStart, i)));
      }
      final TapGestureRecognizer rec = TapGestureRecognizer()
        ..onTap = () => showConceptSheet(context, hit.term);
      recognizers.add(rec);
      spans.add(
        TextSpan(
          text: hit.term,
          style: TextStyle(
            color: chipColor,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: chipColor.withValues(alpha: 0.6),
          ),
          recognizer: rec,
        ),
      );
      i += hit.term.length;
      plainStart = i;
    }
    if (text.length > plainStart) {
      spans.add(TextSpan(text: text.substring(plainStart)));
    }

    return _RecognizerScope(
      recognizers: recognizers,
      child: Text.rich(
        TextSpan(children: spans),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}

/// 负责在 widget 销毁时释放 recognizer。
class _RecognizerScope extends StatefulWidget {
  const _RecognizerScope({required this.recognizers, required this.child});

  final List<TapGestureRecognizer> recognizers;
  final Widget child;

  @override
  State<_RecognizerScope> createState() => _RecognizerScopeState();
}

class _RecognizerScopeState extends State<_RecognizerScope> {
  List<TapGestureRecognizer> _owned = const <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _owned = widget.recognizers;
  }

  @override
  void didUpdateWidget(covariant _RecognizerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.recognizers, widget.recognizers)) {
      for (final TapGestureRecognizer r in _owned) {
        r.dispose();
      }
      _owned = widget.recognizers;
    }
  }

  @override
  void dispose() {
    for (final TapGestureRecognizer r in _owned) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 弹出术语释义卡片。
Future<void> showConceptSheet(BuildContext context, String term) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _ConceptSheet(term: term),
  );
}

class _ConceptSheet extends ConsumerStatefulWidget {
  const _ConceptSheet({required this.term});

  final String term;

  @override
  ConsumerState<_ConceptSheet> createState() => _ConceptSheetState();
}

class _ConceptSheetState extends ConsumerState<_ConceptSheet> {
  Concept? _concept;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(conceptRepoProvider);
    final List<Concept> rows = await repo.search(widget.term);
    if (!mounted) return;
    Concept? exact;
    for (final Concept c in rows) {
      if (c.term == widget.term) {
        exact = c;
        break;
      }
    }
    setState(() {
      _concept = exact ?? (rows.isNotEmpty ? rows.first : null);
      _notFound = _concept == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color bg = isDark ? AppColors.darkCard : AppColors.card;
    final Color fg = isDark ? AppColors.darkText : AppColors.text;
    final Color minor = isDark ? const Color(0xFF9AA3B0) : AppColors.textMinor;
    final Color accent = isDark ? AppColors.darkPrimary : AppColors.goldText;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSizes.gap2),
        padding: const EdgeInsets.fromLTRB(AppSizes.gap3, AppSizes.gap2,
            AppSizes.gap3, AppSizes.gap3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: minor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSizes.gap2),
            Row(
              children: <Widget>[
                Icon(Icons.menu_book_outlined, size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.term,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_concept != null && _concept!.week != null)
                  Text(
                    '第 ${_concept!.week} 周',
                    style: theme.textTheme.bodySmall?.copyWith(color: minor),
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.gap),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.gap3),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accent),
                  ),
                ),
              )
            else if (_notFound)
              Text(
                '术语库里还没有「${widget.term}」的释义。',
                style: theme.textTheme.bodyMedium?.copyWith(color: minor),
              )
            else ...<Widget>[
              Text(
                _concept!.definition,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: fg, height: 1.6),
              ),
              const SizedBox(height: AppSizes.gap2),
              Row(
                children: <Widget>[
                  _LevelChip(
                      level: _concept!.level, accent: accent, minor: minor),
                  const Spacer(),
                  Text(
                    '重复 ${_concept!.reps} 次',
                    style: theme.textTheme.bodySmall?.copyWith(color: minor),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSizes.gap2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.level,
    required this.accent,
    required this.minor,
  });

  final int level;
  final Color accent;
  final Color minor;

  @override
  Widget build(BuildContext context) {
    final List<String> names = <String>['基础', '中等', '进阶'];
    final String name =
        level >= 0 && level < names.length ? names[level] : '基础';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        name,
        style: TextStyle(fontSize: AppSizes.caption, color: accent),
      ),
    );
  }
}
