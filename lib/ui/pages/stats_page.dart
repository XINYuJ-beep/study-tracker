import 'package:flutter/material.dart';

/// 统计页。
/// M1 阶段：最小骨架，只保证能编译能跑。
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('统计', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
