import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../mock_interview_service.dart';

enum _FeedbackPhase { none, streaming, done, error }

/// 模拟面试会话页（PLAN W3-M3）：逐题文字作答 → AI 流式逐题反馈 →
/// 完成后落库（interview + 分段 + 卡片）并跳面试详情统一管理。
///
/// 中途返回有进度时先确认（用户的时间不白费）；反馈中断保留已收内容，
/// 随会话一起落库。
class MockSessionPage extends ConsumerStatefulWidget {
  const MockSessionPage({super.key, required this.plan});

  final MockSessionPlan plan;

  @override
  ConsumerState<MockSessionPage> createState() => _MockSessionPageState();
}

class _MockSessionPageState extends ConsumerState<MockSessionPage> {
  int _index = 0;
  final _answerController = TextEditingController();
  _FeedbackPhase _phase = _FeedbackPhase.none;
  final StringBuffer _feedbackBuffer = StringBuffer();
  final List<MockQa> _qas = [];
  bool _persisting = false;

  bool get _last => _index == widget.plan.questions.length - 1;

  bool get _hasProgress =>
      _qas.isNotEmpty ||
      _answerController.text.isNotEmpty ||
      _phase != _FeedbackPhase.none;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _confirmAbandon() async {
    final abandon = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('mock_abandon_dialog'),
        title: const Text('放弃本次模拟面试？'),
        content: const Text('已作答的内容不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续作答'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃退出'),
          ),
        ],
      ),
    );
    return abandon == true;
  }

  Future<void> _submit() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      _toast('先写下你的回答，或跳过此题');
      return;
    }
    setState(() {
      _phase = _FeedbackPhase.streaming;
      _feedbackBuffer.clear();
    });
    final events = ref.read(mockInterviewServiceProvider).generateFeedback(
          question: widget.plan.questions[_index],
          answer: answer,
          position: widget.plan.position,
          resume: widget.plan.resume,
        );
    await for (final event in events) {
      if (!mounted) return;
      switch (event) {
        case MockFeedbackDelta(:final text):
          setState(() => _feedbackBuffer.write(text));
        case MockFeedbackDone(:final full):
          // 以服务端全文为准（中断重连等场景缓冲可能与最终全文不一致）
          setState(() {
            _feedbackBuffer
              ..clear()
              ..write(full);
            _phase = _FeedbackPhase.done;
          });
        case MockFeedbackError(:final message):
          setState(() => _phase = _FeedbackPhase.error);
          _toast(message);
      }
    }
  }

  /// 把当前题收入会话并推进；最后一题触发落库收尾。
  Future<void> _advance({required bool includeCurrent}) async {
    final question = widget.plan.questions[_index];
    if (includeCurrent) {
      _qas.add(MockQa(
        question: question,
        answer: _answerController.text.trim(),
        feedback:
            _feedbackBuffer.isEmpty ? null : _feedbackBuffer.toString(),
      ));
    } else {
      _qas.add(MockQa(question: question));
    }
    if (_last) {
      await _finish();
      return;
    }
    setState(() {
      _index++;
      _answerController.clear();
      _feedbackBuffer.clear();
      _phase = _FeedbackPhase.none;
    });
  }

  /// 落库并跳到面试详情（与真实面试统一管理）。
  /// 先 go('/home') 复位路由栈再 push 详情，详情页返回即回首页。
  Future<void> _finish() async {
    setState(() => _persisting = true);
    try {
      final interviewId =
          await ref.read(mockInterviewServiceProvider).persistSession(
                position: widget.plan.position,
                qas: _qas,
              );
      if (!mounted) return;
      _toast('模拟面试完成，已生成 ${_qas.length} 张问题卡片');
      context.go('/home');
      context.push('/interviews/$interviewId');
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _persisting = false);
        _toast('保存失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_hasProgress) {
          context.pop();
          return;
        }
        final abandon = await _confirmAbandon();
        if (abandon && context.mounted) context.pop();
      },
      child: Scaffold(
        key: const Key('page_mock_session'),
        appBar: AppBar(
          title: Text(
              '模拟面试 · ${_index + 1} / ${widget.plan.questions.length}'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 面试官提问卡
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.record_voice_over,
                          color: AppTheme.gold, size: 18),
                      const SizedBox(width: 6),
                      Text('面试官提问',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: AppTheme.goldDeep,
                                fontWeight: FontWeight.w700,
                              )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.plan.questions[_index],
                    key: const Key('mock_question_text'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('mock_answer_field'),
              controller: _answerController,
              readOnly: _phase != _FeedbackPhase.none,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '我的回答',
                hintText: '像真实面试一样组织语言，写完提交给 AI 复盘',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_phase == _FeedbackPhase.none) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('btn_submit_answer'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.onGold,
                  ),
                  onPressed: _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('提交并获取 AI 反馈'),
                ),
              ),
              TextButton(
                key: const Key('btn_skip_question'),
                onPressed: () => _advance(includeCurrent: false),
                child: const Text('跳过此题'),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.smart_toy, color: AppTheme.gold, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _phase == _FeedbackPhase.streaming ? 'AI 反馈生成中…' : 'AI 逐题反馈',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.goldDeep,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                _feedbackBuffer.isEmpty ? '……' : _feedbackBuffer.toString(),
                key: const Key('mock_feedback_text'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (_phase == _FeedbackPhase.done || _phase == _FeedbackPhase.error)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('btn_next_question'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: AppTheme.onGold,
                    ),
                    onPressed:
                        _persisting ? null : () => _advance(includeCurrent: true),
                    icon: _persisting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: Text(
                        _persisting ? '正在生成卡片…' : (_last ? '完成并生成卡片' : '下一题')),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
