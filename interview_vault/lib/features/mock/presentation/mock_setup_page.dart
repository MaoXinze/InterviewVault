import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/illustration.dart';
import '../mock_interview_service.dart';

/// 模拟面试配置页（PRD 2.9）：岗位方向 + 简历（粘贴文字/PDF 导入）+ JD
/// → AI 出题 5 道。图片简历不做 OCR（执行修订 #6），引导粘贴文字。
class MockSetupPage extends ConsumerStatefulWidget {
  const MockSetupPage({super.key, this.resumeImporter});

  /// 注入简历导入（选 PDF → 提取文字，返回 null = 用户取消）；测试用桩替换。
  final Future<String?> Function()? resumeImporter;

  /// 首页「模拟面试」统一入口：未配置 AI 时先给引导（PRD 2.1），
  /// 已配置则进入本页。
  static Future<void> enterMockInterview(
      BuildContext context, WidgetRef ref) async {
    final client = await ref.read(aiConfigServiceProvider).activeChatClient();
    if (!context.mounted) return;
    if (client == null) {
      final goConfigure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('mock_key_guide'),
          title: const Text('先配置你的 AI Key'),
          content: const Text(
              '模拟面试的出题与反馈会用你自己的 API Key 直连服务商，'
              'App 不内置 AI、不送额度。对话数据全程保存在本机。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('去配置'),
            ),
          ],
        ),
      );
      if (goConfigure == true && context.mounted) {
        await context.push('/api-key');
      }
      return;
    }
    await context.push('/mock');
  }

  @override
  ConsumerState<MockSetupPage> createState() => _MockSetupPageState();
}

class _MockSetupPageState extends ConsumerState<MockSetupPage> {
  final _positionController = TextEditingController();
  final _resumeController = TextEditingController();
  final _jdController = TextEditingController();
  bool _generating = false;

  @override
  void dispose() {
    _positionController.dispose();
    _resumeController.dispose();
    _jdController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 默认导入：系统选择器选 PDF → 纯 Dart 提取文字（失败给粘贴引导）。
  /// file_picker 13.x 为静态 API，直接返回文件列表。
  Future<String?> _defaultResumeImport() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null) return null;
    return extractResumeText(path);
  }

  Future<void> _importResume() async {
    try {
      final text =
          await (widget.resumeImporter ?? _defaultResumeImport)();
      if (!mounted || text == null) return;
      setState(() => _resumeController.text = text);
      _toast('已导入简历（${text.length} 字）');
    } on FormatException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _generate() async {
    final position = _positionController.text.trim();
    if (position.isEmpty) {
      _toast('请先填写岗位方向');
      return;
    }
    setState(() => _generating = true);
    try {
      final questions =
          await ref.read(mockInterviewServiceProvider).generateQuestions(
                position: position,
                resume: _resumeController.text,
                jd: _jdController.text,
              );
      if (!mounted) return;
      await context.push(
        '/mock/session',
        extra: MockSessionPlan(
          position: position,
          resume: _resumeController.text,
          jd: _jdController.text,
          questions: questions,
        ),
      );
      if (mounted) setState(() => _generating = false);
    } on MockAiException catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        _toast(e.message);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        _toast('出题失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('page_mock_setup'),
      appBar: AppBar(title: const Text('模拟面试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const CardIllustration.coach(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'AI 面试官将根据以下信息出 5 道题，逐题作答后生成复盘卡片',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('mock_position_field'),
            controller: _positionController,
            decoration: const InputDecoration(
              labelText: '岗位方向（必填）',
              hintText: '例如：客户端工程师',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('简历（可选，粘贴文字或导入 PDF）',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              OutlinedButton.icon(
                key: const Key('btn_import_resume'),
                onPressed: _generating ? null : _importResume,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('导入 PDF'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('mock_resume_field'),
            controller: _resumeController,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '粘贴简历正文……图片简历请把内容复制为文字',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('职位 JD（可选）',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            key: const Key('mock_jd_field'),
            controller: _jdController,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '粘贴职位描述，出题会更贴合岗位要求',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('btn_generate_questions'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.onGold,
              ),
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.psychology),
              label: Text(_generating ? '正在出题…' : 'AI 出题（5 道）'),
            ),
          ),
        ],
      ),
    );
  }
}
