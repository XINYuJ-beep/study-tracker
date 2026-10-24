import 'package:flutter/material.dart';

/// 今日页。
/// M1 阶段：最小骨架，只保证能编译能跑。
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('今日', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
