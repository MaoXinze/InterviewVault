# InterviewVault 开发计划

版本: v1.0（2026-09-26）
关联文档: [PRD.md](./PRD.md)（需求与表结构）、[../AGENTS.md](../AGENTS.md)（工作规则与安全红线）

---

## 0. 已确认决策（与 PRD 冲突时以本文和 PRD 执行修订节为准）

| # | 决策 | 内容 |
|---|---|---|
| 1 | 平台 | **MVP 仅 Android**；代码保持双端兼容，W4 后用 Codemagic 云构建补 iOS |
| 2 | 录音 | **P0 支持锁屏后台录音**：Android 前台服务（foregroundServiceType=microphone + 常驻通知） |
| 3 | 账号 | **完全无账号**：跳过登录，保留身份选择/隐私同意/数据管理，注销仅占位 |
| 4 | 导航 | 4 Tab + 中央 ⏺：首页 / 面试 / ⏺ / **回顾** / 我的 |
| 5 | Key 安全 | ai_configs 表不存 Key，Key 仅存 flutter_secure_storage |

## 1. 技术栈（定稿）

| 层 | 选型 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x + Dart 3 | Material 3，暗色模式优先，minSdk 26 |
| 状态管理 | Riverpod | 编译期安全、可测试 |
| 数据库 | drift（SQLite） | 类型安全 + watch() 响应式 + 内建迁移；预留 FTS5（P1 全文搜索） |
| 安全存储 | flutter_secure_storage | API Key 唯一存放处 |
| 录音 | record | 振幅流喂波形、暂停/继续 |
| 播放 | just_audio + audio_session | 精确 seek（标注跳转）、变速 |
| 本地转写 | whisper.cpp + dart:ffi（ffigen 绑定）+ Native Assets（hook/build.dart） | Isolate 执行不阻塞 UI |
| 音频解码 | FFmpegKit 社区维护 fork | 原版 ffmpeg_kit_flutter 已于 2025-01 退役（二进制下架）；W2 从 pub.dev 选维护中的 fork（如 ffmpeg_kit_flutter_new / 支持 16KB page-size 的 fork），功能不变：任意导入格式 → 16kHz 单声道 PCM |
| 网络 | dio + SSE 流式 | Key 仅注入用户配置的 baseUrl |
| 路由/模型 | go_router + freezed + json_serializable | 声明式路由、不可变数据类 |
| 导入/导出 | file_picker + path_provider + share_plus | 音频/简历导入；Markdown/JSON 导出分享 |
| 简历解析 | 粘贴文字为主；PDF 用纯 Dart 提取（syncfusion_flutter_pdf） | 图片 OCR 依赖 GMS，国内不可靠，P0 不做 |
| 测试 | drift 内存库 + mocktail + integration_test | 数据层单测优先 |

依赖引入节奏：W1 只装基础依赖；whisper.cpp 与 ffmpeg_kit 在 W2 引入。

## 2. 项目结构

```
lib/
├── main.dart
├── core/              # 主题（暗色优先）、路由、常量
├── data/
│   ├── database/      # drift：表定义 + DAO + 迁移
│   └── secure/        # KeyStorage 封装
├── network/           # LlmClient（dio）+ 安全拦截器
└── features/
    ├── onboarding/    # 身份/方向选择 + 隐私同意
    ├── home/          # 首页
    ├── interviews/    # 面试列表 + 详情（转写/标注/播放/导出，W2-W4 填充）
    ├── review/        # 「回顾」Tab：卡片库 + 翻卡模式
    ├── mock/          # 模拟面试
    ├── recording/     # 录音页
    ├── api_key/       # API Key 配置
    └── settings/      # 「我的」
```

## 3. 数据库 schema v1

六表：interviews / transcript_segments / annotations / flashcards / ai_configs / tags（完整 DDL 见 PRD.md 3.3）。要点：
- tags 预置 5 个系统标签：问题(question) / 回答(answer) / 亮点(highlight) / 失误(mistake) / 待改进(improvement)，每个带定义文案
- flashcards.tags 为 JSON 数组；卡片带 source_start_time/source_end_time 锚回录音
- 所有表带 created_at/updated_at；外键开启 PRAGMA foreign_keys=ON
- drift migrations 从 v1 起维护，测试断言升级路径

## 4. W1 执行步骤（本次）

