import 'package:flutter/material.dart';

/// 录音页（W2 填充真实录音：波形、暂停/继续、锁屏后台）。
class RecordingPage extends StatelessWidget {
  const RecordingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('page_record'),
      appBar: AppBar(title: const Text('新录音')),
      body: const Center(child: Text('录音功能将在 W2 实现')),
    );
  }
}
