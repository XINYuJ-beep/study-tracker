import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/db/tables.dart';

/// 打卡面板的回值。
class CheckinInput {
  const CheckinInput({required this.minutes, required this.note});

  final int minutes;
  final String note;
}

/// 打卡面板：可改用时、写备注。
///
/// 弹出时默认带入预估用时，用户可改；备注选填，上限 200 字。
///
/// 从 plan_page / today_page 的私有 _CheckinSheet 抽取而来，参数与行为保持一致：
/// 步进 ±5（上限 600）、Slider 5–240 / 47 格、备注 maxLength 200、
/// viewInsetsOf 键盘避让、defaultMinutes <= 0 回退 15。
class CheckinSheet extends StatefulWidget {
  const CheckinSheet({
    super.key,
    required this.item,
    required this.defaultMinutes,
  });

  final Item item;
  final int defaultMinutes;

  @override
  State<CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends State<CheckinSheet> {
  late int _minutes;
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _minutes = widget.defaultMinutes > 0 ? widget.defaultMinutes : 15;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSizes.cardRadius),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.item.watch, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '第 ${widget.item.week} 周 · 预估 ${widget.item.minutes} 分钟',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _stepBtn(
                icon: Icons.remove,
                onTap: _minutes > 5
                    ? () => setState(() => _minutes -= 5)
                    : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$_minutes 分钟',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              _stepBtn(
                icon: Icons.add,
                onTap: _minutes < 600
                    ? () => setState(() => _minutes += 5)
                    : null,
              ),
            ],
          ),
          Slider(
            value: _minutes.toDouble().clamp(5, 240),
            min: 5,
            max: 240,
            divisions: 47,
            onChanged: (double v) => setState(() => _minutes = v.round()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLength: 200,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: '备注（选填）：今天卡在哪里，下次注意什么',
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    CheckinInput(minutes: _minutes, note: _note.text.trim()),
                  ),
                  child: const Text('完成打卡'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn({required IconData icon, VoidCallback? onTap}) {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Icon(icon),
      ),
    );
  }
}