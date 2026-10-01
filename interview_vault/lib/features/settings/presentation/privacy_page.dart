import 'package:flutter/material.dart';

import '../../../core/widgets/motion.dart';

/// 隐私政策与用户协议全文（PRD 2.10，上架前定稿）。
/// 各节用文本展开（模式⑤ Animated Text Disclosure），默认展开第一节。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DisclosureTile(
            title: '本地优先承诺',
            initiallyExpanded: true,
            children: const [
              Text(
                '你的录音、转写稿、标注、问题卡片全部保存在本机'
                '（SQLite 数据库 + 应用私有文件系统）。App 没有任何后端服务器：'
                '不上传、不遥测、不崩溃上报、不做用户统计。'
                '没有账号体系，我们根本无法识别你是谁。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          DisclosureTile(
            title: '我们收集什么',
            children: const [
              Text(
                '什么都不收集。本 App 不嵌入任何统计 SDK、广告 SDK 或'
                '推送 SDK，不请求通讯录、位置、剪贴板等与功能无关的权限，'
                '不读取与你无关的文件。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          DisclosureTile(
            title: '本地存储明细',
            children: const [
              Text(
                '结构化数据（面试记录、逐字稿、标注、问题卡片、标签、'
                'AI 服务商配置）保存在设备私有目录的 SQLite 数据库中；'
                '录音与导入的音频文件保存在应用私有目录下，'
                '均随卸载一并清除，其他 App 无法读取。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          DisclosureTile(
            title: 'API Key 安全',
            children: const [
              Text(
                'AI 能力使用你自己配置的服务商与 API Key。Key 只保存在'
                '系统安全存储（Android Keystore / iOS Keychain），'
                '不写入数据库、日志或任何导出文件。'
                '发起 AI 请求（出题、反馈、参考思路）时，App 从你的设备'
                '直连你填写的服务商地址，请求内容只有你与该服务商可见，'
                '本 App 不经手任何中转。由此产生的费用由你的账户承担。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          DisclosureTile(
            title: '权限使用',
            children: const [
              Text(
                '麦克风：仅在录音与模拟面试录音时使用，音频只存本机；\n'
                '通知：后台录音时显示常驻通知（前台服务必需），'
                '用于防止录音被系统杀掉；\n'
                '存储：仅在导入音频 / 简历 PDF、导出 JSON / Markdown 时，'
                '通过系统文件选择器读写你指定的文件；\n'
                '音频媒体：导入页可列出本机音频供你直接点选导入，'
                '列表仅在 App 内展示，不上传、不采集。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          DisclosureTile(
            title: '数据导出与删除',
            children: const [
              Text(
                '你可以在「我的」中随时把全部数据导出为 JSON（结构化备份）'
                '与 Markdown（复盘文稿）带走；也可以一键删除全部数据，'
                '删除即真删（数据库记录、录音文件、AI 配置与 Key 同步清除），'
                '不可恢复。卸载 App 即等同删除全部本地数据。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          DisclosureTile(
            title: '用户协议',
            children: const [
              Text(
                '1. 问渠是本地优先的个人面试复盘工具，'
                '按"现状"提供，不承诺适用于任何特定目的。\n'
                '2. 录音、转写、标注与卡片内容均由你自己产生与管理，'
                '请遵守所在场景的法律法规与保密义务，勿录制未获授权的对话。\n'
                '3. AI 能力由你自持的第三方服务提供，请求直连服务商，'
                '产生的费用与数据处理由你与服务商之间发生，与本项目无关。\n'
                '4. 请妥善备份：虽然提供全量导出功能，但设备丢失、'
                '损坏或误删造成的数据丢失，本项目不承担责任。\n'
                '5. 开始使用即表示你已阅读并同意本协议。',
              ),
            ],
          ),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('问渠 v1.0.0'),
            subtitle: Text('本政策自 2026-09-27 起生效 · 本地优先 · 无账号无后端'),
          ),
        ],
      ),
    );
  }
}
