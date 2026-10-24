import 'package:flutter/material.dart';

/// 设置页。
/// M1 阶段：最小骨架，只保证能编译能跑。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('设置', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