**Step 0 仓库与文档**（已完成）：git init、.gitignore（含 *.g.dart/*.freezed.dart，clone 后需跑 build_runner）、docs/PRD.md、docs/PLAN.md、AGENTS.md。

**Step 1 项目初始化**：`flutter create --org com.interviewvault interview_vault`（在仓库根建 Android 工程）；Android minSdk 26；安装依赖：flutter_riverpod、drift、drift_flutter、sqlite3_flutter_libs、flutter_secure_storage、record、just_audio、audio_session、dio、go_router、freezed_annotation、json_annotation、intl、flutter_localizations + dev：build_runner、drift_dev、freezed、json_serializable、mocktail、flutter_lints。

**Step 2 核心层**：Material 3 暗色主题（默认深色可切浅色）；go_router StatefulShellRoute 四 Tab + 自定义底栏（中央 ⏺）；ProviderScope。

**Step 3 数据层（测试先行）**：drift 表定义 + DAO（CRUD + watch + 按标签筛选 + 级联删除）+ 迁移框架；freezed 模型；全量导出 JSON schema（带 version 字段）。单测：内存库 CRUD、标签筛选、级联删除、迁移路径。

**Step 4 API Key 管理**：KeyStorage（secure_storage 封装，per-provider 存取删）；Key 配置页（服务商下拉 OpenAI/DeepSeek/Kimi/通义/Claude/自定义、模型名、BaseURL、连接测试、"AI 调用由你的账户扣费"提示）；LlmClient（dio）：仅 host==用户配置 host 时注入 Authorization，日志拦截器脱敏 header，SSE 流式就绪。

**Step 5 四 Tab 骨架**：首页（快捷入口：新录音/导入/模拟面试；今日汇总、最近面试、"N 道题待回顾"占位）；面试（空列表+搜索筛选占位）；回顾（空卡片列表+"开始回顾"+标签筛选占位）；我的（API Key 管理**真实可用**、数据导出/删除占位、隐私政策占位页）；中央 ⏺ 进录音占位页。

**Step 6 质量门**：`flutter analyze` 0 issue；`flutter test` 全绿；Android 模拟器/真机走查四 Tab + 实测 Key 连接测试；分步 git 提交（中文 commit message）。

## 5. W2-W4 路线图

- **W2 录音+转写**：后台录音（前台服务+通知+波形+暂停/继续）、文件导入+格式确认页、ffmpeg 解码 16k PCM、whisper.cpp FFI 集成（ffigen + Native Assets + base/small 模型按需下载、后台下载进度）、逐字稿页面+编辑校正+手动说话人标记（面试官/我）
- **W3 标注+卡片+模拟面试**：标注（高亮/5 类标签/自定义标签/点标注跳播放）、卡片生成与详情（正面问题、背面回答+标注+笔记+AI 参考）、「回顾」翻卡模式、模拟面试全流程（岗位+简历+JD → AI 出题 5 道 → 文字作答 → 流式逐题反馈 → 生成卡片）；首次进入触发 Key 配置引导
- **W4 总结+导出+上架**：单次总结页、按日汇总、Markdown 导出（PRD 模板 + 快照测试锁格式）、JSON 全量导出与删除、隐私政策/协议全文、UI 打磨（暗色）、全链路 integration test（录音→转写→标注→卡片→导出）、AAB 打包提交 Play Console

## 6. 已装 21 个项目 skill 的触发点

位于 `.zcode/skills/`（仅本项目生效）：
- **W1**：dart-add-unit-test、flutter-tester、dart-run-static-analysis、riverpod、flutter-setup-declarative-routing
- **W2**：dart-use-ffigen、dart-setup-ffi-assets（whisper.cpp FFI 核心）、dart-fix-runtime-errors
- **W3**：flutter-best-practices、code-review
- **W4**：flutter-add-integration-test、dart-collect-coverage、store-listing-assets、owasp-mobile-security-checker
- 其余（effective-dart、flutter-apply-architecture-best-practices、flutter-fix-layout-issues、flutter-setup-localization、flutter-implement-json-serialization、dart-add-unit-test 等）按需触发

## 7. 风险与预案

- **whisper.cpp FFI 是最大技术风险**：ffigen/Native Assets 踩坑时备选社区包 whisper_flutter_new 或 sherpa-onnx（中文流式更优）
- 模型体积：base 约 142MB（iOS 蜂窝限制内）、small 约 466MB（提示 WiFi）；whisper.cpp 静态库每 ABI +10-20MB
- 原版 FFmpegKit 已退役（2025-01，arthenica 归档、二进制下架）：W2 必须用社区维护 fork，安装前在 pub.dev 确认最近更新时间与 Android 16KB page-size 支持；包体 +25MB/ABI，接受
- 国内安卓无 GMS：全栈不依赖 Google 服务组件
- CPU 转写速度预期：base 模型约 5-10 倍实时率（1 小时录音 6-12 分钟出稿）

## 8. 环境备注（Windows 开发机）

- 需要 Flutter SDK + Android Studio/SDK + Android 模拟器（或真机 USB 调试）
- clone 后先 `flutter pub get` + `dart run build_runner build --delete-conflicting-outputs`（*.g.dart/*.freezed.dart 已 gitignore）
- iOS 构建本机不可行；W4 后用 Codemagic 免费额度（500 分钟/月）
