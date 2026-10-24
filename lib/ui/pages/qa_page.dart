import 'package:flutter/material.dart';

/// 问签页。
/// M1 阶段：最小骨架，只保证能编译能跑。
class QaPage extends StatelessWidget {
  const QaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('问答', style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
