import 'package:flutter/material.dart';

/// 计划页。
/// M1 阶段：最小骨架，只保证能编译能跑。
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('计划', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
