/// 复习流程的完整组件集（自评 / 验证题 / 错因归因）。
///
/// 为何单独成文件：
///   日考核（day_exam_page）只需要轻量四档自评；
///   到期复习（qa_page 的复习区）要走完整流程：自评 → 验证 → 错因。
///   两处需求不同，但组件相同，所以抽到这里共用。
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/repo/question_repo.dart';

/// 缺口③：答错后的错因归因卡。四个标签 + 跳过。
///
/// 设计口径（方案 A）：错因只记录，不参与 SM-2 排程。
/// 它的价值在统计页——告诉你薄弱的是理解、记忆还是推理，
/// 然后你自己去调学习方法，而不是让算法替你猜。
class FailReasonCard extends StatelessWidget {
  const FailReasonCard({required this.onPick, required this.onSkip});

  final Future<void> Function(int reason) onPick;
  final Future<void> Function() onSkip;

  static const List<MapEntry<int, String>> _reasons = <MapEntry<int, String>>[
    MapEntry<int, String>(1, '看不懂题'),
    MapEntry<int, String>(2, '知识点没记住'),
    MapEntry<int, String>(3, '记混了'),
    MapEntry<int, String>(4, '想陷了'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text('错在哪？', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => onSkip(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  '跳过',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '选一个最接近的。选了会记下来，统计页会告诉你反复死在哪儿。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry<int, String> r in _reasons)
                ReasonChip(
                  label: r.value,
                  onTap: () => onPick(r.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReasonChip extends StatelessWidget {
  const ReasonChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 缺口²：答对后的「用自己的话讲一遍」自评卡。
///
/// 设计口径（方案 A）：
///   - 不自评就不放行，逼你真的讲一遍；
///   - 三档结果直接接 SM-2，不调任何 AI；
///   - 输入框内容不作判定，只当作你自己讲一遍的载体（不入库）。
/// 验证题：自评说「讲得清」之后抽一道同周题验一验。
///
/// 只用来修正上一题的自评档位，不进错题本、不写自己的复习排程。
/// 题不够（同周只有这一道）时不会出现，直接按未验证处理。
class VerifyCard extends StatelessWidget {
  const VerifyCard({
    required this.mcq,
    required this.picked,
    required this.onPick,
    required this.onSubmit,
  });

  final McqQuestion mcq;
  final int picked;
  final void Function(int index) onPick;
  final Future<void> Function()? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.verified_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text('验一下：同周的题', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '你说你讲清了。那同类题应该也能做对。做不对就把刚才的档位降一级——这不是惩罚，是校准。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            mcq.question,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < mcq.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: VerifyOption(
                label: String.fromCharCode(65 + i),
                text: mcq.options[i],
                selected: picked == i,
                onTap: () => onPick(i),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSubmit == null ? null : () => onSubmit!(),
              child: const Text('提交验证'),
            ),
          ),
        ],
      ),
    );
  }
}

class VerifyOption extends StatelessWidget {
  const VerifyOption({
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: <Widget>[
            Text(
              '$label.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? theme.colorScheme.primary : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SelfRatingCard extends StatelessWidget {
  const SelfRatingCard({required this.controller, required this.onRate});

  final TextEditingController controller;
  final Future<void> Function(int score) onRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.record_voice_over_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text('用自己的话讲一遍', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '选对了不等于真懂了。用自己的话把这道题的道理讲出来，再给自己定罪。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            decoration: InputDecoration(
              hintText: '例如：这题考的是 …，因为 …，所以选 …',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '讲得怎么样？',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RateButton(
                  label: '讲清了',
                  sub: '一步不卡 · 验证后推进',
                  color: const Color(0xFF34C759),
                  onTap: () => onRate(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RateButton(
                  label: '要停一下',
                  sub: '中间断了 · 升幅八折',
                  color: const Color(0xFF4D6BFE),
                  onTap: () => onRate(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RateButton(
                  label: '绕过去了',
                  sub: '关键点没说 · 升幅五折',
                  color: const Color(0xFFFF9500),
                  onTap: () => onRate(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RateButton(
                  label: '讲不出来',
                  sub: '降档重来',
                  color: const Color(0xFFFF3B30),
                  onTap: () => onRate(1),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            '选「讲清了」或「要停一下」会抽一道同周题验证，验的是你对自己判断准不准。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class RateButton extends StatelessWidget {
  const RateButton({
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}