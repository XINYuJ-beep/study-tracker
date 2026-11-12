import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'concept_popup.dart';

/// ----
/// 题目自评按钮：三档（不会 / 模糊 / 会）。
/// ----
class GradeButton extends StatelessWidget {
  const GradeButton({
    super.key,
    required this.label,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String hint;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.08),
        ),
        child: Column(
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(hint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// ----
/// 选项卡片：单选/多选的统一外观，支持正确/错误/选中三态着色。
/// ----
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.correct,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool selected;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Color border = theme.colorScheme.outlineVariant;
    Color bg = Colors.transparent;
    if (correct) {
      border = theme.colorScheme.primary;
      bg = theme.colorScheme.primary.withValues(alpha: 0.08);
    } else if (wrong) {
      border = theme.colorScheme.error;
      bg = theme.colorScheme.error.withValues(alpha: 0.08);
    } else if (selected) {
      border = theme.colorScheme.primary;
      bg = theme.colorScheme.primary.withValues(alpha: 0.05);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12),
          color: bg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Text(label, style: theme.textTheme.labelSmall),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ----
/// 空态提示：图标 + 标题 + 说明 + 一个行动按钮。
/// ----
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// ----
/// 空态提示（行高放大版）：用于问答长文案空态，说明文字行高 1.6。
/// ----
class HintBlock extends StatelessWidget {
  const HintBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// ----
/// 结果块：通过/未过两种图标与配色，附带说明与下一步按钮。
/// ----
class ResultBlock extends StatelessWidget {
  const ResultBlock({
    super.key,
    required this.pass,
    required this.title,
    required this.detail,
    required this.note,
    required this.actionLabel,
    required this.onAction,
  });

  final bool pass;
  final String title;
  final String detail;
  final String note;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              pass ? Icons.verified : Icons.error_outline,
              size: 56,
              color: pass ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              note,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// ----
/// 解析框：答题后的文字解析容器。
/// ----
class ExplainBox extends StatelessWidget {
  const ExplainBox({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('解析', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Consumer(
            builder: (BuildContext ctx, WidgetRef ref, Widget? _) {
              return ConceptTappable(
                text: text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// ----
/// 题目出处展示：把 source_ref 翻译成人话标签。
///
/// 题库实际取值分布（2026-11-12 实测 4293 条）：
///   - `wNdM`（如 `w3d2`）      644 种 / 3496 条  -> 第 3 周 第 2 天
///   - `wNexam`（如 `w3exam`）  92 种 / 276 条   -> 第 3 周 周考
///   - `builtin:questions`                      -> 内置题库
///   - `outline:<file>` / `dagang:<file>`       -> 大纲 · <file>
///   - `manual`                                 -> 手动录入
///   - 空串 / null                              -> 内置题库（兜底）
///
/// 背景：`wNdM` 是 item_id 直灌进 source_ref 的结果（gen_batch 的
/// `source_ref: iid` 行为），不带冒号，旧实现走 default 分支会原样
/// 吐回 `w3d2` 这种编码，用户看不懂。本版接管该分支。
/// ----
/// 匹配 `w<周>d<天>`，天固定 1-7。
final RegExp _kItemRefPattern = RegExp(r'^w(\d{1,2})d([1-7])$');
/// 匹配 `w<周>exam` 周考卷。
final RegExp _kExamRefPattern = RegExp(r'^w(\d{1,2})exam$');

/// 把 item_id 形态的 source_ref 翻成「第 N 周 第 M 天」。
String? _itemRefLabel(String raw) {
  final RegExpMatch? itemMatch = _kItemRefPattern.firstMatch(raw);
  if (itemMatch != null) {
    final int week = int.tryParse(itemMatch.group(1) ?? '') ?? 0;
    final int day = int.tryParse(itemMatch.group(2) ?? '') ?? 0;
    if (week >= 1 && day >= 1) {
      return '第 $week 周 第 $day 天';
    }
    return null;
  }
  final RegExpMatch? examMatch = _kExamRefPattern.firstMatch(raw);
  if (examMatch != null) {
    final int week = int.tryParse(examMatch.group(1) ?? '') ?? 0;
    if (week >= 1) {
      return '第 $week 周 周考';
    }
  }
  return null;
}

String sourceRefLabel(String? ref) {
  final String raw = (ref ?? '').trim();
  if (raw.isEmpty) return '内置题库';
  final int sep = raw.indexOf(':');
  if (sep < 0) {
    if (raw == 'manual') return '手动录入';
    final String? itemLabel = _itemRefLabel(raw);
    if (itemLabel != null) return itemLabel;
    return raw;
  }
  final String type = raw.substring(0, sep);
  final String locator = raw.substring(sep + 1);
  switch (type) {
    case 'builtin':
      return '内置题库';
    case 'outline':
    case 'dagang':
      return '大纲 · $locator';
    case 'manual':
      return '手动录入';
    default:
      return '$type · $locator';
  }
}

/// 出处小标签（圆角胶囊），复用自问答页原 _SourceTag 视觉。
class SourceTag extends StatelessWidget {
  const SourceTag({super.key, required this.label});

  /// 已翻译好的展示文案；传 `sourceRef` 时会自动走 [sourceRefLabel]。
  factory SourceTag.ref(String? sourceRef) =>
      SourceTag(label: sourceRefLabel(sourceRef));

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
